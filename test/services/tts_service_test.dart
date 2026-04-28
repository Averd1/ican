import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ican/services/audio_playback_service.dart';
import 'package:ican/services/eleven_labs_tts_client.dart';
import 'package:ican/services/tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const flutterTtsChannel = MethodChannel('flutter_tts');

  late List<MethodCall> nativeCalls;

  setUp(() {
    nativeCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(flutterTtsChannel, (call) async {
          nativeCalls.add(call);
          return 1;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(flutterTtsChannel, null);
  });

  test('ElevenLabs success plays MP3 and does not call native speak', () async {
    final player = _FakeMp3AudioPlayer();
    final service = TtsService.testing(
      audioPlayer: player,
      elevenLabsClient: ElevenLabsTtsClient(
        endpoint: 'https://worker.example.com/tts',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['format'], 'mp3');
          return http.Response.bytes(
            [7, 8, 9],
            200,
            headers: {'content-type': 'audio/mpeg'},
          );
        }),
      ),
    )..setSpeechEngine(SpeechEngine.elevenLabs);

    await service.speak(
      'A full scene description that should use the cloud voice.',
    );

    expect(player.played.single, [7, 8, 9]);
    expect(nativeCalls.where((call) => call.method == 'speak'), isEmpty);
    expect(player.stopCount, 1);
  });

  test('ElevenLabs failure falls back to native speech', () async {
    final player = _FakeMp3AudioPlayer();
    final service = TtsService.testing(
      audioPlayer: player,
      elevenLabsClient: ElevenLabsTtsClient(
        endpoint: 'https://worker.example.com/tts',
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'code': 'upstream',
              'message': 'failed',
              'retryable': true,
            }),
            503,
          );
        }),
      ),
    )..setSpeechEngine(SpeechEngine.elevenLabs);

    await service.speak('A full scene description that should fall back.');

    expect(player.played, isEmpty);
    expect(nativeCalls.any((call) => call.method == 'speak'), isTrue);
  });

  test('stop cancels native and cloud playback', () async {
    final player = _FakeMp3AudioPlayer();
    final service = TtsService.testing(audioPlayer: player);

    await service.stop();

    expect(player.stopCount, 1);
    expect(nativeCalls.any((call) => call.method == 'stop'), isTrue);
  });

  test('init stays available when native setup call fails', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(flutterTtsChannel, (call) async {
          nativeCalls.add(call);
          if (call.method == 'setSpeechRate') {
            throw PlatformException(
              code: 'tts_setup_failed',
              message: 'simulated setup failure',
            );
          }
          return call.method == 'getVoices' ? <Object?>[] : 1;
        });

    final service = TtsService.testing();

    await service.init();

    expect(service.initialized, isTrue);
    expect(
      nativeCalls.map((call) => call.method),
      containsAll(<String>['setLanguage', 'setSpeechRate', 'setPitch']),
    );
  });
}

class _FakeMp3AudioPlayer implements Mp3AudioPlayer {
  final played = <Uint8List>[];
  var stopCount = 0;

  @override
  Future<void> playMp3(Uint8List bytes) async {
    played.add(bytes);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}
