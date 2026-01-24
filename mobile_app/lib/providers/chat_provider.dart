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
  bool _isNamingInProgress = false;  // Lock to prevent parallel naming requests

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
      _conversations = await ChatService.getConversations();
      // Sort by created_at descending (newest first)
      _conversations.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
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
  Future<void> sendMessage(String content, {String? file}) async {
    if (_currentConversation == null || content.trim().isEmpty) return;
    
    // Stop any existing stream
    stopStreaming();

    final userId = await StorageService.getUserId() ?? 0;

    // Add user message
    final userMessage = Message(
      userId: userId,
      conversationId: _currentConversation!.id,
      content: content,
      role: 'user',
      timestamp: DateTime.now(),
      imageBase64: file, // Store image for display
    );
    _messages.add(userMessage);
    notifyListeners();

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
      String fullThinking = '';
      DateTime lastUpdate = DateTime.now();
      
      // Use listen instead of await for to enable cancellation
      final stream = ChatService.sendMessage(
        _currentConversation!.id,
        content,
        file: file,
      );

      final completer = Completer<void>();

      _streamSubscription = stream.listen(
        (chunk) {
          final lines = chunk.split('\n');
          bool shouldNotify = false;

          for (final line in lines) {
            String? jsonStr;
            if (line.startsWith('data: ')) {
               jsonStr = line.substring(6).trim();
            } else if (line.startsWith('data:')) {
               jsonStr = line.substring(5).trim();
            }

            if (jsonStr != null) {
              if (jsonStr == '[DONE]') {
                print('>>> Stream [DONE] received');
                continue;
              }

              // Debug: log every data chunk
              print('>>> Chunk: $jsonStr');

              try {
                final data = _parseJson(jsonStr);
                if (data == null) continue;

                // Handle message_saved event to get the message ID
                if (data['message_saved'] != null) {
                  final messageId = data['message_saved']['id'] as int?;
                  print('>>> message_saved found! ID: $messageId');
                  if (messageId != null) {
                    final lastIndex = _messages.length - 1;
                    if (lastIndex >= 0 && _messages[lastIndex].role == 'assistant') {
                      _messages[lastIndex] = _messages[lastIndex].copyWith(id: messageId);
                      shouldNotify = true;
                      print('>>> Message ID applied: $messageId');
                      
                      // Now that message is saved in DB, trigger auto-naming
                      _maybeGenerateTitle();
                    }
                  }
                }

                // Handle tool_calls event - add search to active searches
                if (data['tool_calls'] != null) {
                  final toolCalls = data['tool_calls'] as List;
                  for (final tc in toolCalls) {
                    if (tc['function'] != null && tc['function']['name'] == 'web_search') {
                      final args = tc['function']['arguments'];
                      String? query;
                      if (args is Map) {
                        query = args['query'] as String?;
                      } else if (args is String) {
                        try {
                          final parsed = _parseJson(args);
                          query = parsed?['query'] as String?;
                        } catch (_) {}
                      }
                      if (query != null) {
                        final lastIndex = _messages.length - 1;
                        if (lastIndex >= 0) {
                          final currentSearches = List<String>.from(_messages[lastIndex].activeSearches);
                          final currentCompleted = _messages[lastIndex].completedSearches;
                          
                          // Deduplicate: Don't add if already active OR already completed
                          if (!currentSearches.contains(query) && !currentCompleted.contains(query)) {
                            currentSearches.add(query!);
                            
                            // Append marker to content for interleaved display
                            // We add double newlines to ensure it breaks from previous text
                            final marker = '\n\n[[SEARCH:$query]]\n\n';
                            fullResponse += marker; // CRITICAL: Update source of truth accumulator
                            
                            _messages[lastIndex] = _messages[lastIndex].copyWith(
                              activeSearches: currentSearches,
                              content: fullResponse, 
                            );
                            shouldNotify = true;
                            print('>>> Search started: $query');
                          }
                        }
                      }
                    }
                  }
                }

                // Handle search_complete event - move to completed searches (keep visible)
                if (data['search_complete'] != null) {
                  final query = data['search_complete']['query'] as String?;
                  if (query != null) {
                    final lastIndex = _messages.length - 1;
                    if (lastIndex >= 0) {
                      final currentActive = List<String>.from(_messages[lastIndex].activeSearches);
                      final currentCompleted = List<String>.from(_messages[lastIndex].completedSearches);
                      
                      // Move from active to completed
                      if (currentActive.contains(query)) {
                        currentActive.remove(query);
                        // Only add to completed if not already there
                        if (!currentCompleted.contains(query)) {
                          currentCompleted.add(query!);
                        }
                        
                        _messages[lastIndex] = _messages[lastIndex].copyWith(
                          activeSearches: currentActive,
                          completedSearches: currentCompleted,
                        );
                        shouldNotify = true;
                        print('>>> Search complete: $query');
                      }
                    }
                  }
                }
            
                // Handle deep_search_update event
                if (data['deep_search_update'] != null) {
                   final update = data['deep_search_update'];
                   final message = update['message'] as String?;
                   
                   if (message != null) {
                     final lastIndex = _messages.length - 1;
                     if (lastIndex >= 0) {
                        final currentUpdates = List<String>.from(_messages[lastIndex].deepSearchUpdates);
                        // Avoid duplicates if possible, or just append log
                        if (currentUpdates.isEmpty || currentUpdates.last != message) {
                           currentUpdates.add(message);
                           
                           _messages[lastIndex] = _messages[lastIndex].copyWith(
                             deepSearchUpdates: currentUpdates,
                           );
                           shouldNotify = true;
                           print('>>> Deep Search Update: $message');
                        }
                     }
                   }
                }

                // Handle plan event (for PlanIndicator widget)
                if (data['plan'] != null) {
                  final plan = data['plan'] as String;
                  final lastIndex = _messages.length - 1;
                  if (lastIndex >= 0) {
                    _messages[lastIndex] = _messages[lastIndex].copyWith(plan: plan);
                    shouldNotify = true;
                    print('>>> Plan received: ${plan.length} chars');
                  }
                }

                // Handle thinking event (top-level, from chat_service)
                if (data['thinking'] != null) {
                  final thinkingDelta = data['thinking'] as String;
                  if (thinkingDelta.isNotEmpty) {
                    fullThinking += thinkingDelta;
                    final lastIndex = _messages.length - 1;
                    if (lastIndex >= 0) {
                      _messages[lastIndex] = _messages[lastIndex].copyWith(
                        thinking: fullThinking,
                      );
                      shouldNotify = true;
                    }
                  }
                }                if (data['message'] != null) {
                  final contentDelta = data['message']['content'] as String? ?? '';
                  final thinkingDelta = data['message']['thinking'] as String? ?? '';
                  
                  if (contentDelta.isNotEmpty) {
                    fullResponse += contentDelta;
                  }
                  if (thinkingDelta.isNotEmpty) {
                    fullThinking += thinkingDelta;
                  }
                  
                  // Throttling: Update UI every 100ms max (increased from 50ms for better performance)
                  // This reduces UI rebuilds while maintaining smooth visual updates
                  if (contentDelta.isNotEmpty || thinkingDelta.isNotEmpty) {
                    final now = DateTime.now();
                    if (now.difference(lastUpdate).inMilliseconds > 100) {
                      final lastIndex = _messages.length - 1;
                      if (lastIndex >= 0) {
                         _messages[lastIndex] = _messages[lastIndex].copyWith(
                           content: fullResponse,
                           thinking: fullThinking.isNotEmpty ? fullThinking : null,
                         );
                         lastUpdate = now;
                         shouldNotify = true;
                      }
                    }
                  }
                }
                
                if (data['error'] != null) {
                  fullResponse += '\n\nError: ${data['error']}';
                  shouldNotify = true;
                }
              } catch (e) {
                print('JSON parse error: $e');
              }
            }
          }

          // Debounce notifyListeners to avoid excessive rebuilds
          if (shouldNotify) {
            notifyListeners();
          }
        },
        onError: (e) {
          _error = e.toString();
          final lastIndex = _messages.length - 1;
          if (lastIndex >= 0) {
            _messages[lastIndex] = _messages[lastIndex].copyWith(
              content: 'Error: ${e.toString()}',
              isStreaming: false,
            );
          }
          notifyListeners();
          completer.complete();
        },
        onDone: () async {
          // Final update to ensure complete message is shown
          final lastIndex = _messages.length - 1;
          if (lastIndex >= 0) {
             // If fullResponse is still empty, maybe show a fallback
             if (fullResponse.isEmpty) {
                fullResponse = '...'; // Placeholder if totally empty
             }
             
             _messages[lastIndex] = _messages[lastIndex].copyWith(
               content: fullResponse, 
               isStreaming: false,
             );
          }
          

          
          notifyListeners();
          completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;

    } catch (e) {
      _error = e.toString();
      final lastIndex = _messages.length - 1;
      _messages[lastIndex] = _messages[lastIndex].copyWith(
        content: 'Error: ${e.toString()}',
        isStreaming: false,
      );
    } finally {
      _isStreaming = false;
      _streamSubscription = null;
      notifyListeners();
    }
  }

  /// Generate conversation title after first exchange
  Future<void> _maybeGenerateTitle() async {
    print('>>> _maybeGenerateTitle called. msgs: ${_messages.length}, title: ${_currentConversation?.title}, isNaming: $_isNamingInProgress');
    
    // Skip if already naming or no conversation
    if (_isNamingInProgress) return;
    if (_currentConversation == null) return;
    
    // Skip if already has a title
    if (_currentConversation!.title != null && _currentConversation!.title!.isNotEmpty) {
      print('>>> Skipped: Has title: ${_currentConversation!.title}');
      return;
    }
    
    // Need at least 1 message (the user query)
    if (_messages.length < 1) {
      print('>>> Skipped: Not enough messages');
      return;
    }
    
    _isNamingInProgress = true;
    
    try {
      final title = await ChatService.generateTitle(_currentConversation!.id);
      
      if (title != null && title.isNotEmpty) {
        // Update current conversation
        _currentConversation = Conversation(
          id: _currentConversation!.id,
          userId: _currentConversation!.userId,
          createdAt: _currentConversation!.createdAt,
          title: title,
        );
        
        // Update in conversations list
        final idx = _conversations.indexWhere((c) => c.id == _currentConversation!.id);
        if (idx >= 0) {
          _conversations[idx] = _currentConversation!;
        }
        
        notifyListeners();
      }
    } catch (e) {
      // ignore
    } finally {
      _isNamingInProgress = false;
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


  /// Stop streaming and save partial response
  void stopStreaming() {
    _streamSubscription?.cancel();
    _isStreaming = false;
    final lastIndex = _messages.length - 1;
    if (lastIndex >= 0 && _messages[lastIndex].isStreaming) {
      final partialMessage = _messages[lastIndex];
      _messages[lastIndex] = partialMessage.copyWith(isStreaming: false);
      
      // Save partial response to DB asynchronously
      if (partialMessage.content.isNotEmpty && _currentConversation != null) {
        ChatService.savePartialMessage(
          conversationId: _currentConversation!.id,
          content: partialMessage.content,
          role: partialMessage.role,
        ).catchError((e) {
          print('Failed to save partial message: $e');
        });
      }
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

  /// Submit feedback for a message
  Future<void> submitFeedback(int messageId, String feedbackType) async {
    try {
      await ChatService.submitFeedback(messageId, feedbackType);
      // Update local message state
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(feedback: feedbackType);
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
}

