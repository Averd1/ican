import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/font_scale.dart';
import '../services/tts_service.dart';

enum VoiceType {
  male('Male'),
  female('Female'),
  neutral('Neutral');

  const VoiceType(this.label);
  final String label;
}

enum DetailLevel {
  brief('Brief'),
  detailed('Detailed');

  const DetailLevel(this.label);
  final String label;
}

enum HazardSensitivity {
  low('Low', 40),
  medium('Medium', 80),
  high('High', 150);

  const HazardSensitivity(this.label, this.thresholdCm);
  final String label;
  final int thresholdCm;
}

enum LiveDetectionVerbosity {
  minimal('Minimal', 'Top object, name only'),
  positional('Positional', 'Top object with direction'),
  full('Full', 'Up to 3 objects with direction');

  const LiveDetectionVerbosity(this.label, this.description);
  final String label;
  final String description;
}

enum PromptProfile {
  balanced(
    'Balanced',
    'General scene description with safety, text, and landmarks',
  ),
  safety('Safety', 'Hazards, motion, crossings, obstacles, and people first'),
  navigation(
    'Navigation',
    'Doors, paths, landmarks, signs, and orientation cues first',
  ),
  reading('Reading', 'Visible text, labels, signs, and screens first');

  const PromptProfile(this.label, this.description);
  final String label;
  final String description;

  String get instruction {
    switch (this) {
      case PromptProfile.balanced:
        return 'Balance safety, directly-ahead details, visible text, and orientation landmarks.';
      case PromptProfile.safety:
        return 'Prioritize hazards first: obstacles, steps, vehicles, people moving nearby, crossings, drop-offs, and anything within arm\'s reach. Keep non-safety details brief.';
      case PromptProfile.navigation:
        return 'Prioritize navigation cues: paths, doors, exits, signs, landmarks, clear walking space, and left/right/ahead orientation.';
      case PromptProfile.reading:
        return 'Prioritize visible text. Read signs, labels, screens, buttons, and documents verbatim before describing the rest of the scene.';
    }
  }
}

class SettingsProvider extends ChangeNotifier {
  final TtsSettingsController ttsService;

  SettingsProvider({required this.ttsService}) {
    _load();
  }

  // ── Audio ──
  double get speechRate => ttsService.rate;
  int get wordsPerMinute => _rateToWpm(ttsService.rate);
  double get volume => _volume;
  VoiceType get voiceType => _voiceType;

  double _volume = 1.0;
  VoiceType _voiceType = VoiceType.neutral;

  void setSpeechRate(double rate) {
    ttsService.setRate(rate);
    _save('speech_rate', rate);
    notifyListeners();
  }

  void setVolume(double vol) {
    _volume = vol.clamp(0.0, 1.0);
    ttsService.setVolume(_volume);
    _save('volume', _volume);
    notifyListeners();
  }

  void setVoiceType(VoiceType type) {
    _voiceType = type;
    _save('voice_type', type.index);
    notifyListeners();
  }

  // ── Descriptions ──
  DetailLevel _detailLevel = DetailLevel.detailed;
  HazardSensitivity _hazardSensitivity = HazardSensitivity.medium;
  PromptProfile _promptProfile = PromptProfile.balanced;

  DetailLevel get detailLevel => _detailLevel;
  HazardSensitivity get hazardSensitivity => _hazardSensitivity;
  PromptProfile get promptProfile => _promptProfile;

  void setDetailLevel(DetailLevel level) {
    _detailLevel = level;
    _save('detail_level', level.index);
    notifyListeners();
  }

  void setHazardSensitivity(HazardSensitivity sensitivity) {
    _hazardSensitivity = sensitivity;
    _save('hazard_sensitivity', sensitivity.index);
    notifyListeners();
  }

  void setPromptProfile(PromptProfile profile) {
    _promptProfile = profile;
    _save('prompt_profile', profile.index);
    notifyListeners();
  }

  // ── Live Detection ──
  LiveDetectionVerbosity _liveDetectionVerbosity =
      LiveDetectionVerbosity.positional;

  LiveDetectionVerbosity get liveDetectionVerbosity => _liveDetectionVerbosity;

  void setLiveDetectionVerbosity(LiveDetectionVerbosity v) {
    _liveDetectionVerbosity = v;
    _save('live_detection_verbosity', v.index);
    notifyListeners();
  }

  // ── Accessibility ──
  FontScale _fontScale = FontScale.normal;
  bool _highContrast = true;
  bool _reduceMotion = false;

  FontScale get fontScale => _fontScale;
  bool get highContrast => _highContrast;
  bool get reduceMotion => _reduceMotion;

  void setFontScale(FontScale scale) {
    _fontScale = scale;
    _save('font_scale', scale.index);
    notifyListeners();
  }

  void setHighContrast(bool value) {
    _highContrast = value;
    _save('high_contrast', value);
    notifyListeners();
  }

  void setReduceMotion(bool value) {
    _reduceMotion = value;
    _save('reduce_motion', value);
    notifyListeners();
  }

  // ── Persistence ──
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final rate = prefs.getDouble('speech_rate');
      if (rate != null) ttsService.setRate(rate);

      _volume = prefs.getDouble('volume') ?? 1.0;
      ttsService.setVolume(_volume);

      final voiceIdx = prefs.getInt('voice_type');
      if (voiceIdx != null && voiceIdx < VoiceType.values.length) {
        _voiceType = VoiceType.values[voiceIdx];
      }

      final detailIdx = prefs.getInt('detail_level');
      if (detailIdx != null && detailIdx < DetailLevel.values.length) {
        _detailLevel = DetailLevel.values[detailIdx];
      }

      final hazardIdx = prefs.getInt('hazard_sensitivity');
      if (hazardIdx != null && hazardIdx < HazardSensitivity.values.length) {
        _hazardSensitivity = HazardSensitivity.values[hazardIdx];
      }

      final promptIdx = prefs.getInt('prompt_profile');
      if (promptIdx != null && promptIdx < PromptProfile.values.length) {
        _promptProfile = PromptProfile.values[promptIdx];
      }

      final verbIdx = prefs.getInt('live_detection_verbosity');
      if (verbIdx != null && verbIdx < LiveDetectionVerbosity.values.length) {
        _liveDetectionVerbosity = LiveDetectionVerbosity.values[verbIdx];
      }

      final fontIdx = prefs.getInt('font_scale');
      if (fontIdx != null && fontIdx < FontScale.values.length) {
        _fontScale = FontScale.values[fontIdx];
      }

      _highContrast = prefs.getBool('high_contrast') ?? true;
      _reduceMotion = prefs.getBool('reduce_motion') ?? false;

      notifyListeners();
    } catch (e) {
      debugPrint('[Settings] Failed to load: $e');
    }
  }

  Future<void> _save(String key, dynamic value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      }
    } catch (e) {
      debugPrint('[Settings] Failed to save $key: $e');
    }
  }

  static int _rateToWpm(double rate) => (100 + (rate * 200)).round();
  static double wpmToRate(int wpm) => ((wpm - 100) / 200).clamp(0.0, 1.0);
}
