import 'package:flutter/foundation.dart';

/// Text-to-Speech Service — wraps platform TTS for voice output.
///
/// The iCan app is primarily voice-driven for visually impaired users.
/// All navigation feedback and scene descriptions are spoken aloud.
class TtsService extends ChangeNotifier {
  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  double _rate = 0.5; // 0.0 – 1.0
  double get rate => _rate;

  double _pitch = 1.0; // 0.5 – 2.0
  double get pitch => _pitch;

  /// Initialize TTS engine.
  Future<void> init() async {
    // TODO: Initialize flutter_tts
    // - Set language to "en-US"
    // - Set rate and pitch
    // - Register completion callback
    debugPrint('[TTS] Initialized.');
  }

  /// Speak the given text aloud.
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    _isSpeaking = true;
    notifyListeners();
    // TODO: Call flutterTts.speak(text)
    debugPrint('[TTS] Speaking: "$text"');
    // On completion:
    _isSpeaking = false;
    notifyListeners();
  }

  /// Stop any ongoing speech immediately.
  Future<void> stop() async {
    // TODO: Call flutterTts.stop()
    _isSpeaking = false;
    notifyListeners();
  }

  /// Update speech rate (0.0 slow – 1.0 fast).
  void setRate(double rate) {
    _rate = rate;
    // TODO: flutterTts.setSpeechRate(rate)
  }

  /// Update pitch (0.5 low – 2.0 high).
  void setPitch(double pitch) {
    _pitch = pitch;
    // TODO: flutterTts.setPitch(pitch)
  }
}
