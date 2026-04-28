import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../models/home_view_model.dart';
import '../models/settings_provider.dart';
import '../protocol/ble_protocol.dart';
import '../services/ble_service.dart';
import '../services/stt_service.dart';
import '../services/tts_service.dart';
import '../services/voice_control_service.dart';

enum VoiceCommandState { idle, listening, processing }

abstract class VoiceCommandTts {
  Future<void> stop();
  Future<void> speak(String text);
}

abstract class VoiceCommandStt {
  bool get available;
  Stream<String> get resultStream;
  Future<bool> init();
  Future<void> startListening();
  Future<void> stopListening();
}

abstract class VoiceCommandBle {
  Stream<String> get buttonEventStream;
}

abstract class VoiceCommandProcessor {
  Future<VoiceActionResult> handleTranscript(String transcript);
}

class VoiceCommandService extends ChangeNotifier {
  VoiceCommandService({
    required TtsService tts,
    required SttService stt,
    required BleService ble,
  }) : this.custom(
         tts: _TtsVoiceCommandAdapter(tts),
         stt: _SttVoiceCommandAdapter(stt),
         ble: _BleVoiceCommandAdapter(ble),
         target: AppVoiceControlTarget(ble: ble),
       );

  @visibleForTesting
  VoiceCommandService.custom({
    required VoiceCommandTts tts,
    required VoiceCommandStt stt,
    required VoiceCommandBle ble,
    AppVoiceControlTarget? target,
    VoiceCommandProcessor? processor,
  }) : _tts = tts,
       _stt = stt,
       _ble = ble,
       _voiceTarget = target,
       _voiceControl =
           processor ??
           _VoiceControlProcessor(VoiceControlService(target: target!)) {
    _buttonSub = _ble.buttonEventStream.listen(_onButtonEvent);
    _sttSub = _stt.resultStream.listen(_onSpeechResult);
  }

  final VoiceCommandTts _tts;
  final VoiceCommandStt _stt;
  final VoiceCommandBle _ble;
  final AppVoiceControlTarget? _voiceTarget;
  final VoiceCommandProcessor _voiceControl;

  StreamSubscription<String>? _buttonSub;
  StreamSubscription<String>? _sttSub;
  Timer? _silenceTimer;

  VoiceCommandState _state = VoiceCommandState.idle;
  String _partialText = '';
  String _lastResult = '';

  VoiceCommandState get state => _state;

  String get partialText => _partialText;

  String get lastResult => _lastResult;

  void attachHomeViewModel(HomeViewModel vm) {
    _voiceTarget?.homeViewModel = vm;
    _voiceTarget?.sceneService = vm.sceneService;
  }

  void attachRouter(GoRouter router) {}
  void attachSettings(SettingsProvider settings) {
    _voiceTarget?.settings = settings;
  }

  void _onButtonEvent(String event) {
    if (event == EyeEvents.buttonDouble) {
      activateVoiceCommand();
    }
  }

  Future<void> activateVoiceCommand() async {
    if (_state != VoiceCommandState.idle) return;

    _partialText = '';
    _setState(VoiceCommandState.listening);
    HapticFeedback.mediumImpact();

    await _tts.stop();
    await _tts.speak('Listening.');

    if (!_stt.available) {
      final ok = await _stt.init();
      if (!ok) {
        await _tts.speak(
          'Microphone not available. Check permissions in settings.',
        );
        _lastResult = 'Microphone not available.';
        _setState(VoiceCommandState.idle);
        return;
      }
    }

    await _stt.startListening();

    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(seconds: 8), () {
      if (_state == VoiceCommandState.listening) {
        _stt.stopListening();
        _onNoSpeech();
      }
    });
  }

  void _onSpeechResult(String text) {
    _silenceTimer?.cancel();
    if (_state != VoiceCommandState.listening) return;
    _partialText = text;
    notifyListeners();
    _processCommand(text);
  }

  Future<void> _onNoSpeech() async {
    await _tts.speak("I didn't hear anything. Double press to try again.");
    _lastResult = "I didn't hear anything.";
    _setState(VoiceCommandState.idle);
  }

  Future<void> _processCommand(String text) async {
    _setState(VoiceCommandState.processing);
    HapticFeedback.lightImpact();

    final normalized = text.toLowerCase().trim();
    debugPrint('[VoiceCmd] Recognized: "$normalized"');

    try {
      final result = await _voiceControl.handleTranscript(normalized);
      _lastResult = result.spokenConfirmation;
      await _tts.speak(result.spokenConfirmation);
    } catch (e) {
      debugPrint('[VoiceCmd] Action error: $e');
      _lastResult = 'Sorry, something went wrong.';
      await _tts.speak(_lastResult);
    }

    _setState(VoiceCommandState.idle);
  }

  void _setState(VoiceCommandState newState) {
    _state = newState;
    notifyListeners();
  }

  @override
  void dispose() {
    _buttonSub?.cancel();
    _sttSub?.cancel();
    _silenceTimer?.cancel();
    super.dispose();
  }
}

class _TtsVoiceCommandAdapter implements VoiceCommandTts {
  _TtsVoiceCommandAdapter(this._tts);

  final TtsService _tts;

  @override
  Future<void> speak(String text) => _tts.speak(text);

  @override
  Future<void> stop() => _tts.stop();
}

class _SttVoiceCommandAdapter implements VoiceCommandStt {
  _SttVoiceCommandAdapter(this._stt);

  final SttService _stt;

  @override
  bool get available => _stt.available;

  @override
  Stream<String> get resultStream => _stt.resultStream;

  @override
  Future<bool> init() => _stt.init();

  @override
  Future<void> startListening() => _stt.startListening();

  @override
  Future<void> stopListening() => _stt.stopListening();
}

class _BleVoiceCommandAdapter implements VoiceCommandBle {
  _BleVoiceCommandAdapter(this._ble);

  final BleService _ble;

  @override
  Stream<String> get buttonEventStream => _ble.buttonEventStream;
}

class _VoiceControlProcessor implements VoiceCommandProcessor {
  _VoiceControlProcessor(this._voiceControl);

  final VoiceControlService _voiceControl;

  @override
  Future<VoiceActionResult> handleTranscript(String transcript) {
    return _voiceControl.handleTranscript(transcript);
  }
}
