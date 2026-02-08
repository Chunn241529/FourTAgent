import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/music_player_provider.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/message_input.dart';
import '../../widgets/settings/settings_dialog.dart';
import '../../widgets/voice/voice_agent_overlay.dart';
import '../../providers/canvas_provider.dart';
import '../../widgets/canvas/canvas_panel.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();
  bool _isUserScrolling = false;
  bool _isNearBottom = true;
  bool _showCanvasPanel = false;
  bool _forceCanvasTool = false; // Forces LLM to use canvas tool
  bool _sidebarCollapsed = false; // Sidebar collapse state

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Load conversations when screen is first displayed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadConversations();
      
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
    context.read<ChatProvider>().addListener(_handleProviderUpdate);
    // Add listener for canvas updates
    context.read<CanvasProvider>().addListener(_handleCanvasUpdate);
    
    // Register callback for socket events
    context.read<ChatProvider>().setOnCanvasUpdate((canvasId) {
       if (mounted) {
         print('>>> ChatScreen: Received canvas update $canvasId');
         // Open panel immediately
         setState(() {
           _showCanvasPanel = true;
         });
         // Only fetch and select if this is a real canvas ID (not a placeholder)
         if (canvasId > 0) {
           context.read<CanvasProvider>().fetchAndSelectCanvas(canvasId);
         }
       }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    context.read<ChatProvider>().removeListener(_handleProviderUpdate);
    context.read<CanvasProvider>().removeListener(_handleCanvasUpdate);
    super.dispose();
  }

  void _handleCanvasUpdate() {
    if (!mounted) return;
    final canvasProvider = context.read<CanvasProvider>();
    // Auto-open panel if a canvas is selected and panel is closed
    if (canvasProvider.currentCanvas != null && !_showCanvasPanel) {
      setState(() {
        _showCanvasPanel = true;
      });
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

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    final threshold = 100.0; // Distance from bottom to consider "near bottom"
    
    final wasNearBottom = _isNearBottom;
    _isNearBottom = (maxScroll - currentScroll) <= threshold;
    
    // If user scrolled away from bottom, mark as user scrolling
    if (wasNearBottom && !_isNearBottom) {
      _isUserScrolling = true;
    }
    
    // If user scrolled back to bottom, re-enable auto-scroll
    if (!wasNearBottom && _isNearBottom) {
      _isUserScrolling = false;
    }
  }

  void _scrollToBottom({bool isStreaming = false}) {
    // Only auto-scroll if user hasn't scrolled up (and isn't at the very bottom)
    if (_isUserScrolling) return;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        
        if (isStreaming) {
           // For streaming, jump to bottom to keep up with the spinner instantly
           // and avoid animation lag/jank
           if (_scrollController.position.pixels < maxScroll) {
             _scrollController.jumpTo(maxScroll);
           }
        } else {
          // For new messages (not streaming), animate smoothly
          _scrollController.animateTo(
            maxScroll,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Use Consumer to scope provider access - the build method still rebuilds,
    // but individual children can use Selector for fine-grained control
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        // Scroll to bottom when streaming - debounced via postFrameCallback
        // This prevents layout during build phase
        if (chatProvider.messages.isNotEmpty && chatProvider.isStreaming) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom(isStreaming: true);
          });
        }

        return Row(
          children: [
            // Left sidebar - Collapsible conversation list
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _sidebarCollapsed ? 60 : 280,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: _sidebarCollapsed 
                  ? _buildCollapsedSidebar(context, theme, chatProvider)
                  : _buildConversationSidebar(context, theme, chatProvider),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            // Main content area
            Expanded(
              child: Consumer<CanvasProvider>(
                builder: (context, canvasProvider, _) {
                  final showCanvas = _showCanvasPanel;
                  if (showCanvas) {
                     print('DEBUG: Canvas Panel is ON. Current Canvas: ${canvasProvider.currentCanvas?.id}');
                  }
                  
                  return Column(
                    children: [
                      // Header - always full width above canvas
                      _buildChatHeader(context, theme, chatProvider),
                      // Chat + Canvas row below header
                      Expanded(
                        child: Row(
                          children: [
                            // Chat messages area
                            Expanded(
                              flex: showCanvas ? 2 : 1,
                              child: _buildChatContent(context, theme, chatProvider),
                            ),
                            // Canvas Panel (List or Content)
                            if (showCanvas)
                              const Expanded(
                                flex: 3,
                                child: CanvasPanel(),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConversationSidebar(BuildContext context, ThemeData theme, ChatProvider chatProvider) {
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final hoverColor = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
    final selectedColor = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06);
    
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 12,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header - subtle with no harsh borders
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF10B981), // Emerald green
                        const Color(0xFF059669),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Lumina AI',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                Container(
                  decoration: BoxDecoration(
                    color: hoverColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                    iconSize: 20,
                    onPressed: () {
                      final themeProvider = context.read<ThemeProvider>();
                      themeProvider.toggleTheme();
                    },
                  ),
                ),
              ],
            ),
          ),
          // New chat button - modern gradient style
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF10B981),
                      const Color(0xFF059669),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      await chatProvider.createConversation();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.add, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Cuộc trò chuyện mới',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Conversation list - clean and modern
          Expanded(
            child: chatProvider.conversations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: hoverColor,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.chat_bubble_outline, size: 28, color: theme.disabledColor),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Chưa có cuộc trò chuyện nào',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.disabledColor),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: chatProvider.conversations.length,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemBuilder: (context, index) {
                      final conversation = chatProvider.conversations[index];
                      final isSelected = chatProvider.currentConversation?.id == conversation.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => chatProvider.selectConversation(conversation),
                            hoverColor: hoverColor,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: isSelected ? selectedColor : Colors.transparent,
                                border: isSelected 
                                    ? Border.all(color: theme.dividerColor.withOpacity(0.5), width: 1)
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: isSelected 
                                          ? const Color(0xFF10B981).withOpacity(0.15)
                                          : hoverColor,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.chat_bubble_outline,
                                      size: 16,
                                      color: isSelected 
                                          ? const Color(0xFF10B981)
                                          : theme.iconTheme.color?.withOpacity(0.6),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      conversation.title ?? 'Cuộc trò chuyện',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                        color: isSelected 
                                            ? theme.textTheme.bodyLarge?.color
                                            : theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildBottomAction(IconData icon, String label, Color hoverColor, VoidCallback onTap, {bool isDestructive = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          hoverColor: hoverColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon, 
                  size: 20, 
                  color: isDestructive ? Colors.red.shade400 : null,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDestructive ? Colors.red.shade400 : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Collapsed sidebar - only icons
  Widget _buildCollapsedSidebar(BuildContext context, ThemeData theme, ChatProvider chatProvider) {
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Expand button
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Mở rộng',
            onPressed: () => setState(() => _sidebarCollapsed = false),
          ),
          const SizedBox(height: 8),
          // New conversation
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Cuộc trò chuyện mới',
            onPressed: () => chatProvider.createConversation(),
          ),
          const Spacer(),
          // Settings
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Cài đặt',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const SettingsDialog(),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // Chat header - always full width above canvas
  Widget _buildChatHeader(BuildContext context, ThemeData theme, ChatProvider chatProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          // Toggle sidebar (only show when expanded, collapsed sidebar has its own toggle)
          if (!_sidebarCollapsed)
            IconButton(
              icon: const Icon(Icons.menu_open),
              tooltip: 'Thu gọn sidebar',
              onPressed: () => setState(() => _sidebarCollapsed = true),
            ),
          const SizedBox(width: 8),
          // Title with animation
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                chatProvider.currentConversation?.title ?? 'Lumina AI',
                key: ValueKey<String>(chatProvider.currentConversation?.title ?? 'default'),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Canvas toggle in header
          IconButton(
            icon: Icon(
              Icons.article_outlined,
              color: _showCanvasPanel ? theme.colorScheme.primary : null,
            ),
            tooltip: 'Canvas',
            onPressed: () => setState(() => _showCanvasPanel = !_showCanvasPanel),
          ),
          // More options
          if (chatProvider.currentConversation != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') {
                  _showDeleteDialog(context, chatProvider);
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
  }

  // Chat content area (messages + input) - no header
  Widget _buildChatContent(BuildContext context, ThemeData theme, ChatProvider chatProvider) {
    return _buildChatArea(context, theme, chatProvider);
  }

  Widget _buildChatArea(BuildContext context, ThemeData theme, ChatProvider chatProvider) {
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
                          color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                                itemCount: chatProvider.availableVoices.length,
                                itemBuilder: (context, index) {
                                  final voice = chatProvider.availableVoices[index];
                                  final isSelected = voice == chatProvider.currentVoiceId;
                                  
                                  return ListTile(
                                    leading: Icon(
                                      Icons.record_voice_over,
                                      color: isSelected ? theme.colorScheme.primary : null,
                                    ),
                                    title: Text(
                                      voice,
                                      style: TextStyle(
                                        color: isSelected ? theme.colorScheme.primary : null,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    trailing: isSelected 
                                        ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
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
          if (chatProvider.currentConversation != null && chatProvider.messages.isNotEmpty)
            Positioned.fill(
              bottom: 120, // Space for input
              child: Selector<ChatProvider, int>(
                // Only rebuild when message count changes (not on every stream update)
                selector: (_, provider) => provider.messages.length,
                builder: (context, messageCount, _) {
                  return ListView.builder(
                    controller: _scrollController,
                    reverse: false, // Start from top
                    padding: const EdgeInsets.only(top: 16, bottom: 24, left: 24, right: 24),
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
                            isStreaming: msg.isStreaming,
                            isGeneratingImage: msg.isGeneratingImage,
                            generatedImages: msg.generatedImages.length,
                          );
                        },
                        shouldRebuild: (prev, next) => prev != next,
                        builder: (context, snapshot, _) {
                          return MessageBubble(
                            key: ValueKey('msg_${snapshot.id ?? index}_${snapshot.content.length}'),
                            message: context.read<ChatProvider>().messages[index],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),

          // 2. Welcome/Suggestions Layer (Visible only when empty)
          if (chatProvider.currentConversation == null || chatProvider.messages.isEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              // Input is at Alignment(0, 0.4), approx 70% down. 
              // Reserve bottom 40% of screen for valid margin to avoid overlap.
              bottom: MediaQuery.of(context).size.height * 0.4, 
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _buildWelcomeView(theme),
                  ),
                ),
              ),
            ),

          // 3. Input Layer
          AnimatedAlign(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            alignment: (chatProvider.currentConversation == null || chatProvider.messages.isEmpty)
                ? const Alignment(0, 0.4)
                : Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: MessageInput(
                  voiceModeEnabled: chatProvider.voiceModeEnabled,
                  onVoiceModeChanged: (enabled) => chatProvider.setVoiceMode(enabled),
                  onSend: (message) async {
                    // Auto-create conversation if none exists
                    if (chatProvider.currentConversation == null) {
                      await chatProvider.createConversation();
                    }
                    if (!mounted) return;
                    
                    final musicPlayer = context.read<MusicPlayerProvider>();
                    
                    // Append " dùng canvas" to message for API only, not shown in UI
                    final messageToSend = _forceCanvasTool 
                        ? '$message dùng canvas' 
                        : message;
                    
                    chatProvider.sendMessage(
                      messageToSend,
                      displayContent: message, // Show original message to user
                      onMusicPlay: (url, title, thumbnail, duration) {
                        musicPlayer.playFromUrl(
                          url: url,
                          title: title,
                          thumbnail: thumbnail,
                          duration: duration,
                        );
                      },
                    );
                    
                    // Scroll to bottom after user sends
                    _isUserScrolling = false;
                    Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom(isStreaming: false));
                  },
                  onSendWithFile: (message, file) async {
                    // Auto-create conversation if none exists
                    if (chatProvider.currentConversation == null) {
                      await chatProvider.createConversation();
                    }
                    if (!mounted) return;
                    
                    final musicPlayer = context.read<MusicPlayerProvider>();

                    // Append " dùng canvas" to message for API only, not shown in UI
                    final messageToSend = _forceCanvasTool 
                        ? '$message dùng canvas' 
                        : message;

                    chatProvider.sendMessage(
                      messageToSend,
                      displayContent: message, // Show original message to user
                      file: file,
                      onMusicPlay: (url, title, thumbnail, duration) {
                        musicPlayer.playFromUrl(
                          url: url,
                          title: title,
                          thumbnail: thumbnail,
                          duration: duration,
                        );
                      },
                    );

                    // Scroll to bottom after user sends
                    _isUserScrolling = false;
                    Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom(isStreaming: false));
                  },
                  isLoading: chatProvider.isStreaming,
                  onStop: () => chatProvider.stopStreaming(),
                  onMusicTap: () {
                    final musicPlayer = context.read<MusicPlayerProvider>();
                    if (musicPlayer.isVisible) {
                      musicPlayer.hide();
                    } else {
                      musicPlayer.show();
                    }
                  },
                  onCanvasTap: () {
                    // Only toggle forceCanvasTool mode - canvas panel shows when LLM creates canvas
                    setState(() {
                      _forceCanvasTool = !_forceCanvasTool;
                    });
                  },
                  forceCanvasTool: _forceCanvasTool,
                ),
              ),
            ),
          ),
          ],  // End of spread operator for normal chat UI
        ],
      ),
    );
  }

  Widget _buildWelcomeView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary,
                  ],
                ),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Xin chào!',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Tôi có thể giúp gì cho bạn?',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // Suggestions
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildSuggestionChip(
                  'Bạn có thể làm gì?',
                  Icons.help_outline,
                  theme,
                ),
                _buildSuggestionChip(
                  'Tạo ảnh 1 con mèo',
                  Icons.image,
                  theme,
                ),
                _buildSuggestionChip(
                  'Mở 1 bài nhạc RnB',
                  Icons.music_note,
                  theme,
                ),
              ],
            ),
          ],
        ),
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
        content: const Text('Bạn có chắc muốn xóa cuộc trò chuyện này? Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              chatProvider.deleteConversation(chatProvider.currentConversation!.id);
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

  void _showToolPermissionDialog(BuildContext context, ChatProvider chatProvider) {
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
            const Text('AI đang yêu cầu thực hiện hành động sau trên thiết bị của bạn:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                actionDesc,
                style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
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
              chatProvider.submitToolResult(name, 'Error: Quyền bị từ chối bởi người dùng.', tool['tool_call_id']);
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
  final bool isStreaming;
  final bool isGeneratingImage;
  final int generatedImages;

  const _MessageSnapshot({
    required this.id,
    required this.content,
    required this.thinking,
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
        other.isStreaming == isStreaming &&
        other.isGeneratingImage == isGeneratingImage &&
        other.generatedImages == generatedImages;
  }

  @override
  int get hashCode => Object.hash(id, content, thinking, isStreaming, isGeneratingImage, generatedImages);
}
