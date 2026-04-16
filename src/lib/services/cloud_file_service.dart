import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
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
        ApiConfig.cloudFiles,
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
        ApiConfig.cloudFilesContent,
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

  /// Download binary file (video, image) to downloads folder and return local path
  static Future<String> downloadBinaryFile(String cloudPath, String filename) async {
    try {
      final token = await StorageService.getToken();
      final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.cloudFilesDownload}?path=${Uri.encodeComponent(cloudPath)}');
      
      final response = await http.get(
        uri,
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        // Get downloads directory
        Directory? downloadsDir;
        if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
          downloadsDir = await getDownloadsDirectory();
        }
        // Fallback to temp if no downloads dir found
        downloadsDir ??= Directory.systemTemp;
        
        final localFile = File('${downloadsDir.path}/$filename');
        await localFile.writeAsBytes(response.bodyBytes);
        return localFile.path;
      } else {
        throw ApiException('Failed to download file', response.statusCode);
      }
    } catch (e) {
      print('Error downloading binary file: $e');
      rethrow;
    }
  }

  /// Create a folder
  static Future<void> createFolder(String path) async {
    try {
      await ApiService.post(
        ApiConfig.cloudFolders,
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
      final response = await ApiService.delete('${ApiConfig.cloudFiles}?path=$path');
      ApiService.parseResponse(response);
    } catch (e) {
      print('Error deleting cloud item: $e');
      rethrow;
    }
  }

  // Upload file with progress callback
  static Future<void> uploadFile(
    File file, 
    String targetDirectory, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final token = await StorageService.getToken();
      final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.cloudFilesUpload}');
      
      // Get file size for progress calculation
      final fileSize = await file.length();
      int uploadedBytes = 0;
      
      // Create custom request with streaming file content
      final request = http.StreamedRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Content-Type'] = 'multipart/form-data';
      
      // Build multipart manually with streaming
      final boundary = '----FlutterFormBoundary${DateTime.now().millisecondsSinceEpoch}';
      request.headers['Content-Type'] = 'multipart/form-data; boundary=$boundary';
      
      // Add path field
      final pathField = '--$boundary\r\n'
          'Content-Disposition: form-data; name="path"\r\n\r\n'
          '$targetDirectory\r\n';
      request.sink.add(utf8.encode(pathField));
      
      // Add file header
      final fileName = file.path.split('/').last;
      final fileHeader = '--$boundary\r\n'
          'Content-Disposition: form-data; name="file"; filename="$fileName"\r\n'
          'Content-Type: application/octet-stream\r\n\r\n';
      request.sink.add(utf8.encode(fileHeader));
      
      // Stream file chunks with progress
      final fileStream = file.openRead();
      final sink = request.sink;
      
      await for (final chunk in fileStream) {
        sink.add(chunk);
        uploadedBytes += chunk.length;
        onProgress?.call(uploadedBytes / fileSize);
      }
      
      // Close multipart
      sink.add(utf8.encode('\r\n--$boundary--\r\n'));
      await sink.close();
      
      // Send request
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

  /// Build the stream URL for binary file access (video/image)
  static String getStreamUrl(String path) {
    return '${ApiConfig.baseUrl}${ApiConfig.cloudFilesStream}?path=${Uri.encodeComponent(path)}';
  }

  /// Build the download URL for a cloud file (forces attachment download)
  static String getDownloadUrl(String path) {
    return '${ApiConfig.baseUrl}${ApiConfig.cloudFilesDownload}?path=${Uri.encodeComponent(path)}';
  }

  /// Check if file is a video
  static bool isVideoFile(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'webm', 'flv', 'wmv'].contains(ext);
  }

  /// Check if file is an image
  static bool isImageFile(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  /// Download file to local storage (returns local file path)
  static Future<String> downloadToLocal(String cloudPath, String localPath) async {
    try {
      final token = await StorageService.getToken();
      final downloadUrl = getDownloadUrl(cloudPath);
      final response = await http.get(
        Uri.parse(downloadUrl),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        final file = File(localPath);
        await file.writeAsBytes(response.bodyBytes);
        return localPath;
      } else {
        throw ApiException('Failed to download file', response.statusCode);
      }
    } catch (e) {
      print('Error downloading file to local: $e');
      rethrow;
    }
  }
}
