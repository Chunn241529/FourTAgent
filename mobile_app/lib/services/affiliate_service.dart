import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'api_service.dart';
import 'storage_service.dart';

/// Service for interacting with the Affiliate Automation backend APIs.
class AffiliateService {
  /// Get status of all LLM providers and ComfyUI.
  static Future<Map<String, dynamic>> getStatus() async {
    final response = await ApiService.get('/affiliate/status');
    return ApiService.parseResponse(response);
  }

  /// Scrape products from a platform.
  static Future<Map<String, dynamic>> scrapeProducts({
    required String platform,
    String? keyword,
    String? url,
    int limit = 10,
  }) async {
    final response = await ApiService.post(
      '/affiliate/scrape',
      body: {
        'platform': platform,
        if (keyword != null) 'keyword': keyword,
        if (url != null) 'url': url,
        'limit': limit,
      },
    );
    return ApiService.parseResponse(response);
  }

  /// List all saved products.
  static Future<List<dynamic>> listProducts() async {
    final response = await ApiService.get('/affiliate/products');
    final data = ApiService.parseResponse(response);
    return data['products'] ?? [];
  }

  /// Generate a viral script for a product.
  static Future<Map<String, dynamic>> generateScript({
    required String productId,
    String style = 'genz',
    String duration = '30s',
    String? customPrompt,
  }) async {
    final response = await ApiService.post(
      '/affiliate/generate-script',
      body: {
        'product_id': productId,
        'style': style,
        'duration': duration,
        if (customPrompt != null) 'custom_prompt': customPrompt,
      },
    );
    return ApiService.parseResponse(response);
  }

  /// Start a video render job (background task).
  static Future<String> startRenderVideo({
    required String productId,
    required String scriptText,
    bool useTts = false,
    String? voiceId,
    int? bgmIndex,
    double durationPerImage = 3.0,
  }) async {
    final response = await ApiService.post(
      '/affiliate/render-video',
      body: {
        'product_id': productId,
        'script_text': scriptText,
        'use_tts': useTts,
        if (voiceId != null) 'voice_id': voiceId,
        if (bgmIndex != null) 'bgm_index': bgmIndex,
        'duration_per_image': durationPerImage,
      },
    );
    final data = ApiService.parseResponse(response);
    return data['job_id'];
  }

  /// Check render job status.
  static Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final response = await ApiService.get('/affiliate/jobs/$jobId');
    return ApiService.parseResponse(response);
  }

  /// Get available smart reup transforms.
  static Future<Map<String, String>> getTransforms() async {
    final response = await ApiService.get('/affiliate/smart-reup/transforms');
    final data = ApiService.parseResponse(response);
    return Map<String, String>.from(data['transforms'] ?? {});
  }

  /// Upload video for smart reup processing.
  static Future<Map<String, dynamic>> smartReupVideo({
    required File videoFile,
    required List<String> transforms,
  }) async {
    final token = await StorageService.getToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}/affiliate/smart-reup');

    final request = http.MultipartRequest('POST', uri);
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.files.add(await http.MultipartFile.fromPath('file', videoFile.path));
    request.fields['transforms'] = transforms.join(',');

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Smart reup failed: ${response.statusCode} ${response.body}');
  }

  /// Get LLM provider status.
  static Future<List<dynamic>> getLlmProviders() async {
    final response = await ApiService.get('/affiliate/llm-providers');
    final data = ApiService.parseResponse(response);
    return data['providers'] ?? [];
  }
}
