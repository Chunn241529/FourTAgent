import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'api_service.dart';
import 'storage_service.dart';

class CloudFile {
  final String name;
  final String type; // 'file' or 'directory'
  final int size;
  final String path;

  CloudFile({
    required this.name,
    required this.type,
    required this.size,
    required this.path,
  });

  factory CloudFile.fromJson(Map<String, dynamic> json) {
    return CloudFile(
      name: json['name'],
      type: json['type'],
      size: json['size'],
      path: json['path'],
    );
  }
}

class CloudFileService {
  /// List files in a directory
  static Future<List<CloudFile>> listFiles(String directory) async {
    try {
      final response = await ApiService.get(
        '/cloud/files',
        queryParams: {'directory': directory},
      );
      
      final List<dynamic> data = ApiService.parseResponse(response);
      return data.map((json) => CloudFile.fromJson(json)).toList();
    } catch (e) {
      print('Error listing cloud files: $e');
      rethrow;
    }
  }

  /// Download file content
  static Future<String> downloadFile(String path) async {
    try {
      final response = await ApiService.get(
        '/cloud/files/content',
        queryParams: {'path': path},
      );
      
      if (response.statusCode == 200) {
        return utf8.decode(response.bodyBytes);
      } else {
        throw ApiException('Failed to download file', response.statusCode);
      }
    } catch (e) {
      print('Error downloading file: $e');
      rethrow;
    }
  }

  /// Create a folder
  static Future<void> createFolder(String path) async {
    try {
      await ApiService.post(
        '/cloud/folders',
        body: {'path': path},
      );
    } catch (e) {
      print('Error creating folder: $e');
      rethrow;
    }
  }

  /// Delete a file or folder
  static Future<void> delete(String path) async {
    try {
      // The delete endpoint uses query param for path
      final response = await ApiService.delete('/cloud/files?path=$path');
      ApiService.parseResponse(response);
    } catch (e) {
      print('Error deleting cloud item: $e');
      rethrow;
    }
  }

  // Upload file (Multipart)
  static Future<void> uploadFile(File file, String targetDirectory) async {
    try {
      final token = await StorageService.getToken();
      final uri = Uri.parse('${ApiConfig.baseUrl}/cloud/files/upload');
      final request = http.MultipartRequest('POST', uri);
      
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      
      // Add path field
      request.fields['path'] = targetDirectory;
      
      // Add file
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return;
      } else {
        throw ApiException(
          'Upload failed: ${response.body}',
          response.statusCode,
        );
      }
    } catch (e) {
      print('Error uploading file: $e');
      rethrow;
    }
  }
}
