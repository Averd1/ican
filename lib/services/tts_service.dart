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

    if (Platform.isIOS) {
      // Force audio to play even if the physical silent switch is engaged,
      // and ensure it prefers the main speaker or Bluetooth.
      await _flutterTts.setSharedInstance(true);
      await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions.interruptSpokenAudioAndMixWithOthers
        ],
        IosTextToSpeechAudioMode.defaultMode,
      );
    }

    // Use awaitSpeakCompletion on all platforms:
    // - Windows: native callbacks fire on a non-platform thread (crashes).
    // - iOS: same threading issue — flutter_tts fires completion/cancel/error
    //   handlers from the native audio thread, which violates Flutter's
    //   platform-channel threading contract and causes data loss.
    // awaitSpeakCompletion(true) makes speak() block until done on the Dart
    // side so we never need native-thread callbacks at all.
    if (Platform.isWindows || Platform.isIOS || Platform.isMacOS) {
      await _flutterTts.awaitSpeakCompletion(true);
      debugPrint('[TTS] Using awaitSpeakCompletion mode (platform: ${Platform.operatingSystem}).');
    } else {
      // Android: native callbacks are dispatched on the platform thread, so
      // callbacks are safe here. Wrap in Future.microtask anyway as a guard.
      _flutterTts.setCompletionHandler(() {
        Future.microtask(() {
          _isSpeaking = false;
          notifyListeners();
        });
      });
      _flutterTts.setCancelHandler(() {
        Future.microtask(() {
          _isSpeaking = false;
          notifyListeners();
        });
      });
      _flutterTts.setErrorHandler((msg) {
        debugPrint('[TTS] Native error: $msg');
        Future.microtask(() {
          _isSpeaking = false;
          notifyListeners();
        });
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

      // Log before speak so we always see what was requested, even if TTS throws.
      debugPrint('[TTS] Speaking (${text.length} chars): "$text"');
      await _flutterTts.speak(text);

      // awaitSpeakCompletion platforms: speak() blocks until done, so reset here.
      // Android callback platforms: completion handler resets it async.
      if (Platform.isWindows || Platform.isIOS || Platform.isMacOS) {
        _isSpeaking = false;
        notifyListeners();
      }
    } on PlatformException catch (e) {
      debugPrint('[TTS] Platform error: ${e.code} — "${e.message}"');
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
