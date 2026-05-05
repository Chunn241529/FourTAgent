import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import 'api_service.dart';
import 'storage_service.dart';

/// Result wrapper for sendMessageWithQueueCheck
class SendMessageResult {
  final bool isQueued;
  final int? jobId;
  final String? message;
  final Stream<String>? stream;

  SendMessageResult({
    required this.isQueued,
    this.jobId,
    this.message,
    this.stream,
  });
}

/// Chat service for conversations and messages
class ChatService {
  /// Get all conversations
  static Future<List<Conversation>> getConversations() async {
    final response = await ApiService.get('${ApiConfig.conversations}/');
    
    if (response.statusCode == 200) {
      // Debug: Log full response
      print('>>> GET /conversations response: ${response.body}');
      
      final List<dynamic> data = ApiService.parseResponse(response) as List? ?? [];
      return data.map((json) => Conversation.fromJson(json)).toList();
    }
    throw ApiException('Failed to load conversations', response.statusCode);
  }

  /// Create new conversation
  static Future<Conversation> createConversation() async {
    final response = await ApiService.post('${ApiConfig.conversations}/');
    final data = ApiService.parseResponse(response);
    return Conversation.fromJson(data);
  }

  /// Delete conversation
  static Future<void> deleteConversation(int conversationId) async {
    final response = await ApiService.delete('${ApiConfig.conversations}/$conversationId');
    if (response.statusCode != 200) {
      throw ApiException('Failed to delete conversation', response.statusCode);
    }
  }

  /// Delete all conversations
  static Future<void> deleteAllConversations() async {
    final response = await ApiService.delete('${ApiConfig.conversations}/');
    if (response.statusCode != 200) {
      throw ApiException('Failed to delete all conversations', response.statusCode);
    }
  }

  /// Generate title for a conversation using AI
  static Future<String?> generateTitle(int conversationId) async {
    try {
      final url = '${ApiConfig.conversations}/$conversationId/generate-title';
      print('>>> Calling POST $url');
      final response = await ApiService.post(url);
      
      print('>>> Generate Title Response: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = ApiService.parseResponse(response);
        return data['title'] as String?;
      }
      return null;
    } catch (e) {
      print('Error generating title: $e');
      return null;
    }
  }

  /// Get messages for a conversation
  static Future<List<Message>> getMessages(int conversationId) async {
    final response = await ApiService.get(
      '${ApiConfig.messages}/conversations/$conversationId/messages',
    );
    
    if (response.statusCode == 200) {
      final List<dynamic> data = ApiService.parseResponse(response) as List? ?? [];
      return data.map((json) => Message.fromJson(json)).toList();
    }
    throw ApiException('Failed to load messages', response.statusCode);
  }

  /// Send message and stream response
  static Stream<String> sendMessage(
    int conversationId, 
    String message, {
    String? file,
    bool voiceEnabled = false,
    String? voiceId,
    bool isCanvas = false,
    bool isGenerateImage = false,
    bool isDeepSearch = false,
  }) async* {
    // userId is handled by backend via token
    
    final body = <String, dynamic>{
      'message': message,
      'voice_enabled': voiceEnabled,
    };
    if (isCanvas) {
      body['is_canvas'] = true;
    }
    if (isGenerateImage) {
      body['is_generate_image'] = true;
    }
    if (isDeepSearch) {
      body['is_deep_search'] = true;
    }
    if (voiceId != null) {
      body['voice_id'] = voiceId;
    }
    if (file != null) {
      body['file'] = file;
    }
    
    // Build URL with query params
    var url = '${ApiConfig.chat}?conversation_id=$conversationId';
    if (voiceEnabled) {
      url += '&voice_enabled=true';
      if (voiceId != null) {
        url += '&voice_id=$voiceId';
      }
    }
    
    yield* ApiService.postStream(url, body);
  }

  /// Result wrapper for sendMessage that can handle queued responses
  static Future<SendMessageResult> sendMessageWithQueueCheck(
    int conversationId, 
    String message, {
    String? file,
    bool voiceEnabled = false,
    String? voiceId,
    bool isCanvas = false,
    bool isGenerateImage = false,
    bool isDeepSearch = false,
  }) async {
    final body = <String, dynamic>{
      'message': message,
      'voice_enabled': voiceEnabled,
    };
    if (isCanvas) {
      body['is_canvas'] = true;
    }
    if (isGenerateImage) {
      body['is_generate_image'] = true;
    }
    if (isDeepSearch) {
      body['is_deep_search'] = true;
    }
    if (voiceId != null) {
      body['voice_id'] = voiceId;
    }
    if (file != null) {
      body['file'] = file;
    }
    
    // Build URL with query params
    var url = '${ApiConfig.chat}?conversation_id=$conversationId';
    if (voiceEnabled) {
      url += '&voice_enabled=true';
      if (voiceId != null) {
        url += '&voice_id=$voiceId';
      }
    }
    
    // Make the request once — reuse the response stream
    final token = await StorageService.getToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}$url');
    final request = http.Request('POST', uri);
    request.headers.addAll({
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    });
    request.body = jsonEncode(body);
    
