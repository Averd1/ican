import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-Speech Service — wraps platform TTS for voice output.
///
/// The iCan app is primarily voice-driven for visually impaired users.
/// All navigation feedback and scene descriptions are spoken aloud.
class TtsService extends ChangeNotifier {
  final FlutterTts _flutterTts = FlutterTts();

  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  double _rate = 0.5; // 0.0 – 1.0
  double get rate => _rate;

  double _pitch = 1.0; // 0.5 – 2.0
  double get pitch => _pitch;

  /// Initialize TTS engine.
  Future<void> init() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(_rate);
    await _flutterTts.setPitch(_pitch);

    // On Windows, native callbacks fire on a non-platform thread which crashes.
    // Use awaitSpeakCompletion so speak() returns when done — no callbacks needed.
    if (Platform.isWindows) {
      await _flutterTts.awaitSpeakCompletion(true);
    } else {
      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        notifyListeners();
      });
      _flutterTts.setCancelHandler(() {
        _isSpeaking = false;
        notifyListeners();
      });
      _flutterTts.setErrorHandler((_) {
        _isSpeaking = false;
        notifyListeners();
      });
    }

    debugPrint('[TTS] Initialized.');
  }

  /// Speak the given text aloud.
  Future<void> speak(String text) async {
    if (text.isEmpty) return;

    try {
      _isSpeaking = true;
      notifyListeners();

      await _flutterTts.speak(text);
      debugPrint('[TTS] Speaking: "$text"');

      // On Windows, speak() awaits completion, so reset here.
      // On other platforms, the completion handler resets it.
      if (Platform.isWindows) {
        _isSpeaking = false;
        notifyListeners();
      }
    } on PlatformException catch (e) {
      debugPrint('[TTS] Platform error: ${e.code}');
      _isSpeaking = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[TTS] Error: $e');
      _isSpeaking = false;
      notifyListeners();
    }
  }

  /// Stop any ongoing speech immediately.
  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('[TTS] Error stopping: $e');
    }
    _isSpeaking = false;
    notifyListeners();
  }

  /// Update speech rate (0.0 slow – 1.0 fast).
  void setRate(double rate) {
    _rate = rate;
    _flutterTts.setSpeechRate(rate);
  }

  /// Update pitch (0.5 low – 2.0 high).
  void setPitch(double pitch) {
    _pitch = pitch;
    _flutterTts.setPitch(pitch);
  }
}
