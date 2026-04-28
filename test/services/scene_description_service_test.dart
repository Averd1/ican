import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ican/services/connectivity_service.dart';
import 'package:ican/services/on_device_vision_service.dart';
import 'package:ican/services/scene_description_service.dart';
import 'package:ican/services/vertex_ai_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SceneDescriptionService offline backend selection', () {
    late _FakeOnDeviceVisionService onDevice;
    late SceneDescriptionService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      onDevice = _FakeOnDeviceVisionService();
      service = SceneDescriptionService(
        cloudService: _FakeVertexAiService(),
        onDeviceService: onDevice,
      );
    });

    test(
      'falls back to vision-only when local AI artifacts are unavailable',
      () async {
        await service.setMode(VisionMode.offlineOnly);

        final chunks = await service
            .describeScene(_jpegBytes, systemPrompt: 'Describe safely.')
            .toList();

        expect(service.lastBackend, VisionBackend.visionOnly);
        expect(chunks.join(), contains('hallway setting'));
        expect(onDevice.loadVlmCalls, 0);
      },
    );

    test(
      'uses Foundation Models when the device reports availability',
      () async {
        onDevice.foundationModelsAvailable = true;
        await service.setMode(VisionMode.offlineOnly);

        final chunks = await service
            .describeScene(_jpegBytes, systemPrompt: 'Describe safely.')
            .toList();

        expect(service.lastBackend, VisionBackend.foundationModels);
        expect(chunks, ['Foundation model description.']);
        expect(onDevice.loadVlmCalls, 0);
      },
    );

    test(
      'uses SmolVLM only when ready model files load successfully',
      () async {
        onDevice.modelStatus = ModelStatus.ready;
        onDevice.loadVlmResult = true;
        await service.setMode(VisionMode.offlineOnly);

        final chunks = await service
            .describeScene(_jpegBytes, systemPrompt: 'Describe safely.')
            .toList();

        expect(service.lastBackend, VisionBackend.vlm);
        expect(chunks, ['SmolVLM description.']);
        expect(onDevice.loadVlmCalls, 1);
      },
    );

    test(
      'does not select SmolVLM when loading the ready model fails',
      () async {
        onDevice.modelStatus = ModelStatus.ready;
        onDevice.loadVlmResult = false;
        await service.setMode(VisionMode.offlineOnly);

        final chunks = await service
            .describeScene(_jpegBytes, systemPrompt: 'Describe safely.')
            .toList();

        expect(service.lastBackend, VisionBackend.visionOnly);
        expect(chunks.join(), contains('hallway setting'));
        expect(onDevice.loadVlmCalls, 1);
      },
    );
  });

  group('SceneDescriptionService cloud fallback', () {
    late _FakeVertexAiService cloud;
    late _FakeOnDeviceVisionService onDevice;
    late _FakeConnectivityService connectivity;
    late SceneDescriptionService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      cloud = _FakeVertexAiService();
      onDevice = _FakeOnDeviceVisionService();
      connectivity = _FakeConnectivityService(online: true);
      service = SceneDescriptionService(
        cloudService: cloud,
        onDeviceService: onDevice,
        connectivityService: connectivity,
      );
    });

    test('Auto mode falls back to local vision after cloud failure', () async {
      cloud.error = CloudVisionException.httpStatus(403);

      final chunks = await service
          .describeScene(_jpegBytes, systemPrompt: 'Describe safely.')
          .toList();

      expect(cloud.streamCalls, 1);
      expect(service.lastCloudFailure, isA<CloudVisionException>());
      expect(service.lastBackend, VisionBackend.visionOnly);
      expect(chunks.join(), contains('hallway setting'));
      expect(onDevice.analyzeSceneCalls, 1);
    });

    test('Cloud-only mode reports cloud failure without fallback', () async {
      cloud.error = CloudVisionException.httpStatus(429);
      await service.setMode(VisionMode.cloudOnly);

      await expectLater(
        service
            .describeScene(_jpegBytes, systemPrompt: 'Describe safely.')
            .toList(),
        throwsA(
          isA<CloudVisionException>()
              .having((e) => e.kind, 'kind', CloudVisionFailureKind.httpStatus)
              .having((e) => e.statusCode, 'statusCode', 429),
        ),
      );

      expect(cloud.streamCalls, 1);
      expect(service.lastBackend, VisionBackend.cloud);
      expect(onDevice.analyzeSceneCalls, 0);
    });
  });
}

final _jpegBytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);

class _FakeOnDeviceVisionService extends OnDeviceVisionService {
  bool foundationModelsAvailable = false;
  ModelStatus modelStatus = ModelStatus.notDownloaded;
  bool loadVlmResult = false;
  int loadVlmCalls = 0;
  int analyzeSceneCalls = 0;

  @override
  Future<bool> isFoundationModelsAvailable() async => foundationModelsAvailable;

  @override
  Future<ModelStatus> getModelStatus() async => modelStatus;

  @override
  Future<bool> loadVlmModel() async {
    loadVlmCalls++;
    return loadVlmResult;
  }

  @override
  Future<ScenePerceptionResult> analyzeScene(Uint8List jpegBytes) async {
    analyzeSceneCalls++;
    return const ScenePerceptionResult(
      ocrTexts: ['EXIT'],
      sceneClassification: 'hallway',
      sceneConfidence: 0.91,
      personCount: 1,
      personRects: [],
      detectedObjects: [
        SpatialObjectData(
          label: 'chair',
          confidence: 0.82,
          clockPosition: 12,
          relativeDepth: 0.24,
          centerX: 0.5,
          centerY: 0.5,
        ),
      ],
      hasDepthMap: true,
    );
  }

  @override
  Stream<String> synthesizeWithFoundationModels(
    String context, {
    required String systemPrompt,
  }) async* {
    yield 'Foundation model description.';
  }

  @override
  Stream<String> describeWithVlm(
    Uint8List jpegBytes, {
    required String systemPrompt,
    String? visionContext,
  }) async* {
    yield 'SmolVLM description.';
  }
}

class _FakeVertexAiService extends VertexAiService {
  Object? error;
  int streamCalls = 0;

  @override
  Stream<String> streamContentFromImage(
    Uint8List imageBytes, {
    required String systemPrompt,
    String userPrompt = 'Describe what you see.',
  }) async* {
    streamCalls++;
    final failure = error;
    if (failure != null) throw failure;
    yield 'Cloud description.';
  }
}

class _FakeConnectivityService extends ConnectivityService {
  _FakeConnectivityService({required this.online});

  final bool online;

  @override
  Future<bool> hasInternet() async => online;
}
