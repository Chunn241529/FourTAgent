import 'dart:async';
import '../config/api_config.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import 'api_service.dart';

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
  static Stream<String> sendMessage(int conversationId, String message, {String? file}) async* {
    // userId is handled by backend via token
    
    final body = <String, dynamic>{
      'message': message,
    };
    if (file != null) {
      body['file'] = file;
    }
    
    yield* ApiService.postStream(
      '${ApiConfig.chat}?conversation_id=$conversationId',
      body,
    );
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
}

