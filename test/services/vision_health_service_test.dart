import 'package:flutter_test/flutter_test.dart';
import 'package:ican/services/connectivity_service.dart';
import 'package:ican/services/on_device_vision_service.dart';
import 'package:ican/services/vertex_ai_service.dart';
import 'package:ican/services/vision_health_service.dart';

void main() {
  group('VisionHealthService', () {
    test('reports missing native channel as the blocking reason', () async {
      final status = await VisionHealthService(
        onDeviceService: _FakeOnDeviceVisionService(nativeReady: false),
        cloudService: VertexAiService(apiKey: 'test-key'),
        connectivityService: _FakeConnectivityService(online: true),
      ).check(eyeConnected: true);

      expect(status.nativeChannel.isAvailable, isFalse);
      expect(status.appleVision.isAvailable, isFalse);
      expect(status.blockingReason, 'Native vision channel is not registered.');
    });

    test(
      'reports basic live mode when YOLO is missing but Vision works',
      () async {
        final status = await VisionHealthService(
          onDeviceService: _FakeOnDeviceVisionService(
            nativeReady: true,
            appleVisionReady: true,
            objectReady: false,
            depthReady: false,
            modelStatus: ModelStatus.notDownloaded,
          ),
          cloudService: VertexAiService(apiKey: 'test-key'),
          connectivityService: _FakeConnectivityService(online: true),
        ).check(eyeConnected: true);

        expect(status.basicLiveModeReady, isTrue);
        expect(status.fullLiveDetectionReady, isFalse);
        expect(status.objectDetector.message, contains('not found'));
        expect(status.cloudDescribeReady, isTrue);
      },
    );
  });
}

class _FakeOnDeviceVisionService extends OnDeviceVisionService {
  _FakeOnDeviceVisionService({
    required this.nativeReady,
    this.appleVisionReady = false,
    this.objectReady = false,
    this.depthReady = false,
    this.modelStatus = ModelStatus.notDownloaded,
  });

  final bool nativeReady;
  final bool appleVisionReady;
  final bool objectReady;
  final bool depthReady;
  final ModelStatus modelStatus;

  @override
  Future<bool> pingNativeChannel() async => nativeReady;

  @override
  Future<bool> isAppleVisionAvailable() async => appleVisionReady;

  @override
  Future<bool> isFoundationModelsAvailable() async => false;

  @override
  Future<ModelStatus> getModelStatus() async => modelStatus;

  @override
  Future<bool> isObjectDetectionAvailable() async => objectReady;

  @override
  Future<bool> isDepthEstimationAvailable() async => depthReady;

  @override
  Future<OfflineVisionDiagnostics> getOfflineVisionDiagnostics() async {
    return OfflineVisionDiagnostics(
      objectDetector: NativeModelDiagnostic(
        name: 'YOLOv3Tiny',
        bundleFound: objectReady,
        compiledModelFound: objectReady,
        loaded: objectReady,
        message: objectReady
            ? 'YOLOv3Tiny loaded.'
            : 'YOLOv3Tiny was not found in the app bundle.',
      ),
      depthEstimator: NativeModelDiagnostic(
        name: 'DepthAnythingV2SmallF16P6',
        bundleFound: depthReady,
        compiledModelFound: depthReady,
        loaded: depthReady,
        message: depthReady
            ? 'Depth model loaded.'
            : 'Depth Anything model was not found in the app bundle.',
      ),
    );
  }
}

class _FakeConnectivityService extends ConnectivityService {
  _FakeConnectivityService({required this.online});

  final bool online;

  @override
  Future<bool> hasInternet() async => online;
}
