import '../models/home_view_model.dart';
import '../models/settings_provider.dart';
import 'ble_service.dart';
import 'scene_description_service.dart';

enum VoiceActionType {
  describeNow,
  repeatLast,
  pauseDescriptions,
  resumeDescriptions,
  startLiveDetection,
  stopLiveDetection,
  setSpeechRate,
  setVolume,
  setDetailLevel,
  setPromptProfile,
  setVisionMode,
  setLiveVerbosity,
  contactCaretaker,
  scanDevices,
  announceStatus,
  announceVisionStatus,
  repeatLastDiagnostic,
  announceTime,
  help,
  unknown,
}

class VoiceIntent {
  final VoiceActionType action;
  final Map<String, Object?> slots;
  final double confidence;
  final String source;
  final String rawTranscript;

  const VoiceIntent({
    required this.action,
    this.slots = const {},
    required this.confidence,
    required this.source,
    required this.rawTranscript,
  });
}

class VoiceActionResult {
  final bool success;
  final String spokenConfirmation;
  final Map<String, Object?> changedState;

  const VoiceActionResult({
    required this.success,
    required this.spokenConfirmation,
    this.changedState = const {},
  });
}

class VoiceIntentParser {
  const VoiceIntentParser();

  VoiceIntent parse(String transcript) {
    final normalized = _normalize(transcript);
    if (normalized.isEmpty) {
      return _intent(transcript, VoiceActionType.unknown, confidence: 0);
    }

    if (_containsAny(normalized, ['describe', 'what around', 'scan scene'])) {
      return _intent(transcript, VoiceActionType.describeNow);
    }
    if (_containsAny(normalized, [
      'what failed',
      'last failure',
      'last diagnostic',
    ])) {
      return _intent(transcript, VoiceActionType.repeatLastDiagnostic);
    }
    if (_containsAny(normalized, ['vision status', 'vision mode status'])) {
      return _intent(transcript, VoiceActionType.announceVisionStatus);
    }
    if (_containsAny(normalized, ['repeat', 'say again', 'last image'])) {
      return _intent(transcript, VoiceActionType.repeatLast);
    }
    if (_containsAny(normalized, ['pause', 'stop talking', 'be quiet'])) {
      return _intent(transcript, VoiceActionType.pauseDescriptions);
    }
    if (_containsAny(normalized, ['resume', 'continue', 'keep going'])) {
      return _intent(transcript, VoiceActionType.resumeDescriptions);
    }
    if (_containsAny(normalized, ['start live', 'go live', 'live detection'])) {
      return _intent(transcript, VoiceActionType.startLiveDetection);
    }
    if (_containsAny(normalized, ['stop live', 'end live', 'exit live'])) {
      return _intent(transcript, VoiceActionType.stopLiveDetection);
    }
    if (_containsAny(normalized, ['status', 'battery', 'device status'])) {
      return _intent(transcript, VoiceActionType.announceStatus);
    }
    if (_containsAny(normalized, ['what time', 'time is it', 'current time'])) {
      return _intent(transcript, VoiceActionType.announceTime);
    }
    if (_containsAny(normalized, ['connect', 'reconnect', 'find device'])) {
      return _intent(transcript, VoiceActionType.scanDevices);
    }
    if (_containsAny(normalized, ['help', 'what can i say', 'commands'])) {
      return _intent(transcript, VoiceActionType.help);
    }
    if (_containsAny(normalized, ['contact caretaker', 'call caretaker'])) {
      return _intent(transcript, VoiceActionType.contactCaretaker);
    }

    final exactWpm = RegExp(
      r'(\d{2,3})\s*(?:words per minute|wpm)',
    ).firstMatch(normalized);
    if (exactWpm != null) {
      return _intent(
        transcript,
        VoiceActionType.setSpeechRate,
        slots: {'wpm': int.parse(exactWpm.group(1)!)},
      );
    }
    if (_containsAny(normalized, ['faster', 'speed up', 'talk faster'])) {
      return _intent(
        transcript,
        VoiceActionType.setSpeechRate,
        slots: {'delta': 0.1},
      );
    }
    if (_containsAny(normalized, ['slower', 'slow down', 'talk slower'])) {
      return _intent(
        transcript,
        VoiceActionType.setSpeechRate,
        slots: {'delta': -0.1},
      );
    }

    final exactVolume = RegExp(
      r'(?:volume|loudness)\s*(?:to)?\s*(\d{1,3})',
    ).firstMatch(normalized);
    if (exactVolume != null) {
      return _intent(
        transcript,
        VoiceActionType.setVolume,
        slots: {'percent': int.parse(exactVolume.group(1)!)},
      );
    }
    if (_containsAny(normalized, ['louder', 'volume up'])) {
      return _intent(
        transcript,
        VoiceActionType.setVolume,
        slots: {'delta': 0.1},
      );
    }
    if (_containsAny(normalized, ['quieter', 'volume down', 'softer'])) {
      return _intent(
        transcript,
        VoiceActionType.setVolume,
        slots: {'delta': -0.1},
      );
    }

    if (_containsAny(normalized, ['live less chatty', 'less live detail'])) {
      return _intent(
        transcript,
        VoiceActionType.setLiveVerbosity,
        slots: {'liveVerbosity': LiveDetectionVerbosity.minimal.name},
      );
    }
    if (_containsAny(normalized, ['live full detail', 'more live detail'])) {
      return _intent(
        transcript,
        VoiceActionType.setLiveVerbosity,
        slots: {'liveVerbosity': LiveDetectionVerbosity.full.name},
      );
    }

    if (_containsAny(normalized, ['less chatty', 'be brief', 'shorter'])) {
      return _intent(
        transcript,
        VoiceActionType.setDetailLevel,
        slots: {'detailLevel': DetailLevel.brief.name},
      );
    }
    if (_containsAny(normalized, ['more detail', 'detailed', 'explain more'])) {
      return _intent(
        transcript,
        VoiceActionType.setDetailLevel,
        slots: {'detailLevel': DetailLevel.detailed.name},
      );
    }

    if (_containsAny(normalized, [
      'only hazards',
      'only tell me hazards',
      'safety mode',
      'focus on hazards',
    ])) {
      return _intent(
        transcript,
        VoiceActionType.setPromptProfile,
        slots: {'promptProfile': PromptProfile.safety.name, 'selfTune': true},
      );
    }
    if (_containsAny(normalized, [
      'read signs',
      'read text first',
      'reading mode',
    ])) {
      return _intent(
        transcript,
        VoiceActionType.setPromptProfile,
        slots: {'promptProfile': PromptProfile.reading.name},
      );
    }
    if (_containsAny(normalized, [
      'navigation mode',
      'landmarks',
      'where to walk',
    ])) {
      return _intent(
        transcript,
        VoiceActionType.setPromptProfile,
        slots: {'promptProfile': PromptProfile.navigation.name},
      );
    }
    if (_containsAny(normalized, ['balanced mode', 'normal mode'])) {
      return _intent(
        transcript,
        VoiceActionType.setPromptProfile,
        slots: {'promptProfile': PromptProfile.balanced.name},
      );
    }

    if (_containsAny(normalized, [
      'use local',
      'offline mode',
      'local model',
    ])) {
      return _intent(
        transcript,
        VoiceActionType.setVisionMode,
        slots: {'visionMode': VisionMode.offlineOnly.name},
      );
    }
    if (_containsAny(normalized, ['use cloud', 'cloud mode', 'gemini'])) {
      return _intent(
        transcript,
        VoiceActionType.setVisionMode,
        slots: {'visionMode': VisionMode.cloudOnly.name},
      );
    }
    if (_containsAny(normalized, ['auto mode', 'automatic mode'])) {
      return _intent(
        transcript,
        VoiceActionType.setVisionMode,
        slots: {'visionMode': VisionMode.auto.name},
      );
    }

    return _intent(transcript, VoiceActionType.unknown, confidence: 0.2);
  }

