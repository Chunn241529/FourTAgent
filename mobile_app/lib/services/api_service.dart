import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'storage_service.dart';

/// API Service for HTTP requests
class ApiService {
  static final _client = http.Client();

  /// Get headers with authentication token
  static Future<Map<String, String>> _getHeaders() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET request
  static Future<http.Response> get(String endpoint, {Map<String, String>? queryParams}) async {
    final headers = await _getHeaders();
    var uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
    if (queryParams != null) {
      uri = uri.replace(queryParameters: queryParams);
    }
    return await _client.get(uri, headers: headers);
  }

  /// POST request
  static Future<http.Response> post(String endpoint, {Map<String, dynamic>? body}) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
    return await _client.post(
      uri,
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  /// PUT request
  static Future<http.Response> put(String endpoint, {Map<String, dynamic>? body}) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
    return await _client.put(
      uri,
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  /// DELETE request
  static Future<http.Response> delete(String endpoint) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
    return await _client.delete(uri, headers: headers);
  }

  /// Streaming POST request for chat
  static Stream<String> postStream(String endpoint, Map<String, dynamic> body) async* {
    final token = await StorageService.getToken();
    final userId = await StorageService.getUserId();
    
    final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
    final request = http.Request('POST', uri);
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      if (token != null) 'Authorization': 'Bearer $token',
    });
    request.body = jsonEncode(body);
    
    final response = await _client.send(request);
    
    // Use LineSplitter to properly handle SSE lines that may be split across HTTP chunks
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.isNotEmpty) {
        yield line;
      }
    }
  }

  /// Parse response and throw on error
  static dynamic parseResponse(http.Response response) {
    final body = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }
    if (body is Map) {
      throw ApiException(
        body['detail'] ?? body['message'] ?? 'Unknown error',
        response.statusCode,
      );
    }
    throw ApiException('Request failed', response.statusCode);
  }

  /// Upload audio file for transcription
  static Future<Map<String, dynamic>> transcribeAudio(File file) async {
    final token = await StorageService.getToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}/voice/transcribe');
    
    var request = http.MultipartRequest('POST', uri);
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    
    print('>>> Uploading audio for transcription: ${file.path}');
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to transcribe audio: ${response.body}');
    }
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}
