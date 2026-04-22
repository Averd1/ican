import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'connectivity_service.dart';
import 'on_device_vision_service.dart';
import 'vertex_ai_service.dart';

/// User-selectable vision processing mode.
enum VisionMode {
  auto('Auto', 'Uses cloud when online, offline model when not'),
  offlineOnly('Offline', 'Always uses on-device processing'),
  cloudOnly('Cloud', 'Always uses Gemini cloud API');

  const VisionMode(this.label, this.description);
  final String label;
  final String description;
}

/// Which backend was used for the most recent description.
enum VisionBackend {
  cloud,
  foundationModels, // Apple Foundation Models (iOS 26+) — richest offline path
  moondream,        // Moondream 2B CoreML — pioneer on-device VLM with Pointing skill
  vlm,              // SmolVLM via llama.cpp — fallback
  visionOnly,       // Layer 1 template only
}

/// Unified scene description service.
/// Selects the best available backend and streams text chunks to the caller.
class SceneDescriptionService extends ChangeNotifier {
  final VertexAiService cloudService;
  final OnDeviceVisionService onDeviceService;
  final ConnectivityService _connectivity = ConnectivityService();

  static const String _prefsKey = 'vision_mode';

  VisionMode _mode = VisionMode.auto;
  VisionMode get mode => _mode;

  VisionBackend? _lastBackend;
  VisionBackend? get lastBackend => _lastBackend;

  SceneDescriptionService({
    required this.cloudService,
    required this.onDeviceService,
  });

  /// Load saved mode preference. Call once at app startup.
  Future<void> loadSavedMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        _mode = VisionMode.values.firstWhere(
          (m) => m.name == saved,
          orElse: () => VisionMode.auto,
        );
      }
    } catch (_) {}
  }

  /// Switch vision mode and persist.
  Future<void> setMode(VisionMode newMode) async {
    if (_mode == newMode) return;
    _mode = newMode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, newMode.name);
    } catch (_) {}
    debugPrint('[SceneDescription] Mode changed to: ${newMode.name}');
  }

  // ── Main entry point ────────────────────────────────────────────────────

  /// Describe a scene from a JPEG image.
  /// Yields text chunks for the sentence-splitting TTS loop in AccessibleHomeScreen.
  Stream<String> describeScene(
    Uint8List imageBytes, {
    required String systemPrompt,
    void Function(String status, VisionBackend backend)? onStatusUpdate,
  }) async* {
    final backend = await _selectBackend();
    _lastBackend = backend;
    debugPrint('[SceneDescription] Using backend: ${backend.name}');

    switch (backend) {
      case VisionBackend.cloud:
        onStatusUpdate?.call('Analyzing with ${cloudService.model.label}...', backend);
        yield* _describeWithCloud(imageBytes, systemPrompt: systemPrompt);

      case VisionBackend.foundationModels:
        onStatusUpdate?.call('Analyzing on-device...', backend);
        yield* _describeWithFoundationModels(imageBytes, systemPrompt: systemPrompt);

      case VisionBackend.moondream:
        onStatusUpdate?.call('Analyzing with Moondream...', backend);
        yield* _describeWithMoondream(imageBytes);

      case VisionBackend.vlm:
        onStatusUpdate?.call('Analyzing offline with AI model...', backend);
        yield* _describeWithVlm(imageBytes, systemPrompt: systemPrompt);

      case VisionBackend.visionOnly:
        onStatusUpdate?.call('Reading scene...', backend);
        yield* _describeWithVisionOnly(imageBytes);
    }
  }

  // ── Single-backend entry points (for diagnostics) ──────────────────────

  Stream<String> describeWithGemini(
    Uint8List imageBytes, {
    required String systemPrompt,
  }) {
    return _describeWithCloud(imageBytes, systemPrompt: systemPrompt);
  }

  Stream<String> describeWithFoundationModels(
    Uint8List imageBytes, {
    required String systemPrompt,
  }) {
    return _describeWithFoundationModels(imageBytes, systemPrompt: systemPrompt);
  }

  Stream<String> describeWithMoondream(Uint8List imageBytes) {
    return _describeWithMoondream(imageBytes);
  }

  Stream<String> describeWithSmolVLM(
    Uint8List imageBytes, {
    required String systemPrompt,
  }) {
    return _describeWithVlm(imageBytes, systemPrompt: systemPrompt);
  }

  Stream<String> describeWithVisionTemplate(Uint8List imageBytes) {
    return _describeWithVisionOnly(imageBytes);
  }

  // ── Backend selection ───────────────────────────────────────────────────

  Future<VisionBackend> _selectBackend() async {
    switch (_mode) {
      case VisionMode.cloudOnly:
        return VisionBackend.cloud;

      case VisionMode.offlineOnly:
        return await _bestOfflineBackend();

      case VisionMode.auto:
        final online = await _connectivity.hasInternet();
        if (online) return VisionBackend.cloud;
        return await _bestOfflineBackend();
    }
  }

  /// Pick the best available offline backend.
  ///
  /// Priority: Foundation Models (iOS 26, zero download)
  ///           → Moondream CoreML (bundled, best VLM quality + Pointing)
  ///           → SmolVLM llama.cpp → template.
  Future<VisionBackend> _bestOfflineBackend() async {
    // 1. Foundation Models — zero download, iOS 26+
    final fmAvailable = await onDeviceService.isFoundationModelsAvailable();
    if (fmAvailable) return VisionBackend.foundationModels;

    // 2. Moondream CoreML — bundled, best on-device VLM with Pointing skill
    final mdAvailable = await onDeviceService.isMoondreamAvailable();
    if (mdAvailable) return VisionBackend.moondream;

    // 2. SmolVLM — good quality, ~800 MB download
    final status = await onDeviceService.getModelStatus();
    if (status == ModelStatus.loaded) return VisionBackend.vlm;
    if (status == ModelStatus.ready) {
      final loaded = await onDeviceService.loadVlmModel();
      if (loaded) return VisionBackend.vlm;
    }

    // 3. Layer 1 template — always available
    return VisionBackend.visionOnly;
  }

  // ── Backend implementations ─────────────────────────────────────────────

  /// Cloud path — stream directly from Gemini.
  Stream<String> _describeWithCloud(
    Uint8List imageBytes, {
    required String systemPrompt,
  }) {
    return cloudService.streamContentFromImage(
      imageBytes,
      systemPrompt: systemPrompt,
    );
  }

  /// Foundation Models path — Layer 1 perception → Apple LLM synthesis.
  ///
  /// Uses the full PerceptionLayer output (Vision + Depth + YOLO) as structured
  /// context fed into Apple Foundation Models for natural-language generation.
  Stream<String> _describeWithFoundationModels(
    Uint8List imageBytes, {
    required String systemPrompt,
  }) async* {
    final perception = await onDeviceService.analyzeScene(imageBytes);
    final context    = perception.toPromptContext();

    debugPrint('[SceneDescription] FM context: $context');

    bool gotTokens = false;
    try {
      await for (final token in onDeviceService.synthesizeWithFoundationModels(
        context,
        systemPrompt: systemPrompt,
      )) {
        gotTokens = true;
        yield token;
      }
    } catch (e) {
      debugPrint('[SceneDescription] Foundation Models failed: $e');
    }

    if (!gotTokens) {
      debugPrint('[SceneDescription] FM produced no output — using template');
      yield perception.toTemplateDescription();
    }
  }

  /// Moondream path — encode + prefill + caption via CoreML.
  /// Falls back to Layer 1 template if prefill fails.
  Stream<String> _describeWithMoondream(Uint8List imageBytes) async* {
    // Run Layer 1 in parallel with Moondream encode+prefill
    final perception = await onDeviceService.analyzeScene(imageBytes);
    final prefillOk  = await onDeviceService.moondreamEncodeAndPrefill(imageBytes);

    if (!prefillOk) {
      debugPrint('[SceneDescription] Moondream prefill failed — template fallback');
      yield perception.toTemplateDescription();
      return;
    }

    bool gotTokens = false;
    try {
      await for (final token in onDeviceService.captionWithMoondream()) {
        gotTokens = true;
        yield token;
      }
    } catch (e) {
      debugPrint('[SceneDescription] Moondream caption error: $e');
    }

    if (!gotTokens) {
      yield perception.toTemplateDescription();
    }
  }

  /// VLM path — Layer 1 perception context fed into SmolVLM.
  Stream<String> _describeWithVlm(
    Uint8List imageBytes, {
    required String systemPrompt,
  }) async* {
    // Use the full Layer 1 pipeline for richer context (includes spatial objects + depth)
    final perception = await onDeviceService.analyzeScene(imageBytes);
    final context    = perception.toPromptContext();

    debugPrint('[SceneDescription] VLM context: $context');

    final enhancedPrompt = context.isNotEmpty
        ? '$systemPrompt\n\n$context\n\nDescribe this scene incorporating the context above.'
        : systemPrompt;

    bool gotTokens = false;
    try {
      await for (final token in onDeviceService.describeWithVlm(
        imageBytes,
        systemPrompt: enhancedPrompt,
      )) {
        gotTokens = true;
        yield token;
      }
    } catch (e) {
      debugPrint('[SceneDescription] VLM inference failed: $e');
    }

    if (!gotTokens) {
      debugPrint('[SceneDescription] VLM produced no output — using template');
      yield perception.toTemplateDescription();
    }
  }

  /// Vision-only path — Layer 1 template, no VLM needed.
  Stream<String> _describeWithVisionOnly(Uint8List imageBytes) async* {
    final perception = await onDeviceService.analyzeScene(imageBytes);
    yield perception.toTemplateDescription();
  }
}