  static VoiceIntent _intent(
    String rawTranscript,
    VoiceActionType action, {
    Map<String, Object?> slots = const {},
    double confidence = 1.0,
  }) {
    return VoiceIntent(
      action: action,
      slots: slots,
      confidence: confidence,
      source: 'rule',
      rawTranscript: rawTranscript,
    );
  }

  static bool _containsAny(String text, List<String> phrases) =>
      phrases.any(text.contains);

  static String _normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').trim();
}

abstract class VoiceControlTarget {
  double get speechRate;
  double get volume;
  int get wordsPerMinute;
  DetailLevel get detailLevel;
  PromptProfile get promptProfile;
  LiveDetectionVerbosity get liveDetectionVerbosity;
  VisionMode get visionMode;
  String get deviceStatusSummary;
  String get visionStatusSummary;
  String get latestFailureSummary;
  String get latestSceneSummary;
  bool get canDescribeNow;
  bool get canRepeatLast;
  bool get canControlDescriptions;
  bool get canStartLiveDetection;
  bool get canStopLiveDetection;
  bool get canScanDevices;

  Future<void> setSpeechRate(double rate);
  Future<void> setVolume(double volume);
  Future<void> setDetailLevel(DetailLevel level);
  Future<void> setPromptProfile(PromptProfile profile);
  Future<void> setLiveDetectionVerbosity(LiveDetectionVerbosity verbosity);
  Future<void> setVisionMode(VisionMode mode);
  Future<String> describeNow();
  Future<void> repeatLast();
  Future<void> pauseDescriptions();
  Future<void> resumeDescriptions();
  Future<void> startLiveDetection();
  Future<void> stopLiveDetection();
  Future<void> scanDevices();
}

