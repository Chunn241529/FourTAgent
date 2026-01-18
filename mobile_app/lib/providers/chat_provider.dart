import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/chat_service.dart';
import '../services/storage_service.dart';

/// Chat state provider
class ChatProvider extends ChangeNotifier {
  List<Conversation> _conversations = [];
  List<Message> _messages = [];
  Conversation? _currentConversation;
  bool _isLoading = false;
  bool _isStreaming = false;
  String? _error;
  StreamSubscription? _streamSubscription;

  List<Conversation> get conversations => _conversations;
  List<Message> get messages => _messages;
  Conversation? get currentConversation => _currentConversation;
  bool get isLoading => _isLoading;
  bool get isStreaming => _isStreaming;
  String? get error => _error;

  /// Load all conversations
  Future<void> loadConversations() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      print('>>> CHAT: Loading conversations...');
      _conversations = await ChatService.getConversations();
      print('>>> CHAT: Loaded ${_conversations.length} conversations');
      // Sort by created_at descending (newest first)
      _conversations.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      print('>>> CHAT: Error loading conversations: $e');
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create new conversation
  Future<Conversation?> createConversation() async {
    _isLoading = true;
    notifyListeners();

    try {
      final conversation = await ChatService.createConversation();
      _conversations.insert(0, conversation);
      _currentConversation = conversation;
      _messages = [];
      notifyListeners();
      return conversation;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Select conversation and load messages
  Future<void> selectConversation(Conversation conversation) async {
    _currentConversation = conversation;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _messages = await ChatService.getMessages(conversation.id);
      // Derive title from first user message if not set
      if (conversation.title == null && _messages.isNotEmpty) {
        final firstUserMsg = _messages.firstWhere(
          (m) => m.role == 'user',
          orElse: () => _messages.first,
        );
        conversation.title = firstUserMsg.content.length > 50
            ? '${firstUserMsg.content.substring(0, 50)}...'
            : firstUserMsg.content;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Delete conversation
  Future<void> deleteConversation(int conversationId) async {
    try {
      await ChatService.deleteConversation(conversationId);
      _conversations.removeWhere((c) => c.id == conversationId);
      if (_currentConversation?.id == conversationId) {
        _currentConversation = null;
        _messages = [];
      }
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Send message and handle streaming response
  Future<void> sendMessage(String content) async {
    if (_currentConversation == null || content.trim().isEmpty) return;

    final userId = await StorageService.getUserId() ?? 0;

    // Add user message
    final userMessage = Message(
      userId: userId,
      conversationId: _currentConversation!.id,
      content: content,
      role: 'user',
      timestamp: DateTime.now(),
    );
    _messages.add(userMessage);
    notifyListeners();

    // Update conversation title if first message
    if (_currentConversation!.title == null) {
      _currentConversation!.title = content.length > 50
          ? '${content.substring(0, 50)}...'
          : content;
    }

    // Add empty assistant message for streaming
    final assistantMessage = Message(
      userId: userId,
      conversationId: _currentConversation!.id,
      content: '',
      role: 'assistant',
      timestamp: DateTime.now(),
      isStreaming: true,
    );
    _messages.add(assistantMessage);
    _isStreaming = true;
    notifyListeners();

    try {
      String fullResponse = '';
      
      await for (final chunk in ChatService.sendMessage(
        _currentConversation!.id,
        content,
      )) {
        // Parse SSE data - each chunk may contain multiple lines
        final lines = chunk.split('\n');
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            final jsonStr = line.substring(6).trim(); // Remove 'data: ' prefix
            
            // Skip [DONE] marker
            if (jsonStr == '[DONE]') continue;
            
            try {
              final data = _parseJson(jsonStr);
              if (data == null) continue;
              
              // Extract content from message.content
              if (data['message'] != null && data['message']['content'] != null) {
                final contentDelta = data['message']['content'] as String;
                if (contentDelta.isNotEmpty) {
                  fullResponse += contentDelta;
                  // Update the last message with new content
                  final lastIndex = _messages.length - 1;
                  _messages[lastIndex] = _messages[lastIndex].copyWith(
                    content: fullResponse,
                  );
                  notifyListeners();
                }
              }
              
              // Handle error
              if (data['error'] != null) {
                fullResponse += '\n\nError: ${data['error']}';
              }
              
              // Handle thinking (optional - can show later)
              // if (data['thinking'] != null) { ... }
              
            } catch (e) {
              // If JSON parsing fails, try to use raw content
              // This handles edge cases
              print('JSON parse error: $e for chunk: $jsonStr');
            }
          }
        }
      }

      // Mark streaming complete
      final lastIndex = _messages.length - 1;
      _messages[lastIndex] = _messages[lastIndex].copyWith(
        isStreaming: false,
      );
    } catch (e) {
      _error = e.toString();
      // Update message to show error
      final lastIndex = _messages.length - 1;
      _messages[lastIndex] = _messages[lastIndex].copyWith(
        content: 'Error: ${e.toString()}',
        isStreaming: false,
      );
    } finally {
      _isStreaming = false;
      notifyListeners();
    }
  }

  /// Parse JSON safely
  Map<String, dynamic>? _parseJson(String jsonStr) {
    try {
      final decoded = json.decode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }


  /// Stop streaming
  void stopStreaming() {
    _streamSubscription?.cancel();
    _isStreaming = false;
    final lastIndex = _messages.length - 1;
    if (lastIndex >= 0 && _messages[lastIndex].isStreaming) {
      _messages[lastIndex] = _messages[lastIndex].copyWith(isStreaming: false);
    }
    notifyListeners();
  }

  /// Clear current conversation
  void clearCurrentConversation() {
    _currentConversation = null;
    _messages = [];
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
