import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'api_service.dart';
import 'storage_service.dart';

/// Service for interacting with the Affiliate Automation backend APIs.
class AffiliateService {
  static String get baseUrl => ApiConfig.baseUrl;

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

  /// Delete a saved product.
  static Future<void> deleteProduct(String platform, String productId) async {
    final response = await ApiService.delete('/affiliate/products/$platform/$productId');
    ApiService.parseResponse(response);
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

  /// Generate script with manual product entry (no scrape needed).
  static Future<Map<String, dynamic>> generateScriptManual({
    required String name,
    String? description,
    String? price,
    String style = 'genz',
    String duration = '30s',
    String? customPrompt,
    List<String>? imageUrls,
  }) async {
    final response = await ApiService.post(
      '/affiliate/generate-script',
      body: {
        'manual_product': {
          'name': name,
          if (description != null) 'description': description,
          if (price != null) 'price': price,
          if (imageUrls != null && imageUrls.isNotEmpty) 'image_urls': imageUrls,
        },
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

  /// Start an AI video generation job.
  static Future<Map<String, dynamic>> generateAiVideo({
    required String prompt,
    String? imageUrl,
    String? modelImageUrl,
    required String model,
    required String apiKey,
  }) async {
    final response = await ApiService.post(
      '/affiliate/generate-ai-video',
      body: {
        'prompt': prompt,
        if (imageUrl != null) 'image_url': imageUrl,
        if (modelImageUrl != null) 'model_image_url': modelImageUrl,
        'model': model,
        'api_key': apiKey,
      },
    );
    return ApiService.parseResponse(response);
  }

  /// Check AI video job status.
  static Future<Map<String, dynamic>> checkAiVideoStatus({
    required String jobId,
    required String apiKey,
  }) async {
    final response = await ApiService.get(
      '/affiliate/ai-video-jobs/$jobId/status?api_key=$apiKey',
    );
    return ApiService.parseResponse(response);
  }

  /// Get available smart reup transforms.
  static Future<Map<String, String>> getTransforms() async {
    final response = await ApiService.get('/affiliate/smart-reup/transforms');
    final data = ApiService.parseResponse(response);
    return Map<String, String>.from(data['transforms'] ?? {});
  }

  /// Upload video or use existing path/id for smart reup processing.
  static Future<Map<String, dynamic>> smartReupVideo({
    File? videoFile,
    String? sourcePath,
    String? productId,
    required List<String> transforms,
  }) async {
    final token = await StorageService.getToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}/affiliate/smart-reup');

    final request = http.MultipartRequest('POST', uri);
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    if (videoFile != null) {
      request.files.add(await http.MultipartFile.fromPath('file', videoFile.path));
    }
    if (sourcePath != null) {
      request.fields['source_path'] = sourcePath;
    }
    if (productId != null) {
      request.fields['product_id'] = productId;
    }
    request.fields['transforms'] = transforms.join(',');

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Smart reup failed: ${response.statusCode} ${response.body}');
  }

  /// Smart Reup Douyin - paste Douyin URL or upload local video.
  static Future<String> smartReupDouyin({
    String? url,
    File? videoFile,
    List<String>? transforms,
    Map<String, double>? cropSettings,
    String audioMode = 'strip',  // 'strip' | 'shift'
    String logoRemoval = 'none',  // 'none' | 'manual' | 'ai'
    // Subtitle options
    bool blurSubtitles = false,
    Map<String, int>? blurRegion,
    bool burnSubtitles = false,
    String? subtitleFile,
    String? subtitleText,
    double? subtitleDuration,
    Map<String, dynamic>? subtitleStyle,
  }) async {
    final token = await StorageService.getToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}/affiliate/smart-reup-douyin');

    final request = http.MultipartRequest('POST', uri);
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    if (videoFile != null) {
      request.files.add(await http.MultipartFile.fromPath('file', videoFile.path));
    }
    if (url != null) {
      request.fields['url'] = url;
    }
    if (transforms != null && transforms.isNotEmpty) {
      request.fields['transforms'] = transforms.join(',');
    }
    if (cropSettings != null) {
      request.fields['crop_settings_json'] = jsonEncode(cropSettings);
    }
    request.fields['audio_mode'] = audioMode;
    request.fields['logo_removal'] = logoRemoval;
    // Subtitle params
    request.fields['blur_subtitles'] = blurSubtitles.toString();
    if (blurRegion != null) {
      request.fields['blur_region_json'] = jsonEncode(blurRegion);
    }
    request.fields['burn_subtitles'] = burnSubtitles.toString();
    if (subtitleFile != null) {
      request.fields['subtitle_file'] = subtitleFile;
    }
    if (subtitleText != null) {
      request.fields['subtitle_text'] = subtitleText;
    }
    if (subtitleDuration != null) {
      request.fields['subtitle_duration'] = subtitleDuration.toString();
    }
    if (subtitleStyle != null) {
      request.fields['subtitle_style_json'] = jsonEncode(subtitleStyle);
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['job_id'] as String;
    }
    throw Exception('Smart Reup Douyin failed: ${response.statusCode} ${response.body}');
  }

  /// Extract a frame from video for subtitle region selection.
  /// Returns map with 'image' (base64 data URL), 'video_width', 'video_height'.
  static Future<Map<String, dynamic>> extractFrame({File? videoFile, String? videoUrl, double timestamp = 1.0}) async {
    final token = await StorageService.getToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}/affiliate/smart-reup/extract-frame');

    final request = http.MultipartRequest('POST', uri);
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    if (videoFile != null) {
      request.files.add(await http.MultipartFile.fromPath('file', videoFile.path));
    }
    if (videoUrl != null) {
      request.fields['url'] = videoUrl;
    }
    request.fields['timestamp'] = timestamp.toString();

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'image': data['image'] as String,
        'video_width': data['video_width'] as int?,
        'video_height': data['video_height'] as int?,
      };
    }
    throw Exception('Extract frame failed: ${response.statusCode} ${response.body}');
  }

  /// Upload an SRT/ASS subtitle file.
  /// Returns the filename/path of the uploaded subtitle.
  static Future<String> uploadSubtitle(File subtitleFile) async {
    final token = await StorageService.getToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}/affiliate/upload-subtitle');

    final request = http.MultipartRequest('POST', uri);
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.files.add(await http.MultipartFile.fromPath('file', subtitleFile.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['path'] as String;
    }
    throw Exception('Upload subtitle failed: ${response.statusCode} ${response.body}');
  }

  /// Upload custom model image for AI Video generation.
  static Future<Map<String, dynamic>> uploadModelImage(File imageFile) async {
    final token = await StorageService.getToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}/affiliate/upload-model-image');

    final request = http.MultipartRequest('POST', uri);
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Model image upload failed: ${response.statusCode} ${response.body}');
  }

  /// Get LLM provider status.
  static Future<List<dynamic>> getLlmProviders() async {
    final response = await ApiService.get('/affiliate/llm-providers');
    final data = ApiService.parseResponse(response);
    return data['providers'] ?? [];
  }
}