class AppVoiceControlTarget implements VoiceControlTarget {
  SettingsProvider? settings;
  SceneDescriptionService? sceneService;
  HomeViewModel? homeViewModel;
  final BleService ble;

  AppVoiceControlTarget({required this.ble});

  @override
  double get speechRate => settings?.speechRate ?? 0.5;

  @override
  double get volume => settings?.volume ?? 1.0;

  @override
  int get wordsPerMinute => settings?.wordsPerMinute ?? 200;

  @override
  DetailLevel get detailLevel => settings?.detailLevel ?? DetailLevel.detailed;

  @override
  PromptProfile get promptProfile =>
      settings?.promptProfile ?? PromptProfile.balanced;

  @override
  LiveDetectionVerbosity get liveDetectionVerbosity =>
      settings?.liveDetectionVerbosity ?? LiveDetectionVerbosity.positional;

  @override
  VisionMode get visionMode => sceneService?.mode ?? VisionMode.auto;

  @override
  String get latestSceneSummary {
    final description = homeViewModel?.lastDescription ?? '';
    return description.isEmpty ? 'No scene description yet.' : description;
  }

  @override
  String get latestFailureSummary =>
      homeViewModel?.latestFailureSummary ?? 'No failure recorded.';

  @override
  String get visionStatusSummary =>
      homeViewModel?.visionStatusSummary ??
      'Vision mode ${visionMode.label}. No scene pipeline has run yet.';

  @override
  String get deviceStatusSummary {
    final eye = ble.state == BleConnectionState.connected
        ? 'Camera connected.'
        : 'Camera disconnected.';
    final cane = ble.caneState == BleConnectionState.connected
        ? 'Cane connected.'
        : 'Cane disconnected.';
    final telemetry = ble.lastTelemetry;
    final battery = telemetry == null
        ? ''
        : ' Battery ${telemetry.batteryPercent} percent.';
    return '$eye $cane$battery';
  }

  @override
  bool get canDescribeNow => homeViewModel?.canDescribe ?? false;

  @override
  bool get canRepeatLast =>
      (homeViewModel?.lastDescription ?? '').trim().isNotEmpty;

  @override
  bool get canControlDescriptions => homeViewModel != null;

  @override
  bool get canStartLiveDetection =>
      (homeViewModel?.isEyeConnected ?? false) &&
      !(homeViewModel?.liveVisionActive ?? false);

  @override
  bool get canStopLiveDetection => homeViewModel?.liveVisionActive ?? false;

  @override
  bool get canScanDevices => homeViewModel != null;

  @override
  Future<void> setSpeechRate(double rate) async {
    settings?.setSpeechRate(rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    settings?.setVolume(volume);
  }

  @override
  Future<void> setDetailLevel(DetailLevel level) async {
    settings?.setDetailLevel(level);
  }

  @override
  Future<void> setPromptProfile(PromptProfile profile) async {
    settings?.setPromptProfile(profile);
  }

  @override
  Future<void> setLiveDetectionVerbosity(
    LiveDetectionVerbosity verbosity,
  ) async {
    settings?.setLiveDetectionVerbosity(verbosity);
  }

  @override
  Future<void> setVisionMode(VisionMode mode) async {
    await sceneService?.setMode(mode);
  }

  @override
  Future<String> describeNow() async {
    final vm = homeViewModel;
    if (vm == null) return 'Home is not ready yet.';
    return vm.describeNow();
  }

  @override
  Future<void> repeatLast() async => homeViewModel?.repeatLast();

  @override
  Future<void> pauseDescriptions() async => homeViewModel?.pauseDescriptions();

  @override
  Future<void> resumeDescriptions() async =>
      homeViewModel?.resumeDescriptions();

  @override
  Future<void> startLiveDetection() async => homeViewModel?.startLiveVision();

  @override
  Future<void> stopLiveDetection() async => homeViewModel?.stopLiveVision();

  @override
  Future<void> scanDevices() async {
    homeViewModel?.startScanForEye();
    homeViewModel?.startScanForCane();
  }
}

class VoiceControlService {
  final VoiceIntentParser parser;
  final VoiceControlTarget target;

