import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'storage_service.dart';

class TtsService {
  static Future<List<Voice>> getVoices() async {
    final token = await StorageService.getToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}/tts/voices');
    final response = await http.get(uri, headers: {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    });

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Voice.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load voices: ${response.statusCode}');
    }
  }

  static Future<List<int>> synthesize(String text, String voiceId) async {
    final token = await StorageService.getToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}/tts/synthesize');
    
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'text': text,
        'voice_id': voiceId,
      }),
    );

    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Synthesis failed: ${response.statusCode} - ${response.body}');
    }
  }

  static Future<Voice> createVoice(String name, File audioFile) async {
    final token = await StorageService.getToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}/tts/voices');
    
    var request = http.MultipartRequest('POST', uri);
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    
    request.fields['name'] = name;
    request.files.add(await http.MultipartFile.fromPath('files', audioFile.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return Voice.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create voice: ${response.statusCode} - ${response.body}');
    }
  }
}

class Voice {
  final String id;
  final String name;
  final String type; // 'preset' or 'custom'
  final String? refText;

  Voice({
    required this.id, 
    required this.name, 
    required this.type,
    this.refText
  });

  factory Voice.fromJson(Map<String, dynamic> json) {
    // Determine name based on type or existing fields
    // Backend returns keys like "id" (which is voice_id), "name" (readable description or id).
    // Let's assume standard structure:
    // id: "Binh", name: "Binh (nam mien Bac)", type: "preset"
    return Voice(
      id: json['id'] as String,
      name: json['description'] ?? json['id'] ?? 'Unknown Voice', // Backend uses 'description' for name in create_voice return, or mapped from presets.
      type: json['type'] ?? 'preset',
      refText: json['ref_text'],
    );
  }
}
