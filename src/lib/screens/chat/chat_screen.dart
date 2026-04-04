import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/music_player_provider.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/message_input.dart';
import '../../widgets/voice/voice_agent_overlay.dart';
import '../../providers/canvas_provider.dart';
import '../../widgets/canvas/canvas_panel.dart';
import '../../providers/settings_provider.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();
  bool _autoScrollEnabled = true;
  bool _isProgrammaticScroll = false;
  bool _scrollPending = false;
  String? _selectedTool;

  late ChatProvider _chatProvider;
  late CanvasProvider _canvasProvider;

  @override
  void initState() {
    super.initState();
    _chatProvider = context.read<ChatProvider>();
    _canvasProvider = context.read<CanvasProvider>();
    _scrollController.addListener(_onScroll);
    // Load conversations when screen is first displayed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chatProvider.loadConversations();

      // Set music callback for voice mode and tool actions
      final musicPlayer = context.read<MusicPlayerProvider>();
      context.read<ChatProvider>().setMusicCallbacks(
        onPlay: (url, title, thumbnail, duration) {
          musicPlayer.playFromUrl(
            url: url,
            title: title,
            thumbnail: thumbnail,
            duration: duration,
          );
        },
        onQueueAdd: (item) {
          musicPlayer.addToQueue(
            url: item['url'],
            title: item['title'],
            thumbnail: item['thumbnail'],
            duration: item['duration'],
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Đã thêm vào danh sách phát: ${item['title']}'),
                behavior: SnackBarBehavior.floating,
                width: 400,
              ),
            );
          }
        },
        onControl: (action) {
          musicPlayer.handleControl(action);
        },
      );
    });

    // Add listener for pending tool calls
    _chatProvider.addListener(_handleProviderUpdate);
    // Add listener for canvas updates
    _canvasProvider.addListener(_handleCanvasUpdate);

    // Register callback for socket events
    _chatProvider.setOnCanvasUpdate((canvasId) {
      if (mounted) {
        print('>>> ChatScreen: Received canvas update $canvasId');
        print('DEBUG: Init with canvasId=$canvasId');
        final canvasProvider = context.read<CanvasProvider>();

        // Open panel immediately (via Settings)
        context.read<SettingsProvider>().setShowCanvas(true);

        if (canvasId > 0) {
          // Real canvas ID - fetch and select
          canvasProvider.fetchAndSelectCanvas(canvasId);
        } else {
          // Pending canvas (canvasId=0) - set loading state
          canvasProvider.setPendingCanvas(true);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _chatProvider.removeListener(_handleProviderUpdate);
    _canvasProvider.removeListener(_handleCanvasUpdate);
    super.dispose();
  }

  void _handleCanvasUpdate() {
    if (!mounted) return;
    final canvasProvider = context.read<CanvasProvider>();
    final settingsProvider = context.read<SettingsProvider>();

    // Auto-open panel if a canvas is selected and panel is closed
    if (canvasProvider.currentCanvas != null && !settingsProvider.showCanvas) {
      settingsProvider.setShowCanvas(true);
    }
  }

  void _handleProviderUpdate() {
    if (!mounted) return;
    final chatProvider = context.read<ChatProvider>();

    // Handle pending client tool calls
    if (chatProvider.pendingClientTool != null) {
      _showToolPermissionDialog(context, chatProvider);
    }
  }

  /// Scroll listener — only tracks USER scrolling, ignores programmatic jumps.
  void _onScroll() {
    if (!_scrollController.hasClients || _isProgrammaticScroll) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    const threshold = 150.0;

    final isNearBottom = (maxScroll - currentScroll) <= threshold;

    if (isNearBottom && !_autoScrollEnabled) {
      // User scrolled back to bottom → re-enable auto-scroll
      _autoScrollEnabled = true;
    } else if (!isNearBottom && _autoScrollEnabled) {
      // User scrolled away from bottom → disable auto-scroll
      _autoScrollEnabled = false;
    }
  }

  /// Scroll to bottom with debouncing to prevent multiple calls per frame.
  /// During streaming: uses jumpTo for instant, jitter-free updates.
  /// After streaming: uses animateTo for smooth animation.
  void _scrollToBottom({bool isStreaming = false}) {
    if (!mounted || !_autoScrollEnabled) return;
    if (_scrollPending) return; // Already scheduled for this frame
    _scrollPending = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollPending = false;
      if (!mounted || !_scrollController.hasClients) return;
      if (!_autoScrollEnabled) return;

      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;

      // Nothing to scroll if already at bottom
      if ((maxScroll - currentScroll).abs() < 1.0) return;

      _isProgrammaticScroll = true;

      if (isStreaming) {
        // Instant jump during streaming — no animation = no jitter
        _scrollController.jumpTo(maxScroll);
        _isProgrammaticScroll = false;
      } else {
        // Smooth animation for non-streaming updates
        _scrollController
            .animateTo(
              maxScroll,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
            )
            .then((_) => _isProgrammaticScroll = false)
            .catchError((_) => _isProgrammaticScroll = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Remove top-level Consumer to prevent whole screen rebuild on every tick
    // Individual parts will listen to provider as needed
    return Column(
      children: [
        // Header - always full width above canvas
        _buildChatHeader(context, theme),
        // Chat + Canvas row below header
        Expanded(
          child: Consumer<CanvasProvider>(
            builder: (context, canvasProvider, _) {
              final showCanvas = context.watch<SettingsProvider>().showCanvas;
              if (showCanvas) {
                print(
                  'DEBUG: Canvas Panel is ON. Current Canvas: ${canvasProvider.currentCanvas?.id}',
                );
              }

              return Row(
                children: [
                  // Chat messages area
                  Expanded(
                    flex: showCanvas ? 2 : 1,
                    child: _buildChatContent(context, theme),
                  ),
                  // Canvas Panel (List or Content)
                  if (showCanvas) const Expanded(flex: 3, child: CanvasPanel()),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // Chat header - always full width above canvas
  Widget _buildChatHeader(BuildContext context, ThemeData theme) {
    return Selector<ChatProvider, (String?, int?)>(
      selector: (_, provider) => (
        provider.currentConversation?.title,
        provider.currentConversation?.id,
      ),
      builder: (context, data, _) {
        final title = data.$1;
        final conversationId = data.$2;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor.withOpacity(0.2)),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    if (conversationId == null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: Image.asset('assets/icon/icon.png'),
                        ),
                      ),
                    Flexible(
                      child: Text(
                        title ?? 'Lumina AI',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // Canvas toggle moved to Settings

              // More options
              if (conversationId != null)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') {
                      _showDeleteDialog(context, context.read<ChatProvider>());
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Xóa cuộc trò chuyện'),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  // Chat content area (messages + input) - no header
  Widget _buildChatContent(BuildContext context, ThemeData theme) {
    return _buildChatArea(context, theme);
  }

  Widget _buildChatArea(BuildContext context, ThemeData theme) {
    // Use Selector to only listen to specific state changes, not every stream chunk
    return Selector<ChatProvider, _ChatAreaState>(
      selector: (_, provider) => _ChatAreaState(
        hasConversation: provider.currentConversation != null,
        messageCount: provider.messages.length,
        isStreaming: provider.isStreaming,
        voiceModeEnabled: provider.voiceModeEnabled,
        lastMessageContent: provider.messages.isNotEmpty
            ? provider.messages.last.content.length
            : 0,
      ),
      shouldRebuild: (prev, next) => prev != next,
      builder: (context, state, _) {
        final chatProvider = context.read<ChatProvider>();

        // Trigger scroll after frame — debounced by _scrollToBottom itself
        if (state.messageCount > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (state.isStreaming) {
              _scrollToBottom(isStreaming: true);
            } else {
              _scrollToBottom(isStreaming: false);
            }
          });
        }

        return PopScope(
          canPop: !chatProvider.voiceModeEnabled,
          onPopInvoked: (didPop) {
            if (didPop) return;
            if (chatProvider.voiceModeEnabled) {
              chatProvider.setVoiceMode(false);
            }
          },
          child: Stack(
            children: [
              // Voice Agent Overlay (covers everything when voice mode active)
              // Voice Agent Overlay (covers everything when voice mode active)
              if (chatProvider.voiceModeEnabled)
                Positioned.fill(
                  child: VoiceAgentOverlay(
                    isActive: true,
                    isPlaying: chatProvider.isPlayingVoice,
                    isProcessing: chatProvider.isVoiceProcessing,
                    isRecording: chatProvider.isRecording,
                    currentSentence: chatProvider.currentVoiceSentence,
                    currentVoice: chatProvider.currentVoiceId,
                    onClose: () => chatProvider.setVoiceMode(false),
                    onMicPressed: () => chatProvider.startRecording(),
                    onMicReleased: () => chatProvider.stopRecording(),
                    onVoiceSwitch: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (ctx) {
                          final theme = Theme.of(context);
                          final isDark = theme.brightness == Brightness.dark;

                          return Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E1E2C)
                                  : Colors.white,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(20),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    'Chọn giọng đọc',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                ),
                                const Divider(height: 1),
                                Flexible(
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    itemCount:
                                        chatProvider.availableVoices.length,
                                    itemBuilder: (context, index) {
                                      final voice =
                                          chatProvider.availableVoices[index];
                                      final isSelected =
                                          voice == chatProvider.currentVoiceId;

                                      return ListTile(
                                        leading: Icon(
                                          Icons.record_voice_over,
                                          color: isSelected
                                              ? theme.colorScheme.primary
                                              : null,
                                        ),
                                        title: Text(
                                          voice,
                                          style: TextStyle(
                                            color: isSelected
                                                ? theme.colorScheme.primary
                                                : null,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                        trailing: isSelected
                                            ? Icon(
                                                Icons.check_circle,
                                                color:
                                                    theme.colorScheme.primary,
                                              )
                                            : null,
                                        onTap: () {
                                          chatProvider.setVoice(voice);
                                          Navigator.pop(ctx);
                                        },
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

              // Normal chat UI (hidden when voice overlay active)
              if (!chatProvider.voiceModeEnabled) ...[
                if (chatProvider.currentConversation != null &&
                    chatProvider.messages.isNotEmpty)
                  Positioned.fill(
                    bottom: 120, // Space for input
                    child: Selector<ChatProvider, (int, bool)>(
                      // Only rebuild when message count or streaming state changes
                      selector: (_, provider) =>
                          (provider.messages.length, provider.isStreaming),
                      builder: (context, data, _) {
                        final messageCount = data.$1;
                        final isStreaming = data.$2;

                        return ListView.builder(
                          controller: _scrollController,
                          reverse: false, // Start from top
                          // Use fixed generous bottom padding to avoid layout jumps when streaming toggles
                          padding: const EdgeInsets.only(
                            top: 16,
                            bottom: 120,
                            left: 24,
                            right: 24,
                          ),
                          itemCount: messageCount,
                          itemBuilder: (context, index) {
                            // Use Selector for individual message to minimize rebuilds
                            return Selector<ChatProvider, _MessageSnapshot>(
                              selector: (_, provider) {
                                final msg = provider.messages[index];
                                return _MessageSnapshot(
                                  id: msg.id,
                                  content: msg.content,
                                  thinking: msg.thinking,
                                  plan: msg.plan,
                                  deepSearchLength:
                                      msg.deepSearchUpdates.length,
                                  codeExecLength: msg.codeExecutions.length,
                                  isStreaming: msg.isStreaming,
                                  isGeneratingImage: msg.isGeneratingImage,
                                  generatedImages: msg.generatedImages.length,
                                );
                              },
                              shouldRebuild: (prev, next) => prev != next,
                              builder: (context, snapshot, _) {
                                final messages = context
                                    .read<ChatProvider>()
                                    .messages;
                                if (index >= messages.length)
                                  return const SizedBox.shrink();
                                return MessageBubble(
                                  key: ValueKey('msg_${snapshot.id ?? index}'),
                                  message: messages[index],
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),

                // 2. Welcome/Suggestions Layer (Visible only when empty)
                if (chatProvider.currentConversation == null ||
                    chatProvider.messages.isEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    // Input is at Alignment(0, 0.4), approx 70% down.
                    // Make bottom aligned just above the input.
                    bottom: MediaQuery.of(context).size.height * 0.3 + 80,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _buildWelcomeView(theme),
                          ),
                        ),
                      ),
                    ),
                  ),

                // 3. Input Layer
                AnimatedAlign(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  alignment:
                      (chatProvider.currentConversation == null ||
                          chatProvider.messages.isEmpty)
                      ? const Alignment(0, 0.4)
                      : Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: MessageInput(
                        voiceModeEnabled: chatProvider.voiceModeEnabled,
                        onVoiceModeChanged: (enabled) =>
                            chatProvider.setVoiceMode(enabled),
                        selectedTool: _selectedTool,
                        onToolSelected: (tool) =>
                            setState(() => _selectedTool = tool),
                        onSend: (message) async {
                          // Auto-create conversation if none exists
                          if (chatProvider.currentConversation == null) {
                            await chatProvider.createConversation();
                          }
                          if (!mounted) return;

                          final musicPlayer = context
                              .read<MusicPlayerProvider>();
                          String messageToSend = message;
                          if (_selectedTool == 'image') {
                            messageToSend += ' (Dùng công cụ tạo hình ảnh)';
                          } else if (_selectedTool == 'deep_research') {
                            messageToSend += ' (Dùng công cụ deep research)';
                          }

                          chatProvider.sendMessage(
                            messageToSend, // Send message with tool cues
                            displayContent: message,
                            onMusicPlay: (url, title, thumbnail, duration) {
                              musicPlayer.playFromUrl(
                                url: url,
                                title: title,
                                thumbnail: thumbnail,
                                duration: duration,
                              );
                            },
                            forceTool: _selectedTool,
                          );

                          // Clear selected tool after send if desired. But typically keep it or clear it. We will clear it.
                          // setState(() {
                          //   _selectedTool = null;
                          // });
                          _autoScrollEnabled = true;
                          _scrollToBottom(isStreaming: false);
                        },
                        onSendWithFile: (message, file) async {
                          // Auto-create conversation if none exists
                          if (chatProvider.currentConversation == null) {
                            await chatProvider.createConversation();
                          }
                          if (!mounted) return;

                          final musicPlayer = context
                              .read<MusicPlayerProvider>();

                          // Append cues
                          String messageToSend = message;
                          if (_selectedTool == 'image') {
                            messageToSend += ' (Vui lòng tạo hình ảnh)';
                          } else if (_selectedTool == 'deep_research') {
                            messageToSend +=
                                ' (Vui lòng dùng công cụ deep research)';
                          } else if (_selectedTool == 'canvas') {
                            messageToSend += ' dùng canvas';
                          }

                          chatProvider.sendMessage(
                            messageToSend,
                            displayContent:
                                message, // Show original message to user
                            file: file,
                            onMusicPlay: (url, title, thumbnail, duration) {
                              musicPlayer.playFromUrl(
                                url: url,
                                title: title,
                                thumbnail: thumbnail,
                                duration: duration,
                              );
                            },
                            forceTool: _selectedTool,
                          );

                          // Scroll to bottom after user sends
                          // setState(() {
                          //   _selectedTool = null;
                          // });
                          _autoScrollEnabled = true;
                          _scrollToBottom(isStreaming: false);
                        },
                        isLoading: chatProvider.isStreaming,
                        onStop: () => chatProvider.stopStreaming(),
                        onMusicTap: () {
                          final musicPlayer = context
                              .read<MusicPlayerProvider>();
                          if (musicPlayer.isVisible) {
                            musicPlayer.hide();
                          } else {
                            musicPlayer.show();
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ], // End of spread operator for normal chat UI
            ],
          ),
        );
      },
    );
  }

  Widget _buildWelcomeView(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Xin chào!',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: 12),
          Text(
            'Chúng ta nên bắt đầu từ đâu nhỉ?',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.8),
            ),
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildEmptyChat(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: theme.colorScheme.onSurface.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'Bắt đầu cuộc trò chuyện',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(String text, IconData icon, ThemeData theme) {
    final chatProvider = context.read<ChatProvider>();
    final musicPlayer = context.read<MusicPlayerProvider>();

    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(text),
      onPressed: () async {
        if (chatProvider.currentConversation == null) {
          await chatProvider.createConversation();
        }
        chatProvider.sendMessage(
          text,
          onMusicPlay: (url, title, thumbnail, duration) {
            musicPlayer.playFromUrl(
              url: url,
              title: title,
              thumbnail: thumbnail,
              duration: duration,
            );
          },
        );
      },
    );
  }

  void _showDeleteDialog(BuildContext context, ChatProvider chatProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa cuộc trò chuyện?'),
        content: const Text(
          'Bạn có chắc muốn xóa cuộc trò chuyện này? Hành động này không thể hoàn tác.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              chatProvider.deleteConversation(
                chatProvider.currentConversation!.id,
              );
              Navigator.pop(context);
            },
            child: Text(
              'Xóa',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  bool _isToolDialogShowing = false;

  void _showToolPermissionDialog(
    BuildContext context,
    ChatProvider chatProvider,
  ) {
    if (_isToolDialogShowing) return;
    _isToolDialogShowing = true;

    final tool = chatProvider.pendingClientTool!;
    final name = tool['name'] as String;
    final args = tool['args'] as Map<String, dynamic>;

    String actionDesc = '';
    IconData icon = Icons.security;

    if (name == 'client_read_file') {
      actionDesc = 'đọc tệp tin: ${args['path']}';
      icon = Icons.file_open_outlined;
    } else if (name == 'client_search_file') {
      actionDesc = 'tìm kiếm tệp tin với từ khóa "${args['query']}"';
      icon = Icons.search;
    } else if (name == 'client_create_file') {
      actionDesc = 'tạo tệp tin mới tại: ${args['path']}';
      icon = Icons.create_new_folder_outlined;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: Colors.blue),
            const SizedBox(width: 10),
            const Text('Yêu cầu quyền hạn'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI đang yêu cầu thực hiện hành động sau trên thiết bị của bạn:',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                actionDesc,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Bạn có cho phép thực hiện hành động này không?',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _isToolDialogShowing = false;
              Navigator.pop(context);
              chatProvider.submitToolResult(
                name,
                'Error: Quyền bị từ chối bởi người dùng.',
                tool['tool_call_id'],
              );
              chatProvider.clearPendingTool();
            },
            child: const Text('Từ chối'),
          ),
          ElevatedButton(
            onPressed: () {
              _isToolDialogShowing = false;
              Navigator.pop(context);
              chatProvider.executePendingTool();
            },
            child: const Text('Cho phép'),
          ),
        ],
      ),
    );
  }
}

/// Lightweight snapshot class for efficient Selector comparison
/// This avoids rebuilding MessageBubble when irrelevant fields change
class _MessageSnapshot {
  final int? id;
  final String content;
  final String? thinking;
  final String? plan;
  final int deepSearchLength;
  final int codeExecLength;
  final bool isStreaming;
  final bool isGeneratingImage;
  final int generatedImages;

  const _MessageSnapshot({
    required this.id,
    required this.content,
    required this.thinking,
    required this.plan,
    required this.deepSearchLength,
    required this.codeExecLength,
    required this.isStreaming,
    required this.isGeneratingImage,
    required this.generatedImages,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _MessageSnapshot &&
        other.id == id &&
        other.content == content &&
        other.thinking == thinking &&
        other.plan == plan &&
        other.deepSearchLength == deepSearchLength &&
        other.codeExecLength == codeExecLength &&
        other.isStreaming == isStreaming &&
        other.isGeneratingImage == isGeneratingImage &&
        other.generatedImages == generatedImages;
  }

  @override
  int get hashCode => Object.hash(
    id,
    content,
    thinking,
    plan,
    deepSearchLength,
    codeExecLength,
    isStreaming,
    isGeneratingImage,
    generatedImages,
  );
}

/// Lightweight snapshot class for chat area Selector
class _ChatAreaState {
  final bool hasConversation;
  final int messageCount;
  final bool isStreaming;
  final bool voiceModeEnabled;
  final int lastMessageContent;

  const _ChatAreaState({
    required this.hasConversation,
    required this.messageCount,
    required this.isStreaming,
    required this.voiceModeEnabled,
    required this.lastMessageContent,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _ChatAreaState &&
        other.hasConversation == hasConversation &&
        other.messageCount == messageCount &&
        other.isStreaming == isStreaming &&
        other.voiceModeEnabled == voiceModeEnabled &&
        other.lastMessageContent == lastMessageContent;
  }

  @override
  int get hashCode => Object.hash(
    hasConversation,
    messageCount,
    isStreaming,
    voiceModeEnabled,
    lastMessageContent,
  );
}
