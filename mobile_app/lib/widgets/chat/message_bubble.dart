import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../../models/message.dart';
import '../../providers/chat_provider.dart';
import 'search_indicator.dart';

/// Modern message bubble widget - User on right, AI on left
class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == 'user';
    final isDark = theme.brightness == Brightness.dark;

    if (isUser) {
      return _buildUserMessage(context, theme);
    } else {
      return _buildAIMessage(context, theme, isDark);
    }
  }

  /// User message - right aligned, no background, simple style
  Widget _buildUserMessage(BuildContext context, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 48), // Spacing from left
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SelectableText(
                  message.content,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                    color: theme.colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// AI message - left aligned with avatar
  Widget _buildAIMessage(BuildContext context, ThemeData theme, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI Avatar
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.secondary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          // Message content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // AI name
                Text(
                  'FourT AI',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 6),

                // Thinking indicator
                if (message.thinking != null && message.thinking!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ThinkingIndicator(thinking: message.thinking!),
                  ),

                // Content with interleaved searches
                _buildInterleavedContent(theme, isDark),

                // Streaming indicator
                if (message.isStreaming)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _buildStreamingIndicator(theme),
                  ),
                // Actions
                if (!message.isStreaming && message.content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _buildActions(context, theme),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 48), // Spacing from right
        ],
      ),
    );
  }

  Widget _buildInterleavedContent(ThemeData theme, bool isDark) {
    if (message.content.isEmpty) return const SizedBox.shrink();

    // Regex to find search markers: [[SEARCH:query]]
    final regex = RegExp(r'\[\[SEARCH:(.*?)\]\]');
    final children = <Widget>[];
    int lastIndex = 0;
    
    final content = message.content;

    for (final match in regex.allMatches(content)) {
      // Add text before match
      if (match.start > lastIndex) {
        final text = content.substring(lastIndex, match.start);
        if (text.trim().isNotEmpty) {
           children.add(
             MarkdownBody(
                data: text,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.grey[300] : Colors.grey[800],
                    height: 1.5,
                  ),
                  code: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    backgroundColor: isDark ? const Color(0xFF2d2d2d) : const Color(0xFFf5f5f5),
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2d2d2d) : const Color(0xFFf5f5f5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
             )
           );
        }
      }
      
      // Add search widget
      final query = match.group(1);
      if (query != null) {
          final isCompleted = message.completedSearches.contains(query);
          // If not in completed, assumes active
          
          children.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SearchIndicator(
                  activeSearches: isCompleted ? [] : [query],
                  completedSearches: isCompleted ? [query] : [],
              ),
          ));
      }
      
      lastIndex = match.end;
    }
    
    // Add remaining text
    if (lastIndex < content.length) {
       final text = content.substring(lastIndex);
       if (text.trim().isNotEmpty) {
          children.add(
             MarkdownBody(
                data: text,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.grey[300] : Colors.grey[800],
                    height: 1.5,
                  ),
                  code: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    backgroundColor: isDark ? const Color(0xFF2d2d2d) : const Color(0xFFf5f5f5),
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2d2d2d) : const Color(0xFFf5f5f5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
             )
           );
       }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  // Deprecated _buildMarkdownContent removed/replaced
  // Widget _buildMarkdownContent(ThemeData theme, bool isDark) { ... } preserved if needed but replacing call site.



  Widget _buildMarkdownContent(ThemeData theme, bool isDark) {
    return MarkdownBody(
      data: message.content,
      selectable: true,
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet(
        p: theme.textTheme.bodyLarge?.copyWith(
          height: 1.6,
          color: theme.colorScheme.onSurface,
        ),
        h1: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        h2: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        h3: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        code: TextStyle(
          backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFE8E8E8),
          fontFamily: 'monospace',
          fontSize: 13,
          color: isDark ? const Color(0xFFE0E0E0) : const Color(0xFF1A1A1A),
        ),
        codeblockDecoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? const Color(0xFF3D3D3D) : const Color(0xFFE0E0E0),
          ),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        listIndent: 20,
        blockquote: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface.withOpacity(0.7),
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.primary, width: 3),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12),
      ),
    );
  }

  Widget _buildStreamingIndicator(ThemeData theme) {
    return Padding(
      padding: EdgeInsets.zero, // Fixed alignment
      child: _TypingIndicator(
        dotCount: message.content.isEmpty ? 3 : 1, // 3 dots when thinking/empty, 1 dot when streaming text
      ),
    );
  }

  Widget _buildActions(BuildContext context, ThemeData theme) {
    final chatProvider = context.read<ChatProvider>();
    final isLiked = message.feedback == 'like';
    final isDisliked = message.feedback == 'dislike';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: Icons.copy_outlined,
          onTap: () {
            Clipboard.setData(ClipboardData(text: message.content));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã sao chép'), duration: Duration(seconds: 1)),
              );
            }
          },
        ),
        const SizedBox(width: 4),
        _ActionButton(
          icon: isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
          isActive: isLiked,
          onTap: () {
            if (message.id != null && context.mounted) {
              chatProvider.submitFeedback(message.id!, 'like');
            }
          },
        ),
        const SizedBox(width: 4),
        _ActionButton(
          icon: isDisliked ? Icons.thumb_down : Icons.thumb_down_outlined,
          isActive: isDisliked,
          onTap: () {
            if (message.id != null && context.mounted) {
              chatProvider.submitFeedback(message.id!, 'dislike');
            }
          },
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;

  const _ActionButton({
    required this.icon,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 14,
          color: isActive
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withOpacity(0.4),
        ),
      ),
    );
  }
}


class _ThinkingIndicator extends StatefulWidget {
  final String thinking;

  const _ThinkingIndicator({required this.thinking});

  @override
  State<_ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<_ThinkingIndicator> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  size: 16,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  'Thinking Process',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded)
          Container(
            padding: const EdgeInsets.only(left: 12, top: 4, bottom: 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: theme.colorScheme.onSurface.withOpacity(0.2),
                  width: 2,
                ),
              ),
            ),
            child: Text(
              widget.thinking,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  final int dotCount;
  const _TypingIndicator({this.dotCount = 3});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Modern accent color or just onSurface
    final color = Theme.of(context).brightness == Brightness.dark 
        ? Colors.white 
        : Colors.black; 
        
    return Container(
      // Reduced padding to fix alignment, removing left padding
      padding: const EdgeInsets.symmetric(vertical: 8), 
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(widget.dotCount, (index) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              // Creating a wave effect
              double wave = (_controller.value + index * 0.2) % 1.0;
              double opacity = 0.2 + 0.8 * (0.5 - (0.5 - wave).abs()) * 2; // Triangle 0.2 -> 1.0 -> 0.2
              opacity = opacity.clamp(0.2, 1.0);
              
              return Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 4), // Space between dots
                decoration: BoxDecoration(
                  color: color.withOpacity(opacity),
                  shape: BoxShape.circle,
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