  const VoiceControlService({
    this.parser = const VoiceIntentParser(),
    required this.target,
  });

  Future<VoiceActionResult> handleTranscript(String transcript) {
    return execute(parser.parse(transcript));
  }

  Future<VoiceActionResult> execute(VoiceIntent intent) async {
    switch (intent.action) {
      case VoiceActionType.describeNow:
        if (!target.canDescribeNow) {
          return _fail('Camera is not ready. Connect the iCan Eye first.');
        }
        final outcome = await target.describeNow();
        return _ok(outcome);
      case VoiceActionType.repeatLast:
        if (!target.canRepeatLast) {
          return _fail('No scene description yet.');
        }
        await target.repeatLast();
        return _ok('Repeating the last description.');
      case VoiceActionType.pauseDescriptions:
        if (!target.canControlDescriptions) {
          return _fail('Home is not ready yet.');
        }
        await target.pauseDescriptions();
        return _ok('Paused.');
      case VoiceActionType.resumeDescriptions:
        if (!target.canControlDescriptions) {
          return _fail('Home is not ready yet.');
        }
        await target.resumeDescriptions();
        return _ok('Resumed.');
      case VoiceActionType.startLiveDetection:
        if (!target.canStartLiveDetection) {
          return _fail('Live detection needs the iCan Eye connected.');
        }
        await target.startLiveDetection();
        return _ok('Starting live detection.');
      case VoiceActionType.stopLiveDetection:
        if (!target.canStopLiveDetection) {
          return _fail('Live detection is not running.');
        }
        await target.stopLiveDetection();
        return _ok('Stopping live detection.');
      case VoiceActionType.scanDevices:
        if (!target.canScanDevices) {
          return _fail('Home is not ready yet.');
        }
        await target.scanDevices();
        return _ok('Scanning for devices.');
      case VoiceActionType.announceStatus:
        return _ok(target.deviceStatusSummary);
      case VoiceActionType.announceVisionStatus:
        return _ok(target.visionStatusSummary);
      case VoiceActionType.repeatLastDiagnostic:
        return _ok(target.latestFailureSummary);
      case VoiceActionType.announceTime:
        return _ok(_timeConfirmation(DateTime.now()));
      case VoiceActionType.help:
        return _ok(_helpText);
      case VoiceActionType.contactCaretaker:
        return _ok(
          'Caretaker contact card is ready. Latest scene: ${target.latestSceneSummary}',
        );
      case VoiceActionType.setSpeechRate:
        return _setSpeechRate(intent);
      case VoiceActionType.setVolume:
        return _setVolume(intent);
      case VoiceActionType.setDetailLevel:
        return _setDetailLevel(intent);
      case VoiceActionType.setPromptProfile:
        return _setPromptProfile(intent);
      case VoiceActionType.setVisionMode:
        return _setVisionMode(intent);
      case VoiceActionType.setLiveVerbosity:
        return _setLiveVerbosity(intent);
      case VoiceActionType.unknown:
        return const VoiceActionResult(
          success: false,
          spokenConfirmation:
              "I didn't understand. Say help for available commands.",
        );
    }
  }

  Future<VoiceActionResult> _setSpeechRate(VoiceIntent intent) async {
    final wpm = intent.slots['wpm'];
    final delta = intent.slots['delta'];
    final rate = wpm is int
        ? SettingsProvider.wpmToRate(wpm)
        : (target.speechRate + ((delta as double?) ?? 0)).clamp(0.0, 1.0);
    await target.setSpeechRate(rate);
    final changedWpm = (100 + (rate * 200)).round();
    return _ok('Speed set to $changedWpm words per minute.', {
      'speechRate': rate,
      'wordsPerMinute': changedWpm,
    });
  }

