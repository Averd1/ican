import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

enum ElevenLabsVoicePreset {
  defaultVoice('default'),
  calm('calm'),
  fast('fast');

  const ElevenLabsVoicePreset(this.workerValue);

  final String workerValue;
}

class ElevenLabsTtsException implements Exception {
  const ElevenLabsTtsException(
    this.code,
    this.message, {
    this.retryable = true,
  });

  final String code;
  final String message;
  final bool retryable;

  @override
  String toString() => '$code: $message';
}

class ElevenLabsTtsClient {
  ElevenLabsTtsClient({
    http.Client? httpClient,
    String endpoint = const String.fromEnvironment('ELEVENLABS_TTS_WORKER_URL'),
    Duration timeout = const Duration(seconds: 12),
  }) : _client = httpClient ?? http.Client(),
       _endpoint = endpoint,
       _timeout = timeout,
       _ownsClient = httpClient == null;

  final http.Client _client;
  final String _endpoint;
  final Duration _timeout;
  final bool _ownsClient;

  bool get isConfigured => _endpoint.trim().isNotEmpty;

  Future<Uint8List> synthesizeMp3(
    String text, {
    ElevenLabsVoicePreset voice = ElevenLabsVoicePreset.defaultVoice,
  }) async {
    if (!isConfigured) {
      throw const ElevenLabsTtsException(
        'not_configured',
        'ElevenLabs Worker URL is not configured.',
        retryable: false,
      );
    }

    final uri = Uri.parse(_endpoint).replace(path: _ttsPath(_endpoint));
    final response = await _client
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'text': text,
            'voice': voice.workerValue,
            'format': 'mp3',
          }),
        )
        .timeout(_timeout);

    final contentType = response.headers['content-type'] ?? '';
    if (response.statusCode == 200 && contentType.contains('audio/mpeg')) {
      return response.bodyBytes;
    }

    throw _errorFromResponse(response);
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  static String _ttsPath(String endpoint) {
    final parsed = Uri.parse(endpoint);
    if (parsed.path.isNotEmpty && parsed.path != '/') return parsed.path;
    return '/tts';
  }

  static ElevenLabsTtsException _errorFromResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return ElevenLabsTtsException(
          decoded['code']?.toString() ?? 'worker_error',
          decoded['message']?.toString() ?? 'TTS Worker request failed.',
          retryable: decoded['retryable'] as bool? ?? true,
        );
      }
    } catch (_) {}
    return ElevenLabsTtsException(
      'http_${response.statusCode}',
      'TTS Worker returned HTTP ${response.statusCode}.',
    );
  }
}
