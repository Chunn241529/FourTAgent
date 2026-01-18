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
  static Stream<String> sendMessage(int conversationId, String message) async* {
    // userId is handled by backend via token
    
    yield* ApiService.postStream(
      '${ApiConfig.chat}?conversation_id=$conversationId',
      {'message': message},
    );
  }
}
