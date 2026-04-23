import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../protocol/ble_protocol.dart';
import '../services/ble_service.dart';
import '../services/on_device_vision_service.dart';
import '../services/scene_description_service.dart';
import '../services/tts_service.dart';
import 'font_scale.dart';

export 'font_scale.dart';

class DescriptionEntry {
  final String text;
  final DateTime timestamp;
  bool isImportant;

  DescriptionEntry({
    required this.text,
    required this.timestamp,
    this.isImportant = false,
  });
}

class HomeViewModel extends ChangeNotifier {
  final SceneDescriptionService sceneService;
  final TtsService ttsService;

  HomeViewModel({
    required this.sceneService,
    required this.ttsService,
  }) {
    _init();
  }

  final List<DescriptionEntry> _history = [];
  String _lastDescription = '';
  bool _isPaused = false;
  bool _isProcessing = false;
  String? _lastImageFingerprint;
  DateTime? _lastImageTime;
  int _batteryPercent = -1;
  Timer? _processingTimeout;

  StreamSubscription<ObstacleAlert>? _obstacleSub;
  StreamSubscription<Uint8List>? _imageSub;
  StreamSubscription<void>? _captureSub;
  StreamSubscription<TelemetryPacket>? _telemetrySub;
  VoidCallback? _bleListener;

  // ── Live vision mode state ──
  bool _liveVisionActive = false;
  bool get liveVisionActive => _liveVisionActive;
  final OnDeviceVisionService _onDeviceVision = OnDeviceVisionService();
  StreamSubscription<Uint8List>? _liveImageSub;
  final Map<String, DateTime> _liveLastAnnounced = {};
  bool _liveProcessing = false;

  // ── Public getters ──
  BleConnectionState get caneConnection => BleService.instance.caneState;
  BleConnectionState get eyeConnection => BleService.instance.state;
  int get batteryPercent => _batteryPercent;

  String get lastDescription => _lastDescription;
  bool get isPaused => _isPaused;
  bool get isProcessing => _isProcessing;
  List<DescriptionEntry> get history => List.unmodifiable(_history);
  bool get hasAnyDevice => isEyeConnected || isCaneConnected;

  bool get isEyeConnected =>
      BleService.instance.state == BleConnectionState.connected;
  bool get isCaneConnected =>
      BleService.instance.caneState == BleConnectionState.connected;
  bool get canDescribe =>
      isEyeConnected && !_isProcessing && !_isPaused && !_liveVisionActive;

  void _init() {
    _bleListener = () {
      if (_liveVisionActive &&
          BleService.instance.state != BleConnectionState.connected) {
        _stopLiveVisionInternal();
      }
      // Reset stuck processing if Eye disconnects mid-capture
      if (!isEyeConnected && _isProcessing) {
        _isProcessing = false;
        _processingTimeout?.cancel();
      }
      notifyListeners();
    };
    BleService.instance.addListener(_bleListener!);

    _obstacleSub = BleService.instance.obstacleStream.listen((alert) {
      notifyListeners();
    });

    _captureSub = BleService.instance.captureStartedStream.listen((_) {
      if (!_liveVisionActive) {
        _isProcessing = true;
        notifyListeners();
        _startProcessingTimeout();
      }
    });

    _telemetrySub = BleService.instance.telemetryStream.listen((pkt) {
      _batteryPercent = pkt.batteryPercent;
      notifyListeners();
    });

    _imageSub =
        BleService.instance.imageStream.listen((Uint8List imageBytes) async {
      if (_isPaused || _liveVisionActive || _isProcessing) return;
      final now = DateTime.now();
      final fingerprint = _computeFingerprint(imageBytes);
      if (_lastImageFingerprint == fingerprint &&
          _lastImageTime != null &&
          now.difference(_lastImageTime!) < const Duration(seconds: 2)) {
        return;
      }
      _lastImageFingerprint = fingerprint;
      _lastImageTime = now;
      await _processImage(imageBytes);
    });

    _announceStartup();
  }

  void _startProcessingTimeout() {
    _processingTimeout?.cancel();
    _processingTimeout = Timer(const Duration(seconds: 15), () {
      if (_isProcessing) {
        _isProcessing = false;
        notifyListeners();
      }
    });
  }

  Future<void> _announceStartup() async {
    final parts = <String>['Home screen.'];
    if (isEyeConnected) parts.add('Camera connected.');
    if (isCaneConnected) parts.add('Cane connected.');
    if (!isEyeConnected && !isCaneConnected) {
      parts.add('No devices connected yet.');
    }
    await ttsService.speak(parts.join(' '));
  }

  // ── Live Vision Mode ──

