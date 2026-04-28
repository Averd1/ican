import 'dart:async';
import 'package:flutter/foundation.dart';
import 'on_device_vision_service.dart';
import 'tts_service.dart';

/// Manages VLM model download lifecycle with TTS progress feedback.
/// Wraps the native ModelDownloadManager via OnDeviceVisionService.
class ModelDownloadService extends ChangeNotifier {
  final OnDeviceVisionService _visionService;
  final TtsService _ttsService;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  double _progress = 0.0;
  double get progress => _progress;

  String? _error;
  String? get error => _error;

  StreamSubscription? _downloadSub;
  int _lastSpokenPercent = -1;

  ModelDownloadService({
    required OnDeviceVisionService visionService,
    required TtsService ttsService,
  }) : _visionService = visionService,
       _ttsService = ttsService;

  /// Start downloading the offline model with TTS progress updates.
  Future<void> startDownload() async {
    if (_isDownloading) return;

    _isDownloading = true;
    _progress = 0.0;
    _error = null;
    _lastSpokenPercent = -1;
    notifyListeners();

    try {
      await _ttsService.speak('Starting offline model download.');
    } catch (_) {}

    _downloadSub = _visionService.startModelDownload().listen(
      (event) {
        _progress = event.progress;
        notifyListeners();
        _maybeSpeakProgress(event.progress);
        if (event.isComplete) {
          _onComplete();
        }
      },
      onError: (error) {
        _error = error.toString();
        _isDownloading = false;
        notifyListeners();
        debugPrint('[ModelDownload] Error: $error');
        try {
          _ttsService.speak('Model download failed. Please try again.');
        } catch (_) {}
      },
      onDone: () {
        if (_isDownloading) {
          _onComplete();
        }
      },
    );
  }

  void _onComplete() {
    _isDownloading = false;
    _progress = 1.0;
    notifyListeners();
    debugPrint('[ModelDownload] Download complete');
    try {
      _ttsService.speak(
        'Offline model ready. Scene descriptions will work without internet.',
      );
    } catch (_) {}
  }

  /// Speak progress at 25% intervals to keep the blind user informed.
  void _maybeSpeakProgress(double progress) {
    final percent = (progress * 100).round();
    // Speak at 25%, 50%, 75%
    for (final milestone in [25, 50, 75]) {
      if (percent >= milestone && _lastSpokenPercent < milestone) {
        _lastSpokenPercent = milestone;
        try {
          _ttsService.speak('Download $milestone percent complete.');
        } catch (_) {}
        break;
      }
    }
  }

  /// Cancel the current download.
  Future<void> cancelDownload() async {
    await _downloadSub?.cancel();
    _downloadSub = null;
    await _visionService.cancelModelDownload();
    _isDownloading = false;
    _progress = 0.0;
    notifyListeners();
  }

  /// Delete the downloaded model.
  Future<bool> deleteModel() async {
    final result = await _visionService.deleteModel();
    if (result) {
      _progress = 0.0;
      notifyListeners();
    }
    return result;
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    super.dispose();
  }
}