  Future<VoiceActionResult> _setVolume(VoiceIntent intent) async {
    final percent = intent.slots['percent'];
    final delta = intent.slots['delta'];
    final volume = percent is int
        ? (percent.clamp(0, 100) / 100.0)
        : (target.volume + ((delta as double?) ?? 0)).clamp(0.0, 1.0);
    await target.setVolume(volume);
    final changedPercent = (volume * 100).round();
    return _ok('Volume set to $changedPercent percent.', {
      'volume': volume,
      'volumePercent': changedPercent,
    });
  }

  Future<VoiceActionResult> _setDetailLevel(VoiceIntent intent) async {
    final level = DetailLevel.values.firstWhere(
      (value) => value.name == intent.slots['detailLevel'],
      orElse: () => target.detailLevel,
    );
    await target.setDetailLevel(level);
    if (level == DetailLevel.brief) {
      await target.setLiveDetectionVerbosity(LiveDetectionVerbosity.minimal);
    }
    return _ok(
      level == DetailLevel.brief
          ? 'Brief mode on. I will keep descriptions shorter.'
          : 'Detailed mode on. I will describe more context.',
      {'detailLevel': level.name},
    );
  }

  Future<VoiceActionResult> _setPromptProfile(VoiceIntent intent) async {
    final profile = PromptProfile.values.firstWhere(
      (value) => value.name == intent.slots['promptProfile'],
      orElse: () => target.promptProfile,
    );
    await target.setPromptProfile(profile);

    final changes = <String, Object?>{'promptProfile': profile.name};
    if (intent.slots['selfTune'] == true && profile == PromptProfile.safety) {
      await target.setDetailLevel(DetailLevel.brief);
      await target.setLiveDetectionVerbosity(LiveDetectionVerbosity.minimal);
      changes['detailLevel'] = DetailLevel.brief.name;
      changes['liveVerbosity'] = LiveDetectionVerbosity.minimal.name;
    }

    return _ok(_profileConfirmation(profile), changes);
  }

  Future<VoiceActionResult> _setVisionMode(VoiceIntent intent) async {
    final mode = VisionMode.values.firstWhere(
      (value) => value.name == intent.slots['visionMode'],
      orElse: () => target.visionMode,
    );
    await target.setVisionMode(mode);
    return _ok('${mode.label} vision mode on.', {'visionMode': mode.name});
  }

  Future<VoiceActionResult> _setLiveVerbosity(VoiceIntent intent) async {
    final verbosity = LiveDetectionVerbosity.values.firstWhere(
      (value) => value.name == intent.slots['liveVerbosity'],
      orElse: () => target.liveDetectionVerbosity,
    );
    await target.setLiveDetectionVerbosity(verbosity);
    return _ok('Live detection set to ${verbosity.label.toLowerCase()}.', {
      'liveVerbosity': verbosity.name,
    });
  }

  static VoiceActionResult _ok(
    String confirmation, [
    Map<String, Object?> changedState = const {},
  ]) {
    return VoiceActionResult(
      success: true,
      spokenConfirmation: confirmation,
      changedState: changedState,
    );
  }

  static VoiceActionResult _fail(String confirmation) {
    return VoiceActionResult(success: false, spokenConfirmation: confirmation);
  }

  static String _profileConfirmation(PromptProfile profile) {
    switch (profile) {
      case PromptProfile.balanced:
        return 'Balanced mode on.';
      case PromptProfile.safety:
        return 'Safety mode on. I will prioritize hazards.';
      case PromptProfile.navigation:
        return 'Navigation mode on. I will prioritize landmarks and walking cues.';
      case PromptProfile.reading:
        return 'Reading mode on. I will read visible text first.';
    }
  }

  static String _timeConfirmation(DateTime now) {
    final hour = now.hour > 12
        ? now.hour - 12
        : (now.hour == 0 ? 12 : now.hour);
    final period = now.hour >= 12 ? 'PM' : 'AM';
    final minute = now.minute.toString().padLeft(2, '0');
    return "It's $hour:$minute $period.";
  }

  static const _helpText =
      'You can say: describe, repeat, pause, resume, start live detection, '
      'stop live detection, status, talk faster, talk slower, louder, quieter, '
      'only hazards, read signs first, use local model, use cloud, vision status, '
      'what failed, or contact caretaker.';
}