  Future<void> startLiveVision() async {
    if (_liveVisionActive || !isEyeConnected) return;
    _liveVisionActive = true;
    _liveLastAnnounced.clear();
    notifyListeners();

    await BleService.instance.setEyeProfile(0);
    await BleService.instance.startLiveCapture(intervalMs: 1500);

    _liveImageSub =
        BleService.instance.imageStream.listen((Uint8List imageBytes) async {
      if (!_liveVisionActive || _liveProcessing) return;
      _liveProcessing = true;
      try {
        await _processLiveFrame(imageBytes);
      } catch (e) {
        debugPrint('[HomeViewModel] Live frame error: $e');
      }
      _liveProcessing = false;
    });

    try {
      await ttsService.speak('Live vision started.');
    } catch (_) {}
  }

  Future<void> stopLiveVision() async {
    if (!_liveVisionActive) return;
    await _stopLiveVisionInternal();
    try {
      await ttsService.speak('Live vision stopped.');
    } catch (_) {}
  }

  void _stopLiveVisionInternal() {
    _liveVisionActive = false;
    _liveProcessing = false;
    _liveImageSub?.cancel();
    _liveImageSub = null;
    _liveLastAnnounced.clear();
    BleService.instance.stopLiveCapture();
    BleService.instance.setEyeProfile(1);
    notifyListeners();
  }

  Future<void> _processLiveFrame(Uint8List imageBytes) async {
    if (imageBytes.length < 2 ||
        imageBytes[0] != 0xFF ||
        imageBytes[1] != 0xD8) return;

    final result = await _onDeviceVision.analyzeScene(imageBytes);
    if (!_liveVisionActive) return;

    final filtered = result.detectedObjects
        .where((o) => o.confidence >= 0.5)
        .toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    if (filtered.isEmpty) return;

    final now = DateTime.now();
    final toAnnounce = <String>[];

    for (final det in filtered.take(3)) {
      final lastTime = _liveLastAnnounced[det.label];
      if (lastTime != null &&
          now.difference(lastTime) < const Duration(seconds: 3)) {
        continue;
      }
      _liveLastAnnounced[det.label] = now;
      final position = _positionFromCenterX(det.centerX);
      toAnnounce.add('${det.label} $position');
    }

    if (toAnnounce.isNotEmpty && _liveVisionActive) {
      try {
        await ttsService.speak(toAnnounce.join(', '));
      } catch (_) {}
    }
  }

  static String _positionFromCenterX(double cx) {
    if (cx < 0.33) return 'on your left';
    if (cx < 0.66) return 'ahead';
    return 'on your right';
  }

  // ── Public methods ──
  void pauseDescriptions() {
    _isPaused = true;
    ttsService.stop();
    notifyListeners();
  }

  void resumeDescriptions() {
    _isPaused = false;
    notifyListeners();
  }

  void repeatLast() {
    if (_lastDescription.isNotEmpty) {
      ttsService.speak(_lastDescription);
    }
  }

  void describeNow() {
    if (!canDescribe) return;
    _isProcessing = true;
    notifyListeners();
    _startProcessingTimeout();
    BleService.instance.triggerEyeCapture();
  }

  void removeDescription(int index) {
    if (index >= 0 && index < _history.length) {
      _history.removeAt(index);
      notifyListeners();
    }
  }

  void toggleImportant(int index) {
    if (index >= 0 && index < _history.length) {
      _history[index].isImportant = !_history[index].isImportant;
      notifyListeners();
    }
  }

  void startScanForEye() => BleService.instance.startScan();
  void startScanForCane() => BleService.instance.startScanForCane();

  // ── Image processing ──
  static const _systemPrompt =
      'You are the vision system for a blind person wearing a chest camera. '
      'Speak in plain, conversational English — no markdown, no bullet points, no lists — '
      'everything you say is read aloud by a text-to-speech engine. '
      'Describe the scene in 4–6 sentences:\n'
      '1) Start with WHERE you are (room type, indoor/outdoor, general setting).\n'
      '2) SAFETY: name any obstacles, steps, edges, vehicles, or people. '
      'Use clock positions for direction (e.g. "chair at 2 o\'clock").\n'
      '3) Describe what is DIRECTLY AHEAD and within arm\'s reach.\n'
      '4) Read any visible text verbatim — signs, labels, screens, buttons.\n'
      '5) Mention notable objects, colors, or landmarks that help orientation.\n'
      'Be specific and spatial. Never say "I see" — describe as if you are the person\'s eyes.';

