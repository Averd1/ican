import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../protocol/ble_protocol.dart';
import '../services/ble_service.dart';
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

  // ── Private state ──
  final List<DescriptionEntry> _history = [];
  String _lastDescription = '';
  bool _isPaused = false;
  bool _isProcessing = false;
  FontScale _fontScale = FontScale.normal;
  String? _lastImageFingerprint;
  DateTime? _lastImageTime;
  int _batteryPercent = -1;

  StreamSubscription<ObstacleAlert>? _obstacleSub;
  StreamSubscription<Uint8List>? _imageSub;
  StreamSubscription<void>? _captureSub;
  StreamSubscription<TelemetryPacket>? _telemetrySub;
  VoidCallback? _bleListener;

  // ── Public getters ──
  BleConnectionState get caneConnection => BleService.instance.caneState;
  BleConnectionState get eyeConnection => BleService.instance.state;
  int get batteryPercent => _batteryPercent;

  String get lastDescription => _lastDescription;
  bool get isPaused => _isPaused;
  bool get isProcessing => _isProcessing;
  FontScale get fontScale => _fontScale;
  List<DescriptionEntry> get history => List.unmodifiable(_history);

  bool get isEyeConnected =>
      BleService.instance.state == BleConnectionState.connected;
  bool get isCaneConnected =>
      BleService.instance.caneState == BleConnectionState.connected;
  bool get canDescribe => isEyeConnected && !_isProcessing && !_isPaused;

  // ── Initialization ──
  void _init() {
    _bleListener = () => notifyListeners();
    BleService.instance.addListener(_bleListener!);

    _obstacleSub = BleService.instance.obstacleStream.listen((alert) {
      // Obstacle alerts are handled by the HazardAlertBanner directly
      // via its own stream subscription — ViewModel just notifies.
      notifyListeners();
    });

    _captureSub = BleService.instance.captureStartedStream.listen((_) {
      _isProcessing = true;
      notifyListeners();
    });

    _telemetrySub = BleService.instance.telemetryStream.listen((pkt) {
      _batteryPercent = pkt.batteryPercent;
      notifyListeners();
    });

    _imageSub =
        BleService.instance.imageStream.listen((Uint8List imageBytes) async {
      if (_isPaused) return;
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
    BleService.instance.triggerEyeCapture();
  }

  void setFontScale(FontScale scale) {
    _fontScale = scale;
    notifyListeners();
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
      notifyListeners();
      try {
        await ttsService
            .speak('The image was corrupted. Please try again.');
      } catch (_) {}
      return;
    }

    _isProcessing = true;
    notifyListeners();

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
    _obstacleSub?.cancel();
    _imageSub?.cancel();
    _captureSub?.cancel();
    _telemetrySub?.cancel();
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
