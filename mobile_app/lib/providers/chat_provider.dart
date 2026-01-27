import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/chat_service.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';
import '../services/file_tool_service.dart';

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
  bool _voiceModeEnabled = false;  // Voice response mode
  List<Map<String, dynamic>> _voiceAudioChunks = [];  // Audio chunks from voice response
  final AudioPlayer _voicePlayer = AudioPlayer();  // Audio player for voice response
  bool _isPlayingVoice = false;  // Currently playing voice audio
  String? _currentVoiceSentence;  // Current sentence being spoken
  
  // Voice settings
  final List<String> _availableVoices = ['Doan', 'Binh', 'Tuyen', 'Vinh', 'Ly', 'Ngoc'];
  String _currentVoiceId = 'Doan';
  bool _isMicEnabled = false; // Now tracks UI toggle, but _isRecording tracks actual state
  
  // Recorder
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isTranscribing = false;

  // Music callback for voice mode
  void Function(String url, String title, String? thumbnail, int? duration)? _musicPlayCallback;
  void Function(Map<String, dynamic> item)? _musicQueueAddCallback;
  void Function(String action)? _musicControlCallback;

  // New getter for 'Processing' state (Thinking/Transcribing but not yet Speaking)
  bool get isVoiceProcessing => _isTranscribing || (_isStreaming && !_isPlayingVoice);

  List<Conversation> get conversations => _conversations;
  List<Message> get messages => _messages;
  Conversation? get currentConversation => _currentConversation;
  bool get isLoading => _isLoading;
  bool get isStreaming => _isStreaming;
  String? get error => _error;
  bool get voiceModeEnabled => _voiceModeEnabled;
  List<Map<String, dynamic>> get voiceAudioChunks => _voiceAudioChunks;
  bool get isPlayingVoice => _isPlayingVoice;
  String? get currentVoiceSentence => _currentVoiceSentence;
  String get currentVoiceId => _currentVoiceId;
  bool get isMicEnabled => _isMicEnabled; // UI visual state (can be same as recording)
  bool get isRecording => _isRecording;
  List<String> get availableVoices => _availableVoices;
  
  // Client tool call state
  Map<String, dynamic>? _pendingClientTool;
  Map<String, dynamic>? get pendingClientTool => _pendingClientTool;

  /// Clear pending tool
  void clearPendingTool() {
    _pendingClientTool = null;
    notifyListeners();
  }

  /// Set the music play callback for voice mode
  void setMusicCallbacks({
    void Function(String url, String title, String? thumbnail, int? duration)? onPlay,
    void Function(Map<String, dynamic> item)? onQueueAdd,
    void Function(String action)? onControl,
  }) {
    if (onPlay != null) _musicPlayCallback = onPlay;
    if (onQueueAdd != null) _musicQueueAddCallback = onQueueAdd;
    if (onControl != null) _musicControlCallback = onControl;
  }

  void setVoice(String voiceId) {
    if (_availableVoices.contains(voiceId)) {
      _currentVoiceId = voiceId;
      notifyListeners();
    }
  }

  void cycleVoice() {
    final currentIndex = _availableVoices.indexOf(_currentVoiceId);
    final nextIndex = (currentIndex + 1) % _availableVoices.length;
    _currentVoiceId = _availableVoices[nextIndex];
    notifyListeners();
  }

  Future<void> toggleMic() async {
    if (_isRecording) {
      await stopRecording();
    } else {
      await startRecording();
    }
  }

  Future<void> startRecording() async {
    try {
      // On mobile, request permission explicitly. On desktop, skip this or assume granted by OS.
      bool hasPerm = true;
      if (Platform.isAndroid || Platform.isIOS) {
        hasPerm = await Permission.microphone.request().isGranted;
      }

      if (hasPerm) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/voice_input.wav';
        
        // Check permissions via recorder package
        if (await _audioRecorder.hasPermission()) {
           await _audioRecorder.start(
            const RecordConfig(encoder: AudioEncoder.wav),
            path: path,
           );
           _isRecording = true;
           _isMicEnabled = true;
           notifyListeners();
           print('>>> Started recording to $path');
        }
      }
    } catch (e) {
      print('>>> Error starting record: $e');
    }
  }

  Future<void> stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      _isRecording = false;
      _isMicEnabled = false;
      notifyListeners();
      print('>>> Stopped recording, path: $path');
      
      if (path != null) {
        await _processAudioInput(path);
      }
    } catch (e) {
      print('>>> Error stopping record: $e');
      _isRecording = false;
      notifyListeners();
    }
  }

  Future<void> _processAudioInput(String path) async {
    _isTranscribing = true;
    notifyListeners();
    
    try {
      final file = File(path);
      if (await file.exists()) {
        print('>>> Transcribing audio...');
        final result = await ApiService.transcribeAudio(file);
        final text = result['text'];
        print('>>> Transcription result: $text');
        
        if (text != null && text.toString().trim().isNotEmpty) {
           _currentVoiceSentence = "Bạn: $text"; // Show user text temporarily?
           notifyListeners();
           
           // Send message
           // Wait a bit to let user see their text?
           await Future.delayed(const Duration(milliseconds: 500));
           
           sendMessage(text, voiceEnabled: true, onMusicPlay: _musicPlayCallback);
        }
      }
    } catch (e) {
      print('>>> STT Error: $e');
      _error = 'Lỗi nhận dạng giọng nói: $e';
    } finally {
      _isTranscribing = false;
      notifyListeners();
    }
  }

  void setVoiceMode(bool enabled) {
    _voiceModeEnabled = enabled;
    if (!enabled) {
      // Stop playing and clear queue when closing voice mode
      _voicePlayer.stop();
      _voiceAudioChunks = [];
      _audioQueue.clear();
      _isProcessingQueue = false;
      _isPlayingVoice = false;
      _currentVoiceSentence = null;
      _isTranscribing = false;
    }
    notifyListeners();
  }

  void clearVoiceAudioChunks() {
    _voiceAudioChunks = [];
    _audioQueue.clear();
    notifyListeners();
  }

  // Audio queue for sequential playback
  // Audio queue for sequential playback (stores {audio: base64, sentence: string})
  final List<Map<String, String>> _audioQueue = [];
  bool _isProcessingQueue = false;

  /// Queue audio chunk for playback with sentence
  void _queueAudioChunk(String base64Audio, String? sentence) {
    _audioQueue.add({'audio': base64Audio, 'sentence': sentence ?? ''});
    print('>>> Queueing chunk. Queue size: ${_audioQueue.length}. isProcessing: $_isProcessingQueue');
    _processAudioQueue();
  }

  /// Process audio queue sequentially
  Future<void> _processAudioQueue() async {
    print('>>> _processAudioQueue called. isProcessing: $_isProcessingQueue, queueEmpty: ${_audioQueue.isEmpty}');
    
    if (_isProcessingQueue || _audioQueue.isEmpty) return;
    
    _isProcessingQueue = true;
    _isPlayingVoice = true;
    notifyListeners();
    
    // Get app documents directory for audio files (safer than temp)
    Directory? tempDir;
    try {
      tempDir = await getApplicationDocumentsDirectory();
      print('>>> Audio output dir: ${tempDir.path}');
    } catch (e) {
      print('>>> Cannot get app doc directory: $e');
      _isProcessingQueue = false;
      _isPlayingVoice = false;
      notifyListeners();
      return;
    }
    
    int chunkIndex = 0;
    
    while (_audioQueue.isNotEmpty) {
      print('>>> Processing queue item. Remaining: ${_audioQueue.length}');
      final chunk = _audioQueue.removeAt(0);
      try {
        final base64Audio = chunk['audio']!;
        _currentVoiceSentence = chunk['sentence'];
        notifyListeners();
      
        final audioBytes = base64Decode(base64Audio);
        print('>>> Decoded ${audioBytes.length} bytes');
        
        // Write to file
        final tempFile = File('${tempDir.path}/voice_chunk_${DateTime.now().millisecondsSinceEpoch}.wav');
        await tempFile.writeAsBytes(audioBytes);
        
        final fileSize = await tempFile.length();
        print('>>> Wav file saved: ${tempFile.path} (Size: $fileSize bytes)');
        
        if (fileSize < 100) {
             print('>>> WARNING: File too small, skipping playback');
             continue;
        }
        
        print('>>> Playing voice chunk from: ${tempFile.path}');
        
        // Ensure volume is up
        await _voicePlayer.setVolume(1.0);
        
        if (!kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
          // Use mpv for desktop (more reliable)
          print('>>> Playing voice with mpv: ${tempFile.path}');
          final result = await Process.run('mpv', ['--no-video', '--volume=80', tempFile.path]);
          if (result.exitCode != 0) {
            print('>>> mpv error (${result.exitCode}): ${result.stderr}');
          } else {
             // print('>>> mpv success: ${result.stdout}');
          }
        } else {
          // Use audioplayers for mobile
          await _voicePlayer.play(DeviceFileSource(tempFile.path));
          
          // Wait for playback to complete (with timeout)
          await Future.any([
            _voicePlayer.onPlayerComplete.first,
            Future.delayed(const Duration(seconds: 10))
          ]);
        }
        
        print('>>> Audio chunk playback complete');
        
        // Small delay between chunks
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Clean up temp file
        try {
          await tempFile.delete();
        } catch (_) {}
        
      } catch (e) {
        print('>>> Voice playback error: $e');
      }
    }
    
    _isProcessingQueue = false;
    _isPlayingVoice = false;
    _currentVoiceSentence = null;
    notifyListeners();
  }

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
      final allMessages = await ChatService.getMessages(conversation.id);
      
      // Filter out tool execution results and system messages from UI
      _messages = allMessages.where((m) => m.role != 'tool' && m.role != 'system').toList();
      
      // Enrich messages with tool call markers for UI
      _enrichMessagesWithToolMarkers();

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

  /// Enrich messages with tool markers from toolCalls data (for history loading)
  void _enrichMessagesWithToolMarkers() {
    for (int i = 0; i < _messages.length; i++) {
        final msg = _messages[i];
        if (msg.role == 'assistant' && msg.toolCalls != null) {
           String thinking = msg.thinking ?? '';
           List<String> activeSearches = [];
           List<String> completedSearches = [];
           List<String> completedFileActions = [];
           
           // We need to append markers to 'thinking' if they are missing
           // But how do we know if they are missing?
           // The persisted 'thinking' might be raw text.
           // We'll append them at the end if not present?
           // Or better, we can reconstruct valid UI state.
           
           try {
             List<dynamic> calls = [];
             if (msg.toolCalls is String) {
                calls = jsonDecode(msg.toolCalls);
             } else if (msg.toolCalls is List) {
                calls = msg.toolCalls;
             }
             
             for (final call in calls) {
                if (call['function'] != null) {
                   final name = call['function']['name'];
                   final argsStr = call['function']['arguments'];
                   Map<String, dynamic> args = {};
                   if (argsStr is String) {
                      try { args = jsonDecode(argsStr); } catch (_) {}
                   } else if (argsStr is Map) {
                      args = argsStr as Map<String, dynamic>;
                   }
                   
                   String marker = '';
                   
                   if (name == 'web_search') {
                      final query = args['query'] as String?;
                      if (query != null) {
                         marker = '\n\n<<<TOOL:SEARCH:${query.replaceAll('>', '')}>>>\n\n';
                         completedSearches.add(query);
                      }
                   } else if (['read_file', 'create_file', 'search_file'].contains(name)) {
                      String action = '';
                      if (name == 'read_file') action = 'READ';
                      if (name == 'create_file') action = 'CREATE';
                      if (name == 'search_file') action = 'SEARCH_FILE';
                      
                      final path = args['path'] as String?;
                      final query = args['query'] as String?;
                      final target = path ?? query;
                      
                      if (target != null) {
                         marker = '\n\n<<<TOOL:$action:${target.replaceAll('>', '')}>>>\n\n';
                         completedFileActions.add('$action:$target');
                      }
                   }
                   
                   // Only append if not already in text (simple heuristic)
                   if (marker.isNotEmpty && !thinking.contains(marker.trim())) {
                      thinking += marker;
                   }
                }
             }
             
             _messages[i] = msg.copyWith(
                thinking: thinking,
                completedSearches: completedSearches,
                completedFileActions: completedFileActions,
             );
           } catch (e) {
             print('Error enriching message tool markers: $e');
           }
        }
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
  Future<void> sendMessage(
    String content, {
    String? file,
    void Function(String url, String title, String? thumbnail, int? duration)? onMusicPlay,
    bool? voiceEnabled,
  }) async {
    if (content.trim().isEmpty) return;

    // Auto-create conversation if none exists (e.g. from Welcome Screen or Voice)
    if (_currentConversation == null) {
      print('>>> Auto-creating conversation for new message...');
      await createConversation();
      if (_currentConversation == null) {
        print('>>> Failed to create conversation');
        return;
      }
    }
    
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
      
      // Clear voice audio chunks
      _voiceAudioChunks = [];
      
      // Use listen instead of await for to enable cancellation
      final stream = ChatService.sendMessage(
        _currentConversation!.id,
        content,
        file: file,
        voiceEnabled: voiceEnabled ?? _voiceModeEnabled,
        voiceId: _currentVoiceId,  // Use selected voice
      );

      final completer = Completer<void>();
      _processStream(stream, completer, onMusicPlay: onMusicPlay);
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

  /// Unified stream processor
  Future<void> _processStream(
    Stream<String> stream, 
    Completer<void> completer,
    {void Function(String url, String title, String? thumbnail, int? duration)? onMusicPlay}
  ) async {
    String fullResponse = '';
    
    // If the last message is assistant and already has content, start with that
    // (Crucial for Resuming tool result streams)
    if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
       fullResponse = _messages.last.content;
    }
    
    String fullThinking = (_messages.isNotEmpty && _messages.last.role == 'assistant') 
        ? (_messages.last.thinking ?? '') 
        : '';
        
    DateTime lastUpdate = DateTime.now();

    try {
      _streamSubscription = stream.listen(
      (chunk) {
        final line = chunk.trim();
        if (line.isEmpty) return;
        
        bool shouldNotify = false;
        String? jsonStr;
        if (line.startsWith('data: ')) {
           jsonStr = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
           jsonStr = line.substring(5).trim();
        }

        if (jsonStr != null) {
          if (jsonStr == '[DONE]') {
            print('>>> Stream [DONE] received');
            return;
          }

          try {
            final data = _parseJson(jsonStr);
            if (data == null) return;

            // Handle message_saved
            if (data['message_saved'] != null) {
              final messageId = data['message_saved']['id'] as int?;
              if (messageId != null) {
                final lastIndex = _messages.length - 1;
                if (lastIndex >= 0 && _messages[lastIndex].role == 'assistant') {
                  _messages[lastIndex] = _messages[lastIndex].copyWith(id: messageId);
                  shouldNotify = true;
                }
              }
            }

            // Handle client_tool_call
            if (data['client_tool_call'] != null) {
              final toolCall = data['client_tool_call'];
              _pendingClientTool = toolCall;
              _isStreaming = false;
              _streamSubscription?.cancel();
              _streamSubscription = null;
              final lastIndex = _messages.length - 1;
              if (lastIndex >= 0) {
                 _messages[lastIndex] = _messages[lastIndex].copyWith(isStreaming: false);
              }
              notifyListeners();
              if (!completer.isCompleted) completer.complete();
              return;
            }

            // Handle tool_calls
            if (data['tool_calls'] != null) {
              final toolCalls = data['tool_calls'] as List;
              for (final tc in toolCalls) {
                if (tc['function'] != null) {
                  final name = tc['function']['name'];
                  final args = tc['function']['arguments'];
                  String? pathOrQuery;
                  
                  // Safer generic args parsing
                  Map<String, dynamic>? parsedArgs;
                  if (args is Map) parsedArgs = args as Map<String, dynamic>;
                  else if (args is String) {
                    try { parsedArgs = _parseJson(args); } catch (_) {}
                  }

                  // Handle web_search
                  if (name == 'web_search') {
                      final query = parsedArgs?['query'] as String?;
                      if (query != null) {
                        final lastIndex = _messages.length - 1;
                        if (lastIndex >= 0) {
                          final currentSearches = List<String>.from(_messages[lastIndex].activeSearches);
                          if (!currentSearches.contains(query) && !_messages[lastIndex].completedSearches.contains(query)) {
                            currentSearches.add(query);
                            // Inject marker into THINKING, not content
                            fullThinking += '\n\n<<<TOOL:SEARCH:${query.replaceAll('>', '')}>>>\n\n';
                            
                            _messages[lastIndex] = _messages[lastIndex].copyWith(activeSearches: currentSearches, thinking: fullThinking);
                            shouldNotify = true;
                          }
                        }
                      }
                  } 
                  // Handle File Tools (Server Side)
                  else if (name == 'read_file' || name == 'create_file' || name == 'search_file') {
                      final path = parsedArgs?['path'] as String?;
                      final query = parsedArgs?['query'] as String?; // for search_file
                      final target = path ?? query;
                      
                      if (target != null) {
                         String action = '';
                         if (name == 'read_file') action = 'READ';
                         if (name == 'create_file') action = 'CREATE';
                         if (name == 'search_file') action = 'SEARCH_FILE';
                         
                         // Inject marker into THINKING
                         fullThinking += '\n\n<<<TOOL:$action:${target.replaceAll('>', '')}>>>\n\n';
                         
                         final lastIndex = _messages.length - 1;
                         if (lastIndex >= 0) {
                            _messages[lastIndex] = _messages[lastIndex].copyWith(thinking: fullThinking);
                            shouldNotify = true;
                         }
                      }
                  }
                }
              }
            }

            // Handle search_complete
            if (data['search_complete'] != null) {
              final query = data['search_complete']['query'] as String?;
              if (query != null) {
                final lastIndex = _messages.length - 1;
                if (lastIndex >= 0) {
                  final currentActive = List<String>.from(_messages[lastIndex].activeSearches);
                  final currentCompleted = List<String>.from(_messages[lastIndex].completedSearches);
                  if (currentActive.contains(query)) {
                    currentActive.remove(query);
                    if (!currentCompleted.contains(query)) currentCompleted.add(query);
                    _messages[lastIndex] = _messages[lastIndex].copyWith(activeSearches: currentActive, completedSearches: currentCompleted);
                    shouldNotify = true;
                  }
                }
              }
            }

            
            // Handle file_tool_complete
            if (data['file_tool_complete'] != null) {
              final tag = data['file_tool_complete']['tag'] as String?;
              if (tag != null) {
                 final lastIndex = _messages.length - 1;
                 if (lastIndex >= 0) {
                    final currentCompleted = List<String>.from(_messages[lastIndex].completedFileActions);
                    if (!currentCompleted.contains(tag)) {
                       currentCompleted.add(tag);
                       _messages[lastIndex] = _messages[lastIndex].copyWith(completedFileActions: currentCompleted);
                       shouldNotify = true;
                    }
                 }
              }
            }
            
            // Handle deep_search_update
            if (data['deep_search_update'] != null) {
               final message = data['deep_search_update']['message'] as String?;
               if (message != null) {
                 final lastIndex = _messages.length - 1;
                 if (lastIndex >= 0) {
                    final currentUpdates = List<String>.from(_messages[lastIndex].deepSearchUpdates);
                    if (currentUpdates.isEmpty || currentUpdates.last != message) {
                       currentUpdates.add(message);
                       _messages[lastIndex] = _messages[lastIndex].copyWith(deepSearchUpdates: currentUpdates);
                       shouldNotify = true;
                    }
                 }
               }
            }

            // Handle plan
            if (data['plan'] != null) {
              final lastIndex = _messages.length - 1;
              if (lastIndex >= 0) {
                _messages[lastIndex] = _messages[lastIndex].copyWith(plan: data['plan'] as String);
                shouldNotify = true;
              }
            }

            // Handle music_play
            if (data['music_play'] != null) {
              final musicData = data['music_play'];
              print('>>> ChatProvider received music_play: $musicData'); // DEBUG
              if (musicData['url'] != null) {
                // Use local callback if available, otherwise use strict passed callback
                if (onMusicPlay != null) {
                  print('>>> Executing local onMusicPlay callback'); // DEBUG
                  onMusicPlay(musicData['url'], musicData['title'] ?? 'Music', musicData['thumbnail'], musicData['duration']);
                } else if (_musicPlayCallback != null) {
                   print('>>> Executing global _musicPlayCallback'); // DEBUG
                   _musicPlayCallback!(musicData['url'], musicData['title'] ?? 'Music', musicData['thumbnail'], musicData['duration']);
                } else {
                   print('>>> NO CALLBACK REGISTERED for music_play'); // DEBUG
                }
              }
            }

            // Handle music_queue_add
            if (data['music_queue_add'] != null) {
              final queueItem = data['music_queue_add']['item'];
              if (queueItem != null && _musicQueueAddCallback != null) {
                _musicQueueAddCallback!(Map<String, dynamic>.from(queueItem));
              }
            }

            // Handle music_control
            if (data['music_control'] != null) {
               final action = data['music_control']['action'] as String?;
               if (action != null && _musicControlCallback != null) {
                 _musicControlCallback!(action);
               }
            }

            // Handle thinking
            if (data['thinking'] != null) {
              fullThinking += data['thinking'] as String;
              final lastIndex = _messages.length - 1;
              if (lastIndex >= 0) {
                _messages[lastIndex] = _messages[lastIndex].copyWith(thinking: fullThinking);
                shouldNotify = true;
              }
            }

            // Handle message content
            if (data['message'] != null) {
              final contentDelta = data['message']['content'] as String? ?? '';
              final thinkingDelta = data['message']['thinking'] as String? ?? '';
              if (contentDelta.isNotEmpty) fullResponse += contentDelta;
              if (thinkingDelta.isNotEmpty) fullThinking += thinkingDelta;
              
              final now = DateTime.now();
              if (now.difference(lastUpdate).inMilliseconds > 100) {
                final lastIndex = _messages.length - 1;
                if (lastIndex >= 0) {
                   _messages[lastIndex] = _messages[lastIndex].copyWith(content: fullResponse, thinking: fullThinking.isNotEmpty ? fullThinking : null);
                   lastUpdate = now;
                   shouldNotify = true;
                }
              }
            }
            
            if (data['error'] != null) {
              fullResponse += '\n\nError: ${data['error']}';
              shouldNotify = true;
            }

            // Handle voice_audio
            if (data.containsKey('voice_audio')) {
              final voiceData = data['voice_audio'] as Map<String, dynamic>;
              _voiceAudioChunks.add(voiceData);
              shouldNotify = true;
              final audioBase64 = voiceData['audio'] as String?;
              if (audioBase64 != null) {
                _queueAudioChunk(audioBase64, voiceData['sentence'] as String?);
              }
            }
          } catch (e) { print('JSON parse error: $e'); }
        }
        if (shouldNotify) notifyListeners();
      },
      onError: (e) {
        _error = e.toString();
        final lastIndex = _messages.length - 1;
        if (lastIndex >= 0) {
          _messages[lastIndex] = _messages[lastIndex].copyWith(content: 'Error: ${e.toString()}', isStreaming: false);
        }
        notifyListeners();
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () async {
        final lastIndex = _messages.length - 1;
        if (lastIndex >= 0) {
           _messages[lastIndex] = _messages[lastIndex].copyWith(content: fullResponse.isEmpty ? '...' : fullResponse, isStreaming: false);
        }
        notifyListeners();
        _maybeGenerateTitle();
        if (!completer.isCompleted) completer.complete();
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
    // print('>>> _maybeGenerateTitle called. msgs: ${_messages.length}, title: ${_currentConversation?.title}, isNaming: $_isNamingInProgress');
    
    // Skip if already naming or no conversation
    if (_isNamingInProgress) return;
    if (_currentConversation == null) return;
    
    // Skip if already has a title
    if (_currentConversation!.title != null && _currentConversation!.title!.isNotEmpty) {
      // print('>>> Skipped: Has title: ${_currentConversation!.title}');
      return;
    }
    
    // Need at least 1 message (the user query)
    if (_messages.length < 1) {
      // print('>>> Skipped: Not enough messages');
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
    } catch (e) {
      // Only log if it looks like voice_audio (very long)
      if (jsonStr.length > 1000) {
        print('>>> JSON parse error for long string (${jsonStr.length} chars): $e');
      }
    }
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

  /// Execute the currently pending client tool
  Future<void> executePendingTool() async {
    if (_pendingClientTool == null) return;
    
    final tool = _pendingClientTool!;
    final name = tool['name'] as String;
    final args = tool['args'] as Map<String, dynamic>;
    final toolCallId = tool['tool_call_id'] as String?;
    
    print('>>> Executing client tool: $name');
    
    String result = '';
    try {
      if (name == 'client_read_file') {
        // Add a marker to show we are reading
        final lastIndex = _messages.length - 1;
        if (lastIndex >= 0) {
           String currentContent = _messages[lastIndex].content;
           _messages[lastIndex] = _messages[lastIndex].copyWith(
             content: '$currentContent\n\n![FILE_ACTION](file:read:${Uri.encodeComponent(args['path'] ?? '')})\n\n',
           );
           notifyListeners();
        }
        result = await FileToolService.readFile(args['path']);
      } else if (name == 'client_search_file') {
        final lastIndex = _messages.length - 1;
        if (lastIndex >= 0) {
           String currentContent = _messages[lastIndex].content;
           _messages[lastIndex] = _messages[lastIndex].copyWith(
             content: '$currentContent\n\n![FILE_ACTION](file:search:${Uri.encodeComponent(args['query'] ?? '')})\n\n',
           );
           notifyListeners();
        }
        final rawResults = await FileToolService.searchFiles(
          args['query'], 
          directory: args['directory']
        );
        result = jsonEncode({'results': rawResults});
      } else if (name == 'client_create_file') {
        final lastIndex = _messages.length - 1;
        if (lastIndex >= 0) {
           String currentContent = _messages[lastIndex].content;
           _messages[lastIndex] = _messages[lastIndex].copyWith(
             content: '$currentContent\n\n![FILE_ACTION](file:create:${Uri.encodeComponent(args['path'] ?? '')})\n\n',
           );
           notifyListeners();
        }
        result = await FileToolService.createFile(args['path'], args['content']);
      } else {
        result = 'Error: Unknown client tool $name';
      }
    } catch (e) {
      result = 'Error executing tool: $e';
    }
    
    // Clear pending and submit
    _pendingClientTool = null;
    notifyListeners();
    
    await submitToolResult(name, result, toolCallId);
  }

  /// Submit tool result back to server to resume streaming
  Future<void> submitToolResult(String name, String result, String? toolCallId) async {
    if (_currentConversation == null) return;
    
    _isStreaming = true;
    notifyListeners();
    
    try {
      final stream = ChatService.submitToolResult(
        _currentConversation!.id,
        name,
        result,
        toolCallId: toolCallId,
        voiceEnabled: _voiceModeEnabled,
        voiceId: _currentVoiceId,
      );
      
      final completer = Completer<void>();
      _processStream(stream, completer);
      await completer.future;

    } catch (e) {
      _error = 'Error submitting tool result: $e';
      _isStreaming = false;
      notifyListeners();
    }
  }
}
