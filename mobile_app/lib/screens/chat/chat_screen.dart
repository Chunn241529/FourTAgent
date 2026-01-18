import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/message_input.dart';
import '../../widgets/navigation/app_drawer.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();
  bool _isUserScrolling = false;
  bool _isNearBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
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
    final chatProvider = context.watch<ChatProvider>();

    // Scroll to bottom when new messages arrive (only if not user scrolling)
    if (chatProvider.messages.isNotEmpty) {
      _scrollToBottom(isStreaming: chatProvider.isStreaming);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          chatProvider.currentConversation?.title ?? 'FourT AI',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
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
      drawer: AppDrawer(
        onConversationTap: (conversation) {
          chatProvider.selectConversation(conversation);
        },
        onNewChat: () async {
          await chatProvider.createConversation();
        },
      ),
      body: Stack(
        children: [
          // 1. Messages Layer (Always at bottom/fill, but hidden if empty to show welcome)
          if (chatProvider.currentConversation != null && chatProvider.messages.isNotEmpty)
            Positioned.fill(
              bottom: 120, // Space for input
              child: ListView.builder(
                controller: _scrollController,
                reverse: false, // Start from top
                padding: const EdgeInsets.only(top: 16, bottom: 24),
                itemCount: chatProvider.messages.length,
                itemBuilder: (context, index) {
                  return MessageBubble(
                    message: chatProvider.messages[index],
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: MessageInput(
                onSend: (message) {
                  chatProvider.sendMessage(message);
                  // Scroll to bottom after user sends
                  Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
                },
                onSendWithFile: (message, file) {
                  chatProvider.sendMessage(message, file: file);
                  // Scroll to bottom after user sends
                  Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
                },
                isLoading: chatProvider.isStreaming,
                onStop: () => chatProvider.stopStreaming(),
              ),
            ),
          ),
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
                // _buildSuggestionChip(
                //   'Viết code Python tính tổng',
                //   Icons.code,
                //   theme,
                // ),
                _buildSuggestionChip(
                  'Giải thích khái niệm Micro Services',
                  Icons.lightbulb_outline,
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
    
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(text),
      onPressed: () async {
        if (chatProvider.currentConversation == null) {
          await chatProvider.createConversation();
        }
        chatProvider.sendMessage(text);
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
}
