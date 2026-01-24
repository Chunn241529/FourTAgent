import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/message.dart';
import '../../providers/chat_provider.dart';
import 'search_indicator.dart';
import 'deep_search_indicator.dart';
import '../common/custom_snackbar.dart';
import 'plan_indicator.dart';

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
                // Display image if present
                if (message.imageBase64 != null && message.imageBase64!.isNotEmpty)
                  Builder(
                    builder: (context) {
                      String base64Str = message.imageBase64!;
                      // Check for data URI info
                      bool isImage = true;
                      String mimeType = '';
                      
                      if (base64Str.startsWith('data:')) {
                        final markerIndex = base64Str.indexOf(';');
                        if (markerIndex > 0) {
                          mimeType = base64Str.substring(5, markerIndex);
                          if (!mimeType.startsWith('image/')) {
                            isImage = false;
                          }
                        }
                      }
                      
                      // Extract raw bytes
                      String base64Data = base64Str;
                      if (base64Data.contains(',')) {
                        base64Data = base64Data.split(',').last;
                      }

                      if (isImage) {
                         return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              base64Decode(base64Data),
                              width: 200,
                              height: 200,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 200,
                                height: 100,
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.broken_image, size: 40),
                              ),
                            ),
                          ),
                        );
                      } else {
                        // Render File Card for non-image files
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                               color: theme.colorScheme.outline.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                               Icon(
                                 _getFileIcon(mimeType),
                                 color: theme.colorScheme.primary,
                               ),
                               const SizedBox(width: 8),
                               Flexible(
                                 child: Text(
                                   'Tệp đính kèm (${mimeType.split('/').last.toUpperCase()})',
                                   style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                                   maxLines: 1,
                                   overflow: TextOverflow.ellipsis,
                                 ),
                               ),
                            ],
                          ),
                        );
                      }
                    },
                  ),
                // Display text content
                if (message.content.isNotEmpty && !message.content.startsWith('[Đã gửi'))
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
                  'Lumina AI',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 6),

                // 1. Deep Search Indicator (status updates) - FIRST
                if (message.deepSearchUpdates.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildDeepSearchIndicator(message),
                  ),

                // 2. Plan Indicator (collapsible) - SECOND
                if (message.plan != null && message.plan!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PlanIndicator(
                      plan: message.plan!,
                      isStreaming: message.isStreaming,
                    ),
                  ),

                // 3. Thinking Indicator (Collapsible) - THIRD (during synthesis)
                if (message.thinking != null && message.thinking!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ThinkingIndicator(
                      thinking: message.thinking!,
                      isStreaming: message.isStreaming,
                    ),
                  ),

                // 4. Content with interleaved searches
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

  IconData _getFileIcon(String mimeType) {
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('word')) return Icons.description;
    if (mimeType.contains('sheet') || mimeType.contains('excel')) return Icons.table_chart;
    if (mimeType.contains('text')) return Icons.text_snippet;
    if (mimeType.contains('audio')) return Icons.audio_file;
    return Icons.insert_drive_file;
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
                onTapLink: (text, href, title) async {
                  if (href != null) {
                    final uri = Uri.tryParse(href);
                    if (uri != null && await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  }
                },
                styleSheet: MarkdownStyleSheet(
                  p: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.grey[300] : Colors.grey[850],
                    height: 1.5,
                  ),
                  strong: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.grey[900],
                  ),
                  a: TextStyle(
                    color: isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2),
                    decoration: TextDecoration.underline,
                  ),
                  code: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    backgroundColor: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFf5f5f5),
                    color: isDark ? const Color(0xFFE0E0E0) : const Color(0xFF1A1A1A),
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFf5f5f5),
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
                onTapLink: (text, href, title) async {
                  if (href != null) {
                    final uri = Uri.tryParse(href);
                    if (uri != null && await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  }
                },
                styleSheet: MarkdownStyleSheet(
                  p: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.grey[300] : Colors.grey[800],
                    height: 1.5,
                  ),
                  strong: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.grey[900],
                  ),
                  a: TextStyle(
                    color: isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2),
                    decoration: TextDecoration.underline,
                  ),
                  code: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    backgroundColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFf5f5f5),
                    color: isDark ? const Color(0xFFE0E0E0) : const Color(0xFF1A1A1A),
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFf5f5f5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  blockquote: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.grey[300] : Colors.grey[800],
                    fontStyle: FontStyle.italic,
                  ),
                  blockquoteDecoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF0F4F8),
                    border: Border(
                      left: BorderSide(
                        color: isDark ? const Color(0xFF64B5F6) : Colors.blue,
                        width: 3,
                      ),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
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
        // Body text
        p: theme.textTheme.bodyLarge?.copyWith(
          height: 1.6,
          color: isDark ? Colors.grey[300] : Colors.grey[850],
        ),
        // Headers with explicit dark mode colors
        h1: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.grey[900],
        ),
        h2: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.grey[100] : Colors.grey[900],
        ),
        h3: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.grey[200] : Colors.grey[900],
        ),
        // Strong/bold text
        strong: TextStyle(
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.grey[900],
        ),
        // Emphasis/italic
        em: TextStyle(
          fontStyle: FontStyle.italic,
          color: isDark ? Colors.grey[300] : Colors.grey[800],
        ),
        // Links - distinct but not clashing
        a: TextStyle(
          color: isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2),
          decoration: TextDecoration.underline,
        ),
        // Inline code
        code: TextStyle(
          backgroundColor: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE8E8E8),
          fontFamily: 'monospace',
          fontSize: 13,
          color: isDark ? const Color(0xFFE0E0E0) : const Color(0xFF1A1A1A),
        ),
        // Code block
        codeblockDecoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? const Color(0xFF3D3D3D) : const Color(0xFFE0E0E0),
          ),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        listIndent: 20,
        // List bullets
        listBullet: theme.textTheme.bodyMedium?.copyWith(
          color: isDark ? Colors.grey[400] : Colors.grey[700],
        ),
        // Blockquote
        blockquote: theme.textTheme.bodyLarge?.copyWith(
          color: isDark ? Colors.grey[300] : Colors.grey[800],
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F4F8),
          border: Border(
            left: BorderSide(
              color: isDark ? const Color(0xFF64B5F6) : theme.colorScheme.primary,
              width: 3,
            ),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        // Horizontal rule
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              width: 1,
            ),
          ),
        ),
      ),
      // Handle link taps
      onTapLink: (text, href, title) async {
        if (href != null) {
          final uri = Uri.tryParse(href);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      },
      // Handle image rendering
      imageBuilder: (uri, title, alt) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            uri.toString(),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image, color: Colors.grey[500]),
                    const SizedBox(width: 8),
                    Flexible(child: Text(alt ?? 'Image failed to load', style: TextStyle(color: Colors.grey[500]))),
                  ],
                ),
              );
            },
          ),
        );
      },
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
              CustomSnackBar.showSuccess(context, 'Đã sao chép');
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


  Widget _buildDeepSearchIndicator(Message message) {
    if (message.deepSearchUpdates.isEmpty) return const SizedBox.shrink();

    final updates = message.deepSearchUpdates;
    // If streaming, the last update is active.
    // If not streaming (done), all updates are completed.
    // However, usually we might want to collapse completed ones or show them differently?
    // For now, let's show all as completed except the last one if streaming.
    
    final isStreaming = message.isStreaming;
    final completedSteps = isStreaming && updates.isNotEmpty 
        ? updates.sublist(0, updates.length - 1)
        : updates;
    
    final activeSteps = isStreaming && updates.isNotEmpty
        ? [updates.last]
        : <String>[];

    return DeepSearchIndicator(
      activeSteps: activeSteps,
      completedSteps: completedSteps,
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
  final bool isStreaming;

  const _ThinkingIndicator({
    required this.thinking,
    required this.isStreaming,
  });

  @override
  State<_ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<_ThinkingIndicator> {
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    // Auto-expand if actively streaming thinking content
    if (widget.isStreaming) {
      _isExpanded = true;
    }
  }

  @override
  void didUpdateWidget(_ThinkingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-collapse when streaming finishes
    if (oldWidget.isStreaming && !widget.isStreaming) {
        // Optional: Delay collapse slightly for better UX?
        // For now, immediate collapse as requested.
        setState(() {
          _isExpanded = false;
        });
    }
  }

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
