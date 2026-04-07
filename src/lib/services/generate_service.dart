import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';
import '../config/api_config.dart';

/// Service for stateless AI text generation (Studio features)
/// Uses /generate endpoint without saving conversation history
class GenerateService {

  /// Stream text generation from LLM
  /// Returns stream of content chunks
  static Stream<String> generate({
    required String prompt,
    String? systemPrompt,
    String model = 'gemma4:e4b',
    double temperature = 0.2,
  }) async* {
    final token = await StorageService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.generateStream}');

    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = 'Bearer $token';

    final StringBuffer jsonBody = StringBuffer('{');
    jsonBody.write('"prompt": ${_jsonEncode(prompt)}');
    jsonBody.write(', "model": "$model"');
    jsonBody.write(', "temperature": $temperature');
    if (systemPrompt != null) {
      jsonBody.write(', "system_prompt": ${_jsonEncode(systemPrompt)}');
    }
    jsonBody.write('}');
    request.body = jsonBody.toString();

    final client = http.Client();
    try {
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Generate failed: ${response.statusCode}');
      }

      await for (final chunk in response.stream.transform(const Utf8Decoder())) {
        yield chunk;
      }
    } finally {
      client.close();
    }
  }
  
  /// Helper to properly encode JSON string
  static String _jsonEncode(String value) {
    return '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n').replaceAll('\r', '\\r').replaceAll('\t', '\\t')}"';
  }

  /// Translate subtitle/text using backend service
  /// Returns stream of translated text chunks
  /// Backend handles prompt building + model selection
  static Stream<String> translate({
    required String text,
    bool withContext = false,
    String context = "",
    double temperature = 0.4,
  }) async* {
    final token = await StorageService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.translate}');

    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = 'Bearer $token';

    final StringBuffer jsonBody = StringBuffer('{');
    jsonBody.write('"text": ${_jsonEncode(text)}');
    jsonBody.write(', "with_context": $withContext');
    if (context.isNotEmpty) {
      jsonBody.write(', "context": ${_jsonEncode(context)}');
    }
    jsonBody.write(', "temperature": $temperature');
    jsonBody.write('}');
    request.body = jsonBody.toString();

    final client = http.Client();
    try {
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Translate failed: ${response.statusCode}');
      }

      await for (final chunk in response.stream.transform(const Utf8Decoder())) {
        yield chunk;
      }
    } finally {
      client.close();
    }
  }
}
