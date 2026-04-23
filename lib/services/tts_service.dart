import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService extends ChangeNotifier {
  TtsService._();
  static final TtsService instance = TtsService._();

  final FlutterTts _flutterTts = FlutterTts();

  bool _initialized = false;
  bool get initialized => _initialized;

  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  double _rate = 0.5;
  double get rate => _rate;

  double _pitch = 1.0;
  double get pitch => _pitch;

  double _volume = 1.0;
  double get volume => _volume;

  Future<void> init() async {
    if (_initialized) return;

    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(_rate);
    await _flutterTts.setPitch(_pitch);
    await _flutterTts.setVolume(_volume);

    if (Platform.isIOS) {
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

    if (Platform.isWindows || Platform.isIOS || Platform.isMacOS) {
      await _flutterTts.awaitSpeakCompletion(true);
      debugPrint('[TTS] Using awaitSpeakCompletion mode (platform: ${Platform.operatingSystem}).');
    } else {
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

    _initialized = true;
    debugPrint('[TTS] Initialized.');
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;

    try {
      _isSpeaking = true;
      notifyListeners();

      debugPrint('[TTS] Speaking (${text.length} chars): "$text"');
      await _flutterTts.speak(text);

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

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('[TTS] Error stopping: $e');
    }
    _isSpeaking = false;
    notifyListeners();
  }

  void setRate(double rate) {
    _rate = rate;
    _flutterTts.setSpeechRate(rate);
  }

  void setPitch(double pitch) {
    _pitch = pitch;
    _flutterTts.setPitch(pitch);
  }

  void setVolume(double vol) {
    _volume = vol.clamp(0.0, 1.0);
    _flutterTts.setVolume(_volume);
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }
}