  Future<void> _processImage(Uint8List imageBytes) async {
    if (imageBytes.length < 2 ||
        imageBytes[0] != 0xFF ||
        imageBytes[1] != 0xD8) {
      _isProcessing = false;
      _processingTimeout?.cancel();
      notifyListeners();
      try {
        await ttsService
            .speak('The image was corrupted. Please try again.');
      } catch (_) {}
      return;
    }

    _isProcessing = true;
    notifyListeners();
    _startProcessingTimeout();

    final enhancedBytes = await compute(_enhanceImageForApi, imageBytes);

    try {
      final textBuffer = StringBuffer();
      final fullTextBuffer = StringBuffer();
      final sentenceEnd = RegExp(r'[.!?](?:\s|$)');

      await for (final chunk in sceneService.describeScene(
        enhancedBytes,
        systemPrompt: _systemPrompt,
        onStatusUpdate: (_, __) {},
      )) {
        if (_isPaused) continue;
        textBuffer.write(chunk);
        fullTextBuffer.write(chunk);

        while (true) {
          final accumulated = textBuffer.toString();
          final match = sentenceEnd.firstMatch(accumulated);
          if (match == null) break;
          final sentence = accumulated.substring(0, match.end).trim();
          final leftover = accumulated.substring(match.end);
          textBuffer.clear();
          textBuffer.write(leftover);
          try {
            await ttsService.speak(sentence);
          } catch (_) {}
        }
      }

      final remaining = textBuffer.toString().trim();
      if (remaining.isNotEmpty && !_isPaused) {
        try {
          await ttsService.speak(remaining);
        } catch (_) {}
      }

      final fullText = fullTextBuffer.toString().trim();
      if (fullText.isNotEmpty) {
        _lastDescription = fullText;
        _history.insert(
            0,
            DescriptionEntry(
              text: fullText,
              timestamp: DateTime.now(),
            ));
      }
    } catch (e) {
      debugPrint('[HomeViewModel] Error processing image: $e');
      try {
        await ttsService
            .speak('Sorry, there was an error processing the image.');
      } catch (_) {}
    }

    _isProcessing = false;
    _processingTimeout?.cancel();
    notifyListeners();
  }

  String _computeFingerprint(Uint8List data) {
    if (data.isEmpty) return 'empty';
    final headLen = data.length < 16 ? data.length : 16;
    final tailLen = data.length < 16 ? data.length : 16;
    final head = data.sublist(0, headLen);
    final tail = data.sublist(data.length - tailLen);
    return '${data.length}:${head.join(',')}:${tail.join(',')}';
  }

  @override
  void dispose() {
    if (_liveVisionActive) {
      _stopLiveVisionInternal();
    }
    _obstacleSub?.cancel();
    _imageSub?.cancel();
    _liveImageSub?.cancel();
    _captureSub?.cancel();
    _telemetrySub?.cancel();
    _processingTimeout?.cancel();
    if (_bleListener != null) {
      BleService.instance.removeListener(_bleListener!);
    }
    super.dispose();
  }
}

// ── Image enhancement (top-level for compute() isolate) ──

Uint8List _enhanceImageForApi(Uint8List rawBytes) {
  final decoded = img.decodeJpg(rawBytes);
  if (decoded == null) return rawBytes;

  var image = decoded;

  final isTruncated = rawBytes.length < 2 ||
      rawBytes[rawBytes.length - 2] != 0xFF ||
      rawBytes[rawBytes.length - 1] != 0xD9;
  if (isTruncated) {
    image = _cropBottomBlackBar(image);
  }

  final meanLuma = _computeMeanLuminance(image);
  if (meanLuma < 80) {
    image = img.normalize(image, min: 10, max: 245);
  } else if (meanLuma <= 180) {
    image = img.adjustColor(image, contrast: 1.1);
  }

  image = img.convolution(image,
    filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
    amount: 0.3,
  );

  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}

double _computeMeanLuminance(img.Image src) {
  double sum = 0;
  int count = 0;
  for (int y = 0; y < src.height; y += 8) {
    for (int x = 0; x < src.width; x += 8) {
      final p = src.getPixel(x, y);
      sum +=
          0.299 * p.r.toDouble() + 0.587 * p.g.toDouble() + 0.114 * p.b.toDouble();
      count++;
    }
  }
  return count > 0 ? sum / count : 128;
}

img.Image _cropBottomBlackBar(img.Image src) {
  const brightnessThreshold = 20;
  for (int y = src.height - 1; y >= src.height * 2 ~/ 3; y--) {
    for (int x = 0; x < src.width; x += 16) {
      final p = src.getPixel(x, y);
      if (p.r > brightnessThreshold ||
          p.g > brightnessThreshold ||
          p.b > brightnessThreshold) {
        final cropTo = y + 1;
        if (cropTo < src.height - 8) {
          return img.copyCrop(src,
              x: 0, y: 0, width: src.width, height: cropTo);
        }
        return src;
      }
    }
  }
  return src;
}
