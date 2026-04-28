import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ican/core/theme.dart';
import 'package:ican/models/home_view_model.dart';
import 'package:ican/models/settings_provider.dart';
import 'package:ican/protocol/eye_capture_diagnostics.dart';
import 'package:ican/screens/accessible_home_screen.dart';
import 'package:ican/services/on_device_vision_service.dart';
import 'package:ican/services/scene_description_service.dart';
import 'package:ican/services/stt_service.dart';
import 'package:ican/services/tts_service.dart';
import 'package:ican/services/vertex_ai_service.dart';
import 'package:ican/services/voice_command_service.dart';
import 'package:ican/services/voice_control_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const onDeviceVisionChannel = MethodChannel('com.ican/on_device_vision');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(onDeviceVisionChannel, (call) async {
          return switch (call.method) {
            'isFoundationModelsAvailable' => false,
            'getModelStatus' => 'not_available',
            'isObjectDetectionAvailable' => false,
            'isDepthEstimationAvailable' => false,
            'getNativeModelDiagnostics' => {
              'object_detector': {
                'name': 'YOLOv3Tiny',
                'bundle_found': false,
                'compiled_model_found': false,
                'loaded': false,
                'message': 'YOLOv3Tiny was not found in the app bundle.',
              },
              'depth_estimator': {
                'name': 'DepthAnythingV2SmallF16P6',
                'bundle_found': false,
                'compiled_model_found': false,
                'loaded': false,
                'message':
                    'DepthAnythingV2SmallF16P6 was not found in the app bundle.',
              },
            },
            _ => throw PlatformException(code: 'unexpected'),
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(onDeviceVisionChannel, null);
  });

  testWidgets('Home renders voice trigger and command state', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final stt = _FakeStt();
    final processor = _FakeProcessor();
    final voice = VoiceCommandService.custom(
      tts: _FakeTts(),
      stt: stt,
      ble: _FakeBle(),
      processor: processor,
    );
    final settings = SettingsProvider(ttsService: TtsService.instance)
      ..setPromptProfile(PromptProfile.safety)
      ..setDetailLevel(DetailLevel.brief)
      ..setLiveDetectionVerbosity(LiveDetectionVerbosity.minimal);
    final vm = HomeViewModel(
      sceneService: SceneDescriptionService(
        cloudService: VertexAiService(),
        onDeviceService: OnDeviceVisionService(),
      ),
      ttsService: TtsService.instance,
      settingsProvider: settings,
    );

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (context, child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<HomeViewModel>.value(value: vm),
            ChangeNotifierProvider<VoiceCommandService>.value(value: voice),
          ],
          child: MaterialApp(
            theme: ICanTheme.lightTheme,
            home: const AccessibleHomeScreen(),
          ),
        ),
      ),
    );

    expect(find.text('Start Voice Command'), findsOneWidget);
    expect(find.text('Status: Ready'), findsOneWidget);
    expect(find.text('Focus: Safety'), findsOneWidget);
    expect(find.text('Detail: Brief'), findsOneWidget);
    expect(find.text('Live: Minimal'), findsOneWidget);
    expect(find.text('Vision: Auto: cloud reliable'), findsOneWidget);
    await tester.pump();
    expect(find.text('Local: Local basic vision'), findsOneWidget);

    await tester.ensureVisible(find.text('Start Voice Command'));
    await tester.pump();
    await tester.tap(find.text('Start Voice Command'));
    await tester.pump();

    expect(find.text('Listening for Command'), findsOneWidget);
    expect(find.text('Status: Listening'), findsOneWidget);

    stt.emit('repeat last');
    await tester.pump();

    expect(find.text('Processing Voice Command'), findsOneWidget);
    expect(find.text('Status: Processing'), findsOneWidget);
    expect(find.text('Heard: repeat last'), findsOneWidget);

    processor.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('Start Voice Command'), findsOneWidget);
    expect(find.textContaining('Last result: Repeating'), findsOneWidget);

    voice.dispose();
    vm.dispose();
    stt.dispose();
  });

  testWidgets('Home shows the latest vision diagnostic as visible text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    final tts = _FakeTts();
    final stt = _FakeStt();
    final voice = VoiceCommandService.custom(
      tts: tts,
      stt: stt,
      ble: _FakeBle(),
      processor: _FakeProcessor(),
    );
    final settings = SettingsProvider(ttsService: TtsService.instance);
    final vm = HomeViewModel(
      sceneService: SceneDescriptionService(
        cloudService: VertexAiService(),
        onDeviceService: OnDeviceVisionService(),
      ),
      ttsService: tts,
      settingsProvider: settings,
    );

    vm.startCaptureTimeoutForTesting();
    await vm.handleEyeCaptureDiagnosticForTesting(
      const EyeCaptureDiagnostic(
        code: EyeCaptureDiagnosticCode.streamStalled,
        captureStarted: true,
        sizeArrived: true,
        expectedBytes: 1024,
        receivedBytes: 512,
        uniqueChunks: 4,
        duplicateChunks: 1,
        endArrived: false,
        jpegMagicValid: true,
        jpegEndValid: false,
        timeoutStage: EyeTransferTimeoutStage.awaitingEnd,
      ),
    );

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (context, child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<HomeViewModel>.value(value: vm),
            ChangeNotifierProvider<VoiceCommandService>.value(value: voice),
          ],
          child: MaterialApp(
            theme: ICanTheme.lightTheme,
            home: const AccessibleHomeScreen(),
          ),
        ),
      ),
    );

    expect(find.text('Latest Vision Diagnostic'), findsOneWidget);
    expect(find.textContaining('Eye E02'), findsOneWidget);
    expect(find.textContaining('512/1024 bytes'), findsOneWidget);

    voice.dispose();
    vm.dispose();
    stt.dispose();
  });
}

class _FakeTts implements VoiceCommandTts, SpeechOutput {
  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {}
}

class _FakeStt implements VoiceCommandStt {
  final _controller = StreamController<String>.broadcast();
  final _partialController = StreamController<String>.broadcast();
  final _errorController = StreamController<SttRecognitionError>.broadcast();

  @override
  bool get available => true;

  @override
  Stream<String> get resultStream => _controller.stream;

  @override
  Stream<String> get partialResultStream => _partialController.stream;

  @override
  Stream<SttRecognitionError> get errorStream => _errorController.stream;

  @override
  Future<bool> init() async => true;

  @override
  Future<void> startListening({
    Duration listenFor = const Duration(seconds: 8),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {}

  @override
  Future<void> stopListening() async {}

  void emit(String text) {
    _controller.add(text);
  }

  void dispose() {
    _controller.close();
    _partialController.close();
    _errorController.close();
  }
}

class _FakeBle implements VoiceCommandBle {
  @override
  Stream<String> get buttonEventStream => const Stream.empty();
}

class _FakeProcessor implements VoiceCommandProcessor {
  final _completer = Completer<VoiceActionResult>();

  @override
  Future<VoiceActionResult> handleTranscript(String transcript) {
    return _completer.future;
  }

  void complete() {
    _completer.complete(
      const VoiceActionResult(
        success: true,
        spokenConfirmation: 'Repeating the last description.',
      ),
    );
  }
}
