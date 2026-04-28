import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ican/services/eleven_labs_tts_client.dart';

void main() {
  group('ElevenLabsTtsClient', () {
    test('posts Worker contract and returns mp3 bytes', () async {
      late Map<String, dynamic> requestBody;
      final client = ElevenLabsTtsClient(
        endpoint: 'https://worker.example.com/tts',
        httpClient: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          expect(request.url.toString(), 'https://worker.example.com/tts');
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'audio/mpeg'},
          );
        }),
      );

      final bytes = await client.synthesizeMp3(
        'A clear path ahead.',
        voice: ElevenLabsVoicePreset.calm,
      );

      expect(bytes, [1, 2, 3]);
      expect(requestBody, {
        'text': 'A clear path ahead.',
        'voice': 'calm',
        'format': 'mp3',
      });
    });

    test('structured Worker errors throw retryable exception', () async {
      final client = ElevenLabsTtsClient(
        endpoint: 'https://worker.example.com',
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'code': 'rate_limited',
              'message': 'Too many requests.',
              'retryable': true,
            }),
            429,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        client.synthesizeMp3('Hello.'),
        throwsA(
          isA<ElevenLabsTtsException>()
              .having((e) => e.code, 'code', 'rate_limited')
              .having((e) => e.retryable, 'retryable', isTrue),
        ),
      );
    });
  });
}