// ── Dart-side helper on ScenePerceptionResult ──────────────────────────────

extension ScenePerceptionResultTemplate on ScenePerceptionResult {
  /// Assemble a spoken description from Layer 1 data alone.
  String toTemplateDescription() {
    final sentences = <String>[];

    // WHERE
    if (sceneClassification != 'unknown' && sceneConfidence > 0.15) {
      final label = sceneClassification.replaceAll('_', ' ');
      sentences.add('You appear to be in a $label setting.');
    } else {
      sentences.add('The scene could not be clearly identified.');
    }

    // SAFETY — close objects
    final close = detectedObjects.where((o) => (o.relativeDepth ?? 1.0) < 0.50).toList();
    if (close.isNotEmpty) {
      final descs = close.take(3).map((o) => o.spatialLabel).join(', ');
      sentences.add('Caution: $descs.');
    }

    // PEOPLE
    if (personCount > 0) {
      final noun = personCount == 1 ? '1 person is' : '$personCount people are';
      sentences.add('${noun[0].toUpperCase()}${noun.substring(1)} detected nearby.');
    }

    // TEXT
    if (ocrTexts.isNotEmpty) {
      if (ocrTexts.length == 1) {
        sentences.add('Text reads: ${ocrTexts.first}.');
      } else {
        sentences.add('Visible text includes: ${ocrTexts.take(3).join(', ')}.');
      }
    }

    // OTHER OBJECTS
    final others = detectedObjects.where((o) => (o.relativeDepth ?? 0.0) >= 0.50).take(4);
    if (others.isNotEmpty) {
      sentences.add('Also nearby: ${others.map((o) => o.spatialLabel).join(', ')}.');
    }

    return sentences.join(' ');
  }
}
