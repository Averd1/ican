import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Available AI models for image understanding, ordered by speed.
enum AiModel {
  flashLite(
    id: 'gemini-2.5-flash-lite',
    label: 'Flash Lite',
    description: 'Fastest, basic quality',
  ),
  flash(
    id: 'gemini-2.5-flash',
    label: 'Flash',
    description: 'Fast, good quality (recommended)',
  ),
  pro(
    id: 'gemini-2.5-pro',
    label: 'Pro',
    description: 'Best quality, slower (~3s)',
  );

  const AiModel({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;
}

class VertexAiService extends ChangeNotifier {
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  static const String _prefsKey = 'ai_model';

  AiModel _model = AiModel.flash;
  AiModel get model => _model;

  /// Load saved model preference. Call once at app startup.
  Future<void> loadSavedModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        _model = AiModel.values.firstWhere(
          (m) => m.id == saved,
          orElse: () => AiModel.flash,
        );
      }
    } catch (_) {}
  }

  /// Switch the active model and persist the choice.
  Future<void> setModel(AiModel newModel) async {
    if (_model == newModel) return;
    _model = newModel;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, newModel.id);
    } catch (_) {}
    debugPrint('[VisionAI] Model changed to: ${newModel.id}');
  }

  Future<String> generateContent(String prompt) async {
    return _sendRequest([
      {'text': prompt},
    ]);
  }

  Future<String> generateContentFromImage(
    Uint8List imageBytes, {
    required String systemPrompt,
    String userPrompt = 'Describe what you see.',
  }) async {
    final base64Image = base64Encode(imageBytes);

    return _sendRequest([
      {
        'inlineData': {
          'mimeType': 'image/jpeg',
          'data': base64Image,
        }
      },
      {'text': userPrompt},
    ], systemPrompt: systemPrompt);
  }

  Future<String> _sendRequest(
    List<Map<String, dynamic>> parts, {
    String? systemPrompt,
  }) async {
    const apiKey = String.fromEnvironment('API_KEY');

    if (apiKey.isEmpty) {
      throw Exception('API_KEY not set — build with --dart-define=API_KEY=<your_key>');
    }

    final url = Uri.parse('$_baseUrl/${_model.id}:generateContent?key=$apiKey');

    final body = <String, dynamic>{
      'contents': [
        {
          'role': 'user',
          'parts': parts,
        },
      ],
      'generationConfig': {
        'temperature': 0.2,
        'maxOutputTokens': 500,
        'topP': 0.8,
      },
    };

    if (systemPrompt != null) {
      body['system_instruction'] = {
        'parts': [{'text': systemPrompt}],
      };
    }

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    debugPrint('[VisionAI] ${_model.id} response: ${response.statusCode}');

    if (response.statusCode == 200) {
      final Map<String, dynamic> json = jsonDecode(response.body);
      return _extractText(json);
    } else {
      debugPrint('[VisionAI] Error: ${response.body.substring(0, response.body.length > 300 ? 300 : response.body.length)}');
      throw Exception('AI request failed (${response.statusCode})');
    }
  }

  /// Stream content from image using SSE for lower first-token latency.
  /// Yields incremental text chunks as they arrive from the API.
  Stream<String> streamContentFromImage(
    Uint8List imageBytes, {
    required String systemPrompt,
    String userPrompt = 'Describe what you see.',
  }) async* {
    final base64Image = base64Encode(imageBytes);
    const apiKey = String.fromEnvironment('API_KEY');
    if (apiKey.isEmpty) {
      throw Exception('API_KEY not set — build with --dart-define=API_KEY=<your_key>');
    }

    final url = Uri.parse(
      '$_baseUrl/${_model.id}:streamGenerateContent?alt=sse&key=$apiKey',
    );

    final body = <String, dynamic>{
      'system_instruction': {
        'parts': [{'text': systemPrompt}],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'inlineData': {
                'mimeType': 'image/jpeg',
                'data': base64Image,
              }
            },
            {'text': userPrompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.2,
        'maxOutputTokens': 500,
        'topP': 0.8,
      },
    };

    final request = http.Request('POST', url);
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(body);

    final client = http.Client();
    try {
      final streamed = await client.send(request);

      if (streamed.statusCode != 200) {
        final errorBody = await streamed.stream.bytesToString();
        debugPrint('[VisionAI] Stream error: '
            '${errorBody.substring(0, errorBody.length > 300 ? 300 : errorBody.length)}');
        throw Exception('AI stream failed (${streamed.statusCode})');
      }

      debugPrint('[VisionAI] ${_model.id} streaming started');

      // Parse SSE events: "data: {json}\n\n"
      String lineBuf = '';
      await for (final chunk in streamed.stream.transform(const Utf8Decoder())) {
        lineBuf += chunk;
        while (lineBuf.contains('\n')) {
          final lineEnd = lineBuf.indexOf('\n');
          final line = lineBuf.substring(0, lineEnd).trim();
          lineBuf = lineBuf.substring(lineEnd + 1);

          if (line.startsWith('data: ')) {
            try {
              final json = jsonDecode(line.substring(6)) as Map<String, dynamic>;
              final text = _extractText(json);
              if (text.isNotEmpty && text != 'Could not analyze the image.') {
                yield text;
              }
            } catch (e) {
              debugPrint('[VisionAI] SSE parse error: $e');
            }
          }
        }
      }

      // Flush remaining data — the last SSE line may not end with \n
      final remaining = lineBuf.trim();
      if (remaining.startsWith('data: ')) {
        try {
          final json = jsonDecode(remaining.substring(6)) as Map<String, dynamic>;
          final text = _extractText(json);
          if (text.isNotEmpty && text != 'Could not analyze the image.') {
            yield text;
          }
        } catch (e) {
          debugPrint('[VisionAI] SSE flush parse error: $e');
        }
      }

      debugPrint('[VisionAI] stream complete');
    } finally {
      client.close();
    }
  }

  String _extractText(Map<String, dynamic> json) {
    final candidates = json['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      return 'Could not analyze the image.';
    }
    final content = candidates[0]['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) {
      return 'Could not analyze the image.';
    }
    final sb = StringBuffer();
    for (final part in parts) {
      final txt = part['text'] as String?;
      if (txt != null) sb.write(txt);
    }
    final result = sb.toString().trim();
    return result.isEmpty ? 'Could not analyze the image.' : result;
  }
}
