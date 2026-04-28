import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

/// Results from Apple Vision framework analysis (legacy — still used by VLM path).
class VisionAnalysis {
  final List<String> ocrTexts;
  final String sceneClassification;
  final double sceneConfidence;
  final int personCount;
  final List<Map<String, double>> personRects;

  const VisionAnalysis({
    required this.ocrTexts,
    required this.sceneClassification,
    required this.sceneConfidence,
    required this.personCount,
    required this.personRects,
  });

  factory VisionAnalysis.fromMap(Map<dynamic, dynamic> map) {
    return VisionAnalysis(
      ocrTexts:
          (map['ocr_texts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      sceneClassification:
          (map['scene_classification'] as String?) ?? 'unknown',
      sceneConfidence: (map['scene_confidence'] as num?)?.toDouble() ?? 0.0,
      personCount: (map['person_count'] as int?) ?? 0,
      personRects:
          (map['person_rects'] as List<dynamic>?)
              ?.map(
                (r) => (r as Map<dynamic, dynamic>).map(
                  (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
                ),
              )
              .toList() ??
          [],
    );
  }

  /// Build a human-readable context string for injecting into the VLM prompt.
  String toPromptContext() {
    final parts = <String>[];

    if (sceneClassification != 'unknown' && sceneConfidence > 0.15) {
      final label = sceneClassification.replaceAll('_', ' ');
      final pct = (sceneConfidence * 100).round();
      parts.add('- Scene type: $label ($pct% confidence)');
    }

    if (personCount > 0) {
      parts.add('- People detected: $personCount');
    }

    if (ocrTexts.isNotEmpty) {
      final quoted = ocrTexts.map((t) => '"$t"').join(', ');
      parts.add('- Text visible: $quoted');
    }

    if (parts.isEmpty) return '';
    return 'Context from device sensors:\n${parts.join('\n')}';
  }
}

/// A spatially-located object from Layer 1 (YOLOv3 + Depth Anything V2 fusion).
class SpatialObjectData {
  final String label;
  final double confidence;
  final int clockPosition; // 9=left, 12=center, 3=right
  final double?
  relativeDepth; // 0.0=closest, 1.0=farthest; null if depth unavailable
  final double centerX;
  final double centerY;
  final double?
  bboxX; // image-space bounding box (top-left origin, normalised 0–1)
  final double? bboxY;
  final double? bboxW;
  final double? bboxH;

  const SpatialObjectData({
    required this.label,
    required this.confidence,
    required this.clockPosition,
    this.relativeDepth,
    required this.centerX,
    required this.centerY,
    this.bboxX,
    this.bboxY,
    this.bboxW,
    this.bboxH,
  });

  factory SpatialObjectData.fromMap(Map<dynamic, dynamic> map) {
    return SpatialObjectData(
      label: (map['label'] as String?) ?? 'object',
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
      clockPosition: (map['clock_position'] as int?) ?? 12,
      relativeDepth: (map['relative_depth'] as num?)?.toDouble(),
      centerX: (map['center_x'] as num?)?.toDouble() ?? 0.5,
      centerY: (map['center_y'] as num?)?.toDouble() ?? 0.5,
      bboxX: (map['bbox_x'] as num?)?.toDouble(),
      bboxY: (map['bbox_y'] as num?)?.toDouble(),
      bboxW: (map['bbox_w'] as num?)?.toDouble(),
      bboxH: (map['bbox_h'] as num?)?.toDouble(),
    );
  }

  String? get distanceTier {
    final d = relativeDepth;
    if (d == null) return null;
    if (d < 0.30) return 'very close';
    if (d < 0.50) return 'close';
    if (d < 0.70) return 'ahead';
    return 'far';
  }

  String get spatialLabel {
    final tier = distanceTier;
    return tier != null
        ? '$label at $clockPosition o\'clock, $tier'
        : '$label at $clockPosition o\'clock';
  }
}

/// Full output from Layer 1 — Vision + Depth Anything V2 + YOLOv3 fused.
class ScenePerceptionResult extends VisionAnalysis {
  final List<SpatialObjectData> detectedObjects;
  final bool hasDepthMap;

  const ScenePerceptionResult({
    required super.ocrTexts,
    required super.sceneClassification,
    required super.sceneConfidence,
    required super.personCount,
    required super.personRects,
    required this.detectedObjects,
    required this.hasDepthMap,
  });

  factory ScenePerceptionResult.fromMap(Map<dynamic, dynamic> map) {
    return ScenePerceptionResult(
      ocrTexts:
          (map['ocr_texts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      sceneClassification:
          (map['scene_classification'] as String?) ?? 'unknown',
      sceneConfidence: (map['scene_confidence'] as num?)?.toDouble() ?? 0.0,
      personCount: (map['person_count'] as int?) ?? 0,
      personRects:
          (map['person_rects'] as List<dynamic>?)
              ?.map(
                (r) => (r as Map<dynamic, dynamic>).map(
                  (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
                ),
              )
              .toList() ??
          [],
      detectedObjects:
          (map['detected_objects'] as List<dynamic>?)
              ?.map(
                (o) => SpatialObjectData.fromMap(o as Map<dynamic, dynamic>),
              )
              .toList() ??
          [],
      hasDepthMap: (map['has_depth_map'] as bool?) ?? false,
    );
  }

  /// Rich context string — includes spatial objects and depth tiers.
  @override
  String toPromptContext() {
    final lines = <String>[];

    if (sceneClassification != 'unknown' && sceneConfidence > 0.15) {
      final label = sceneClassification.replaceAll('_', ' ');
      lines.add(
        '- Scene type: $label (${(sceneConfidence * 100).round()}% confidence)',
      );
    }

    if (personCount > 0) {
      lines.add('- People detected: $personCount');
    }

    final close = detectedObjects
        .where((o) => (o.relativeDepth ?? 1.0) < 0.50)
        .toList();
    if (close.isNotEmpty) {
      lines.add(
        '- Close obstacles: ${close.map((o) => o.spatialLabel).join('; ')}',
      );
    }

    final others = detectedObjects
        .where((o) => (o.relativeDepth ?? 0.0) >= 0.50)
        .take(6);
    if (others.isNotEmpty) {
      lines.add(
        '- Nearby objects: ${others.map((o) => o.spatialLabel).join('; ')}',
      );
    }

    if (ocrTexts.isNotEmpty) {
      final quoted = ocrTexts.take(4).map((t) => '"$t"').join(', ');
      lines.add('- Text visible: $quoted');
    }

    if (lines.isEmpty) return '';
    return 'Context from on-device sensors:\n${lines.join('\n')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Model status
// ─────────────────────────────────────────────────────────────────────────────

/// Status of the on-device VLM (SmolVLM) model.
enum ModelStatus {
  notAvailable,
  notDownloaded,
  downloading,
  ready, // downloaded but not loaded into memory
  loaded, // in memory, ready for inference
}

ModelStatus _parseModelStatus(String raw) {
  switch (raw) {
    case 'not_available':
      return ModelStatus.notAvailable;
    case 'loaded':
      return ModelStatus.loaded;
    case 'ready':
      return ModelStatus.ready;
    case 'downloading':
      return ModelStatus.downloading;
    default:
      return ModelStatus.notDownloaded;
  }
}

class OfflineVisionStatus {
  final bool foundationModelsAvailable;
  final ModelStatus modelStatus;
  final bool objectDetectionAvailable;
  final bool depthEstimationAvailable;

  const OfflineVisionStatus({
    required this.foundationModelsAvailable,
    required this.modelStatus,
    required this.objectDetectionAvailable,
    required this.depthEstimationAvailable,
  });

  bool get smolVlmAvailable =>
      modelStatus == ModelStatus.loaded || modelStatus == ModelStatus.ready;

  bool get hasSpatialPerception =>
      objectDetectionAvailable && depthEstimationAvailable;

  String get bestLocalBackendLabel {
    if (foundationModelsAvailable) return 'Foundation Models';
    if (modelStatus == ModelStatus.loaded) return 'SmolVLM';
    if (hasSpatialPerception) return 'Core ML spatial perception';
    return 'Vision only';
  }

  List<String> get missingRequirements {
    final missing = <String>[];
    if (!foundationModelsAvailable) {
      missing.add('Foundation Models unavailable');
    }
    switch (modelStatus) {
      case ModelStatus.notAvailable:
        missing.add('SmolVLM unavailable');
      case ModelStatus.notDownloaded:
        missing.add('SmolVLM model not downloaded');
      case ModelStatus.downloading:
        missing.add('SmolVLM model still downloading');
      case ModelStatus.ready:
      case ModelStatus.loaded:
        break;
    }
    if (!objectDetectionAvailable) {
      missing.add('YOLOv3Tiny model missing');
    }
    if (!depthEstimationAvailable) {
      missing.add('Depth Anything model missing');
    }
    return missing;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

/// Dart-side client for the native on-device vision MethodChannel.
/// Handles all three pipeline layers exposed by OnDeviceVisionChannel.swift.
class OnDeviceVisionService {
  static const _method = MethodChannel('com.ican/on_device_vision');
  static const _vlmStream = EventChannel('com.ican/vlm_stream');
  static const _fmStream = EventChannel('com.ican/fm_stream');
  static const _downloadStream = EventChannel(
    'com.ican/model_download_progress',
  );

  // ── Layer 1 (legacy) ────────────────────────────────────────────────────

  /// Run Apple Vision framework only (OCR + scene + people).
  /// Kept for backward-compat; prefer [analyzeScene] for new code.
  Future<VisionAnalysis> analyzeWithVision(Uint8List jpegBytes) async {
    try {
      final result = await _method.invokeMethod<Map<dynamic, dynamic>>(
        'analyzeWithVision',
        {'imageBytes': jpegBytes},
      );
      if (result == null || result.containsKey('error')) {
        debugPrint(
          '[OnDeviceVision] analyzeWithVision error: ${result?['error']}',
        );
        return _emptyVisionAnalysis();
      }
      return VisionAnalysis.fromMap(result);
    } on PlatformException catch (e) {
      debugPrint('[OnDeviceVision] Platform error: ${e.message}');
      return _emptyVisionAnalysis();
    }
  }

  // ── Layer 1 (full) ───────────────────────────────────────────────────────

  /// Run the full Layer 1 pipeline: Apple Vision + Depth Anything V2 + YOLOv3.
  /// Returns a [ScenePerceptionResult] with spatial objects and depth tiers.
  Future<ScenePerceptionResult> analyzeScene(Uint8List jpegBytes) async {
    try {
      final result = await _method.invokeMethod<Map<dynamic, dynamic>>(
        'analyzeScene',
        {'imageBytes': jpegBytes},
      );
      if (result == null || result.containsKey('error')) {
        debugPrint('[OnDeviceVision] analyzeScene error: ${result?['error']}');
        return _emptySceneResult();
      }
      return ScenePerceptionResult.fromMap(result);
    } on PlatformException catch (e) {
      debugPrint('[OnDeviceVision] Platform error: ${e.message}');
      return _emptySceneResult();
    }
  }

  // ── Object detection availability ─────────────────────────────────────────

  Future<bool> isObjectDetectionAvailable() async {
    try {
      final result = await _method.invokeMethod<bool>(
        'isObjectDetectionAvailable',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isDepthEstimationAvailable() async {
    try {
      final result = await _method.invokeMethod<bool>(
        'isDepthEstimationAvailable',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<OfflineVisionStatus> getOfflineVisionStatus() async {
    final results = await Future.wait<Object>([
      isFoundationModelsAvailable(),
      getModelStatus(),
      isObjectDetectionAvailable(),
      isDepthEstimationAvailable(),
    ]);

    return OfflineVisionStatus(
      foundationModelsAvailable: results[0] as bool,
      modelStatus: results[1] as ModelStatus,
      objectDetectionAvailable: results[2] as bool,
      depthEstimationAvailable: results[3] as bool,
    );
  }

  // ── Layer 3: Foundation Models ───────────────────────────────────────────

  /// Returns true if Apple Foundation Models is available on this device (iOS 26+).
  Future<bool> isFoundationModelsAvailable() async {
    try {
      final result = await _method.invokeMethod<bool>(
        'isFoundationModelsAvailable',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Synthesize a scene description using Apple Foundation Models.
  /// Streams text chunks (sentences) via EventChannel.
  Stream<String> synthesizeWithFoundationModels(
    String context, {
    required String systemPrompt,
  }) async* {
    try {
      await _method.invokeMethod<bool>('synthesizeDescription', {
        'context': context,
        'systemPrompt': systemPrompt,
      });

      await for (final event in _fmStream.receiveBroadcastStream()) {
        if (event is String) yield event;
      }
    } on PlatformException catch (e) {
      debugPrint('[OnDeviceVision] Foundation Models error: ${e.message}');
    }
  }

  // ── Layer 2: SmolVLM ────────────────────────────────────────────────────

  Future<ModelStatus> getModelStatus() async {
    try {
      final raw = await _method.invokeMethod<String>('getModelStatus');
      return _parseModelStatus(raw ?? 'not_downloaded');
    } catch (_) {
      return ModelStatus.notDownloaded;
    }
  }

  Future<bool> loadVlmModel() async {
    try {
      final result = await _method.invokeMethod<bool>('loadModel');
      return result ?? false;
    } catch (e) {
      debugPrint('[OnDeviceVision] Failed to load VLM: $e');
      return false;
    }
  }

  Future<void> unloadVlmModel() async {
    try {
      await _method.invokeMethod<bool>('unloadModel');
    } catch (e) {
      debugPrint('[OnDeviceVision] Failed to unload VLM: $e');
    }
  }

  /// Run VLM inference and stream tokens back.
  Stream<String> describeWithVlm(
    Uint8List jpegBytes, {
    required String systemPrompt,
    String? visionContext,
  }) async* {
    try {
      await _method.invokeMethod<bool>('describeImage', {
        'imageBytes': jpegBytes,
        'systemPrompt': systemPrompt,
        'visionContext': visionContext,
      });

      await for (final event in _vlmStream.receiveBroadcastStream()) {
        if (event is String) yield event;
      }
    } on PlatformException catch (e) {
      debugPrint('[OnDeviceVision] VLM inference error: ${e.message}');
    }
  }

  // ── Download management ──────────────────────────────────────────────────

  Stream<dynamic> startModelDownload() async* {
    try {
      await _method.invokeMethod<bool>('downloadModel');
      await for (final event in _downloadStream.receiveBroadcastStream()) {
        yield event;
      }
    } on PlatformException catch (e) {
      debugPrint('[OnDeviceVision] Download error: ${e.message}');
    }
  }

  Future<void> cancelModelDownload() async {
    try {
      await _method.invokeMethod<bool>('cancelDownload');
    } catch (_) {}
  }

  Future<bool> deleteModel() async {
    try {
      final result = await _method.invokeMethod<bool>('deleteModel');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getModelInfo() async {
    try {
      final result = await _method.invokeMethod<Map<dynamic, dynamic>>(
        'getModelInfo',
      );
      return result?.map((k, v) => MapEntry(k.toString(), v)) ?? {};
    } catch (_) {
      return {};
    }
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  VisionAnalysis _emptyVisionAnalysis() => const VisionAnalysis(
    ocrTexts: [],
    sceneClassification: 'unknown',
    sceneConfidence: 0,
    personCount: 0,
    personRects: [],
  );

  ScenePerceptionResult _emptySceneResult() => const ScenePerceptionResult(
    ocrTexts: [],
    sceneClassification: 'unknown',
    sceneConfidence: 0,
    personCount: 0,
    personRects: [],
    detectedObjects: [],
    hasDepthMap: false,
  );
}
