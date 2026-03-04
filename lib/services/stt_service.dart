import 'dart:async';
import 'package:flutter/foundation.dart';

/// Speech-to-Text Service — wraps platform STT for voice input.
///
/// Listens for voice commands from the user (e.g., "closest McDonald's",
/// a street address, or menu navigation commands).
class SttService extends ChangeNotifier {
  bool _isListening = false;
  bool get isListening => _isListening;

  String _lastResult = '';
  String get lastResult => _lastResult;

  final _resultController = StreamController<String>.broadcast();
  Stream<String> get resultStream => _resultController.stream;

  /// Initialize STT engine and check permissions.
  Future<bool> init() async {
    // TODO: Initialize speech_to_text plugin
    // - Check microphone permissions
    // - Initialize recognizer
    debugPrint('[STT] Initialized.');
    return true;
  }

  /// Start listening for speech.
  Future<void> startListening() async {
    if (_isListening) return;
    _isListening = true;
    notifyListeners();
    // TODO: speech.listen(
    //   onResult: (result) { ... },
    //   listenFor: Duration(seconds: 30),
    //   localeId: 'en_US',
    // )
    debugPrint('[STT] Listening...');
  }

  /// Stop listening.
  Future<void> stopListening() async {
    _isListening = false;
    notifyListeners();
    // TODO: speech.stop()
    debugPrint('[STT] Stopped.');
  }

  /// Called internally when speech is recognized.
  void onResult(String recognizedText) {
    _lastResult = recognizedText;
    _resultController.add(recognizedText);
    notifyListeners();
    debugPrint('[STT] Recognized: "$recognizedText"');
  }

  @override
  void dispose() {
    _resultController.close();
    super.dispose();
  }
}
