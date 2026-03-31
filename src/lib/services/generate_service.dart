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
    String model = 'translategemma:4b',
    double temperature = 0.2,
  }) async* {
    final token = await StorageService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}/generate/stream');
    
    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = 'Bearer $token';
    
    final body = {
      'prompt': prompt,
      'model': model,
      'temperature': temperature,
    };
    if (systemPrompt != null) {
      body['system_prompt'] = systemPrompt;
    }
    
    request.body = Uri(queryParameters: {}).replace(
      queryParameters: null,
    ).toString().isEmpty 
        ? '{"prompt": "$prompt", "model": "$model", "temperature": $temperature${systemPrompt != null ? ', "system_prompt": "$systemPrompt"' : ''}}'
        : '';
    
    // Build proper JSON body
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
}
