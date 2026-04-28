import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ican/services/on_device_vision_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.ican/on_device_vision');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'reports vision-only when all advanced offline artifacts are missing',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return switch (call.method) {
              'isFoundationModelsAvailable' => false,
              'getModelStatus' => 'not_available',
              'isObjectDetectionAvailable' => false,
              'isDepthEstimationAvailable' => false,
              _ => throw PlatformException(code: 'unexpected'),
            };
          });

      final status = await OnDeviceVisionService().getOfflineVisionStatus();

      expect(status.foundationModelsAvailable, isFalse);
      expect(status.modelStatus, ModelStatus.notAvailable);
      expect(status.objectDetectionAvailable, isFalse);
      expect(status.depthEstimationAvailable, isFalse);
      expect(status.bestLocalBackendLabel, 'Vision only');
      expect(
        status.missingRequirements,
        containsAll([
          'Foundation Models unavailable',
          'SmolVLM unavailable',
          'YOLOv3Tiny model missing',
          'Depth Anything model missing',
        ]),
      );
    },
  );

  test(
    'reports spatial perception when object and depth models are present',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return switch (call.method) {
              'isFoundationModelsAvailable' => false,
              'getModelStatus' => 'not_downloaded',
              'isObjectDetectionAvailable' => true,
              'isDepthEstimationAvailable' => true,
              _ => throw PlatformException(code: 'unexpected'),
            };
          });

      final status = await OnDeviceVisionService().getOfflineVisionStatus();

      expect(status.bestLocalBackendLabel, 'Core ML spatial perception');
      expect(status.hasSpatialPerception, isTrue);
      expect(
        status.missingRequirements,
        contains('SmolVLM model not downloaded'),
      );
    },
  );

  test(
    'reports Foundation Models as the best local backend when available',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return switch (call.method) {
              'isFoundationModelsAvailable' => true,
              'getModelStatus' => 'loaded',
              'isObjectDetectionAvailable' => true,
              'isDepthEstimationAvailable' => true,
              _ => throw PlatformException(code: 'unexpected'),
            };
          });

      final status = await OnDeviceVisionService().getOfflineVisionStatus();

      expect(status.bestLocalBackendLabel, 'Foundation Models');
      expect(status.modelStatus, ModelStatus.loaded);
      expect(status.missingRequirements, isEmpty);
    },
  );
}