    final streamedResponse = await ApiService.client.send(request);
    
    // Check for auth/server errors
    if (streamedResponse.statusCode == 401) {
      throw ApiException('Phiên đăng nhập hết hạn', 401);
    } else if (streamedResponse.statusCode == 502 || streamedResponse.statusCode == 503) {
      throw ApiException('Server đang bận hoặc đang khởi động lại', streamedResponse.statusCode);
    }
    
    // Check content type
    final contentType = streamedResponse.headers['content-type'] ?? '';
    
    if (contentType.contains('application/json')) {
      // Queued response - read and parse JSON
      final response = await http.Response.fromStream(streamedResponse);
      final data = ApiService.parseResponse(response) as Map<String, dynamic>;
      return SendMessageResult(
        isQueued: true,
        jobId: data['job_id'] as int?,
        message: data['message'] ?? "Máy chủ đang bận",
      );
    } else {
      // Normal SSE stream — reuse the SAME response stream (no second request!)
      final stream = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      return SendMessageResult(
        isQueued: false,
        stream: stream,
      );
    }
  }

  /// Submit feedback (like/dislike) for a message
  static Future<void> submitFeedback(int messageId, String feedbackType) async {
    final response = await ApiService.post(
      '${ApiConfig.feedback}/',
      body: {
        'message_id': messageId,
        'feedback_type': feedbackType,
      },
    );
    if (response.statusCode != 200) {
      throw ApiException('Failed to submit feedback', response.statusCode);
    }
  }

  /// Get feedback for a specific message
  static Future<String?> getFeedback(int messageId) async {
    try {
      final response = await ApiService.get('${ApiConfig.feedback}/$messageId');
      if (response.statusCode == 200) {
        final data = ApiService.parseResponse(response);
        return data['feedback_type'] as String?;
      }
      return null;
    } catch (e) {
      return null; // No feedback found is not an error
    }
  }

  /// Delete feedback for a message
  static Future<void> deleteFeedback(int messageId) async {
    await ApiService.delete('${ApiConfig.feedback}/$messageId');
  }

  /// Save partial message when user stops streaming
  static Future<void> savePartialMessage({
    required int conversationId,
    required String content,
    required String role,
  }) async {
    if (content.isEmpty) return;
    
    try {
      await ApiService.post(
        '${ApiConfig.messages}/conversations/$conversationId/messages',
        body: {
          'content': content,
          'role': role,
        },
      );
    } catch (e) {
      print('Error saving partial message: $e');
      rethrow;
    }
  }

  /// Send stop signal to backend
  static Future<void> stopStreaming(int conversationId) async {
    try {
      await ApiService.post('${ApiConfig.chat}/stop/$conversationId');
      print('>>> Stop signal sent for conversation $conversationId');
    } catch (e) {
      print('Error sending stop signal: $e');
    }
  }

  /// Submit tool result with queue check
  static Future<SendMessageResult> submitToolResultWithQueueCheck(
    int conversationId,
    String toolName,
    String result, {
    String? toolCallId,
    bool voiceEnabled = false,
    String? voiceId,
  }) async {
    final body = {
      'tool_name': toolName,
      'result': result,
      'tool_call_id': toolCallId,
      'conversation_id': conversationId,
      'voice_enabled': voiceEnabled,
      'voice_id': voiceId,
    };

    final token = await StorageService.getToken();
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.chatToolResult}');
    final request = http.Request('POST', uri);
    request.headers.addAll({
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    });
    request.body = jsonEncode(body);

    final streamedResponse = await ApiService.client.send(request);

    if (streamedResponse.statusCode == 401) {
      throw ApiException('Phiên đăng nhập hết hạn', 401);
    }

    final contentType = streamedResponse.headers['content-type'] ?? '';
    if (contentType.contains('application/json')) {
      final response = await http.Response.fromStream(streamedResponse);
      final data = ApiService.parseResponse(response) as Map<String, dynamic>;
      return SendMessageResult(
        isQueued: true,
        jobId: data['job_id'] as int?,
        message: data['message'] ?? "Máy chủ đang bận",
      );
    } else {
      final stream = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      return SendMessageResult(
        isQueued: false,
        stream: stream,
      );
    }
  }
}

