import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SttRecognitionError {
  const SttRecognitionError({required this.message, required this.permanent});

  final String message;
  final bool permanent;

  bool get isNoSpeech =>
      message == 'error_no_match' ||
      message == 'error_speech_timeout' ||
      message.toLowerCase().contains('no match') ||
      message.toLowerCase().contains('speech timeout');
}

class SttService extends ChangeNotifier {
  SttService._();
  static final SttService instance = SttService._();

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _available = false;
  bool get available => _available;

  bool _isListening = false;
  bool get isListening => _isListening;

  String _lastResult = '';
  String get lastResult => _lastResult;

  final _resultController = StreamController<String>.broadcast();
  Stream<String> get resultStream => _resultController.stream;

  final _partialResultController = StreamController<String>.broadcast();
  Stream<String> get partialResultStream => _partialResultController.stream;

  final _errorController = StreamController<SttRecognitionError>.broadcast();
  Stream<SttRecognitionError> get errorStream => _errorController.stream;

  SttRecognitionError? _lastError;
  SttRecognitionError? get lastError => _lastError;

  Future<bool> init() async {
    try {
      _available = await _speech.initialize(
        onError: (error) {
          debugPrint('[STT] Error: ${error.errorMsg}');
          _lastError = SttRecognitionError(
            message: error.errorMsg,
            permanent: error.permanent,
          );
          _errorController.add(_lastError!);
          _isListening = false;
          notifyListeners();
        },
        onStatus: (status) {
          debugPrint('[STT] Status: $status');
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
            notifyListeners();
          }
        },
      );
      debugPrint('[STT] Initialized. Available: $_available');
    } catch (e) {
      debugPrint('[STT] Init failed: $e');
      _available = false;
    }
    return _available;
  }

  Future<void> startListening({
    Duration listenFor = const Duration(seconds: 8),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    if (_isListening) return;
    if (!_available) {
      final ok = await init();
      if (!ok) return;
    }
    _isListening = true;
    _lastResult = '';
    _lastError = null;
    notifyListeners();

    await _speech.listen(
      onResult: (result) {
        _lastResult = result.recognizedWords;
        notifyListeners();
        if (_lastResult.isEmpty) return;
        if (result.finalResult) {
          _resultController.add(_lastResult);
          debugPrint('[STT] Final: "$_lastResult"');
        } else {
          _partialResultController.add(_lastResult);
        }
      },
      listenFor: listenFor,
      pauseFor: pauseFor,
      localeId: 'en_US',
      cancelOnError: true,
      listenMode: stt.ListenMode.confirmation,
    );

    debugPrint('[STT] Listening...');
  }

  Future<void> stopListening() async {
    if (!_isListening) return;
    await _speech.stop();
    _isListening = false;
    notifyListeners();
    debugPrint('[STT] Stopped.');
  }

  @override
  void dispose() {
    _speech.stop();
    _resultController.close();
    _partialResultController.close();
    _errorController.close();
    super.dispose();
  }
}
