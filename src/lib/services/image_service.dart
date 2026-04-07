import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'storage_service.dart';
import 'api_service.dart';

class ImageService {
  /// Generate an image from text prompt (Image Studio - uses LLM cloud for translation)
  static Future<Map<String, dynamic>> generateImage(
    String description, {
    String size = '768x768',
  }) async {
    final token = await StorageService.getToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.generateImageStudio}');

    var request = http.MultipartRequest('POST', uri);
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.fields['description'] = description;
    request.fields['size'] = size;

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body['error'] != null) {
        throw Exception(body['error']);
      }
      return body;
    } else {
      String errorMessage = 'Failed to generate image';
      try {
        final errorBody = jsonDecode(response.body);
        if (errorBody['detail'] != null) {
          errorMessage = errorBody['detail'].toString();
        }
      } catch (_) {}
      throw Exception(errorMessage);
    }
  }

  /// Edit image(s) for Image Studio — image1 required, image2 optional
  /// Uses LLM cloud for prompt translation (no history/RAG)
  static Future<Map<String, dynamic>> editImage({
    required File image1,
    File? image2,
    required String prompt,
    bool tryon = false,
    bool detail = false,
    bool pixel = false,
    bool pose = false,
  }) async {
    final token = await StorageService.getToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.editImageStudio}');

    var request = http.MultipartRequest('POST', uri);
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.fields['prompt'] = prompt;
    request.fields['tryon'] = tryon.toString();
    request.fields['detail'] = detail.toString();
    request.fields['pixel'] = pixel.toString();
    request.fields['pose'] = pose.toString();
    
    // image1 — required
    request.files
        .add(await http.MultipartFile.fromPath('image1', image1.path));

    // image2 — optional
    if (image2 != null) {
      request.files
          .add(await http.MultipartFile.fromPath('image2', image2.path));
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body['error'] != null) {
        throw Exception(body['error']);
      }
      return body;
    } else {
      String errorMessage = 'Failed to edit image';
      try {
        final errorBody = jsonDecode(response.body);
        if (errorBody['detail'] != null) {
          errorMessage = errorBody['detail'].toString();
        }
      } catch (_) {}
      throw Exception(errorMessage);
    }
  }

  /// Helper to build full URL for a generated image filename
  static String getImageUrl(String filename) {
    if (filename.isEmpty) return '';
    final safeName = filename.split('/').last.split('\\').last;
    return '${ApiConfig.baseUrl}${ApiConfig.generatedImage}/$safeName';
  }
}
