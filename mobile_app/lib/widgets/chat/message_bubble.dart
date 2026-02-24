import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/message.dart';
import '../../providers/chat_provider.dart';
import '../../config/api_config.dart';
import 'search_indicator.dart';
import 'deep_search_indicator.dart';
import '../common/custom_snackbar.dart';
import 'plan_indicator.dart';
import 'code_block_builder.dart';
import 'file_action_indicator.dart';
import 'simple_tool_indicator.dart';
import 'code_execution_widget.dart';
import 'message_images_widget.dart';

class MessageBubble extends StatefulWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _isEditing = false;
  late TextEditingController _editController;

  // Caching variables to prevent expensive rebuilds (markdown parsing)
  Widget? _cachedWidget;
  String? _lastContent;
  bool? _lastIsStreaming;
  bool? _lastIsGeneratingImage;
  int? _lastImagesLength;
  String? _lastThinking;
  String? _lastPlan;
  int? _lastDeepSearchLength;
  int? _lastCodeExecLength;
  bool? _lastIsDark;
  bool? _lastIsEditing;
  // For feedback
  String? _lastFeedback;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.message.content);
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.content != widget.message.content && !_isEditing) {
      _editController.text = widget.message.content;
    }
    // Note: Since message object reference might be the same,
    // we handled change detection in build() via _shouldRebuild()
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  bool _shouldRebuild(bool isDark) {
    if (_cachedWidget == null) return true;

    final m = widget.message;

    if (isDark != _lastIsDark) return true;
    if (_isEditing != _lastIsEditing) return true;

    if (m.content != _lastContent) return true;
    if (m.isStreaming != _lastIsStreaming) return true;
    if (m.isGeneratingImage != _lastIsGeneratingImage) return true;
    if (m.generatedImages.length != _lastImagesLength) return true;
    if (m.thinking != _lastThinking) return true;
    if (m.plan != _lastPlan) return true;
    if (m.deepSearchUpdates.length != _lastDeepSearchLength) return true;
    // Check deep search content if length same (status update) -> assume length change for now or simply rebuild if specific optimized check needed.
    // For lists, checking length is often fast heuristic, but let's check hash if needed.
    // Actually, deep search updates are appended. Length check is okay.
    // But if status of an item updates?
    // Let's assume rebuild on any deep search update is rare enough.

    if (m.codeExecutions.length != _lastCodeExecLength) return true;

    if (m.feedback != _lastFeedback) return true;

    return false;
  }

  void _updateCacheState(bool isDark) {
    final m = widget.message;
    _lastIsDark = isDark;
    _lastIsEditing = _isEditing;
    _lastContent = m.content;
    _lastIsStreaming = m.isStreaming;
    _lastIsGeneratingImage = m.isGeneratingImage;
    _lastImagesLength = m.generatedImages.length;
    _lastThinking = m.thinking;
    _lastPlan = m.plan;
    _lastDeepSearchLength = m.deepSearchUpdates.length;
    _lastCodeExecLength = m.codeExecutions.length;
    _lastFeedback = m.feedback;
  }

  /// Download image to Downloads folder
  Future<void> _downloadImage(
    BuildContext context,
    List<int> imageBytes,
    String imageBase64,
  ) async {
    try {
      // Get Downloads directory
      Directory? downloadsDir;
      if (Platform.isAndroid || Platform.isLinux) {
        downloadsDir = Directory(
          '/home/${Platform.environment['USER']}/Downloads',
        );
        if (!downloadsDir.existsSync()) {
          downloadsDir = await getDownloadsDirectory();
        }
      } else if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        downloadsDir = Directory('$userProfile\\Downloads');
      } else if (Platform.isMacOS) {
        final home = Platform.environment['HOME'];
        downloadsDir = Directory('$home/Downloads');
      } else {
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      if (downloadsDir == null) {
        throw Exception('Could not find Downloads directory');
      }

      // Generate filename with timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${downloadsDir.path}/lumina_image_$timestamp.png';

      // Write file
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);

      if (context.mounted) {
        CustomSnackBar.showSuccess(context, 'Đã lưu ảnh: $filePath');
      }
    } catch (e) {
      if (context.mounted) {
        CustomSnackBar.showError(context, 'Lỗi lưu ảnh: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_shouldRebuild(isDark)) {
      final isUser = widget.message.role == 'user';
      Widget content;
      if (isUser) {
        content = _buildUserMessage(context, theme);
      } else {
        content = _buildAIMessage(context, theme, isDark);
      }

      // Wrap in RepaintBoundary to isolate painting updates (e.g. streaming text)
      _cachedWidget = RepaintBoundary(child: content);
      _updateCacheState(isDark);
    }

    return _cachedWidget!;
  }

  /// User message - right aligned, no background, simple style
  Widget _buildUserMessage(BuildContext context, ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Container(
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
                    if (widget.message.imageBase64 != null &&
                        widget.message.imageBase64!.isNotEmpty)
                      Builder(
                        builder: (context) {
                          String base64Str = widget.message.imageBase64!;
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
                                // Optimized: use memory image gracefully without heavy try-catch decoding if possible
                                child: Image.memory(
                                  base64Decode(base64Data),
                                  width: 200,
                                  height: 200,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 200,
                                    height: 100,
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    child: const Icon(
                                      Icons.broken_image,
                                      size: 40,
                                    ),
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
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.colorScheme.outline.withOpacity(
                                    0.2,
                                  ),
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
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w500,
                                          ),
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

                    if (widget.message.content.isNotEmpty &&
                        !widget.message.content.startsWith('[Đã gửi')) ...[
                      if (_isEditing)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              TextField(
                                controller: _editController,
                                autofocus: true,
                                maxLines: null,
                                style: theme.textTheme.bodyLarge,
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.all(12),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _isEditing = false;
                                          _editController.text =
                                              widget.message.content;
                                        });
                                      },
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text('Hủy'),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      onPressed: () {
                                        final newContent = _editController.text
                                            .trim();
                                        if (newContent.isNotEmpty &&
                                            newContent !=
                                                widget.message.content) {
                                          context
                                              .read<ChatProvider>()
                                              .editMessage(
                                                widget.message,
                                                newContent,
                                              );
                                        }
                                        setState(() {
                                          _isEditing = false;
                                        });
                                      },
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text('Lưu'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            SelectableText(
                              widget.message.content,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                height: 1.5,
                                color: theme.colorScheme.onSurface,
                              ),
                              textAlign: TextAlign.right,
                            ),
                            // Edit Icon (placed below message, right aligned)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _isEditing = true;
                                    _editController.text =
                                        widget.message.content;
                                  });
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.edit_outlined,
                                    size: 14,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.4),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// AI message - left aligned with avatar
  Widget _buildAIMessage(BuildContext context, ThemeData theme, bool isDark) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // AI Avatar with Spinner
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: _AvatarSpinner(
                  isAnimating:
                      (widget.message.isStreaming &&
                          widget.message.content.isEmpty) ||
                      widget.message.isGeneratingImage,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? Colors.black : Colors.white,
                      border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.2),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withOpacity(0.15),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Padding(
                        padding: const EdgeInsets.all(2.0),
                        child: Image.asset(
                          'assets/icon/icon.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Message content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // 1. Pre-Search Thinking (if any)
                    if (widget.message.thinking != null &&
                        widget.message.thinking!.isNotEmpty) ...[
                      Builder(
                        builder: (context) {
                          final thinking = widget.message.thinking!;
                          final splitIndex =
                              widget.message.deepSearchStartIndex;

                          String preThinking = thinking;
                          if (splitIndex != null &&
                              splitIndex < thinking.length) {
                            preThinking = thinking.substring(0, splitIndex);
                          }

                          if (preThinking.isNotEmpty) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildReasoningChain(
                                context,
                                theme,
                                widget.message,
                                contentOverride: preThinking,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],

                  // 2. Deep Search Indicator (status updates)
                    if (widget.message.deepSearchUpdates.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildDeepSearchIndicator(widget.message),
                      ),



                    // 4. Post-Search Thinking (if any)
                    if (widget.message.thinking != null &&
                        widget.message.thinking!.isNotEmpty) ...[
                      Builder(
                        builder: (context) {
                          final thinking = widget.message.thinking!;
                          final splitIndex =
                              widget.message.deepSearchStartIndex;

                          if (splitIndex != null &&
                              splitIndex < thinking.length) {
                            final postThinking = thinking.substring(splitIndex);
                            if (postThinking.isNotEmpty) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _buildReasoningChain(
                                  context,
                                  theme,
                                  widget.message,
                                  contentOverride: postThinking,
                                ),
                              );
                            }
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],

                    // Code Executions Results (Above content to avoid jumping)
                    if (widget.message.codeExecutions.isNotEmpty) ...[
                      ...widget.message.codeExecutions.map((exec) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: CodeExecutionWidget(
                            code: exec['code'] ?? '',
                            output: exec['output'] ?? '',
                            error: exec['error'] ?? '',
                            isDark: isDark,
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],

                    // 2. Content with interleaved indicators (using imageBuilder)
                    _buildMarkdownContent(theme, isDark),

                    // Generated Images using optimized widget
                    if (widget.message.generatedImages.isNotEmpty ||
                        widget.message.isGeneratingImage)
                      MessageImagesWidget(
                        images: widget.message.generatedImages,
                        isGenerating: widget.message.isGeneratingImage,
                        onDownload: _downloadImage,
                      ),

                    // Streaming indicator REMOVED (replaced by Avatar Spinner)
                    // if (widget.message.isStreaming && !widget.message.isGeneratingImage)
                    //   Padding(
                    //     padding: const EdgeInsets.only(top: 12),
                    //     child: _buildStreamingIndicator(theme),
                    //   ),
                    // Actions
                    if (!widget.message.isStreaming &&
                        widget.message.content.isNotEmpty)
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
        ),
      ),
    );
  }

  IconData _getFileIcon(String mimeType) {
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('word')) return Icons.description;
    if (mimeType.contains('sheet') || mimeType.contains('excel'))
      return Icons.table_chart;
    if (mimeType.contains('text')) return Icons.text_snippet;
    if (mimeType.contains('audio')) return Icons.audio_file;
    return Icons.insert_drive_file;
  }

  Widget _buildMarkdownContent(ThemeData theme, bool isDark) {
    // Always use MarkdownBody for consistency
    return MarkdownBody(
      data: widget.message.content,
      selectable: true,
      softLineBreak: true,
      builders: {'code': CodeBlockBuilder(isDark: isDark)},
      styleSheet: MarkdownStyleSheet(
        // Body text - generous line height for readability
        p: theme.textTheme.bodyLarge?.copyWith(
          height: 1.7,
          color: isDark ? Colors.grey[300] : Colors.grey[850],
          letterSpacing: 0.1,
        ),
        // Headers with explicit dark mode colors
        h1: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : Colors.grey[900],
          height: 1.3,
        ),
        h2: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.grey[100] : Colors.grey[900],
          height: 1.3,
        ),
        h3: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.grey[200] : Colors.grey[900],
          height: 1.3,
        ),
        // Strong/bold text
        strong: TextStyle(
          fontWeight: FontWeight.w600,
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
          decorationColor: isDark
              ? const Color(0xFF64B5F6).withOpacity(0.4)
              : const Color(0xFF1976D2).withOpacity(0.4),
        ),

        // Code block
        codeblockDecoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? const Color(0xFF2D2D44) : const Color(0xFFE0E0E0),
            width: 0.5,
          ),
        ),
        codeblockPadding: const EdgeInsets.all(14),
        listIndent: 24,
        // List bullets
        listBullet: theme.textTheme.bodyMedium?.copyWith(
          color: isDark ? Colors.grey[400] : Colors.grey[700],
        ),
        // Blockquote
        blockquote: theme.textTheme.bodyLarge?.copyWith(
          color: isDark ? Colors.grey[300] : Colors.grey[700],
          fontStyle: FontStyle.italic,
          height: 1.6,
        ),
        blockquoteDecoration: BoxDecoration(
          color: isDark
              ? theme.colorScheme.primary.withOpacity(0.06)
              : theme.colorScheme.primary.withOpacity(0.04),
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.primary.withOpacity(isDark ? 0.5 : 0.6),
              width: 3,
            ),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        // Horizontal rule
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              width: 0.5,
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
      // Handle image rendering (used for custom indicators)
      imageBuilder: (uri, title, alt) {
        final uriStr = uri.toString();

        // Handle custom SEARCH indicator
        if (uriStr.startsWith('search:')) {
          final query = Uri.decodeComponent(uriStr.substring(7));
          final isCompleted = widget.message.completedSearches.contains(query);
          return Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SearchIndicator(
                activeSearches: isCompleted ? [] : [query],
                completedSearches: isCompleted ? [query] : [],
              ),
            ),
          );
        }

        // Handle custom FILE_ACTION indicator
        if (uriStr.startsWith('file:')) {
          final parts = Uri.decodeComponent(uriStr.substring(5)).split(':');
          if (parts.length >= 2) {
            // Fix: remove potential leading slashes from action (e.g. ///CREATE from file:///CREATE)
            var action = parts[0];
            while (action.startsWith('/')) {
              action = action.substring(1);
            }

            final target = parts
                .sublist(1)
                .join(':'); // Path might contain colons
            final actionTag = '${action}:${target}';
            final isActionCompleted = widget.message.completedFileActions
                .contains(actionTag);

            return Align(
              alignment: Alignment.centerLeft,
              child: FileActionIndicator(
                action: action,
                target: target,
                isCompleted: !widget.message.isStreaming || isActionCompleted,
              ),
            );
          }
        }

        // Standard image rendering
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
                    Flexible(
                      child: Text(
                        alt ?? 'Image failed to load',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
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
        dotCount: widget.message.content.isEmpty
            ? 3
            : 1, // 3 dots when thinking/empty, 1 dot when streaming text
      ),
    );
  }

  Widget _buildActions(BuildContext context, ThemeData theme) {
    final chatProvider = context.read<ChatProvider>();
    final isLiked = widget.message.feedback == 'like';
    final isDisliked = widget.message.feedback == 'dislike';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: Icons.copy_outlined,
          tooltip: 'Sao chép',
          onTap: () {
            Clipboard.setData(ClipboardData(text: widget.message.content));
            if (context.mounted) {
              CustomSnackBar.showSuccess(context, 'Đã sao chép');
            }
          },
        ),
        const SizedBox(width: 2),
        _ActionButton(
          icon: isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
          tooltip: 'Hữu ích',
          isActive: isLiked,
          onTap: () {
            if (widget.message.id != null && context.mounted) {
              chatProvider.submitFeedback(widget.message.id!, 'like');
            }
          },
        ),
        const SizedBox(width: 2),
        _ActionButton(
          icon: isDisliked ? Icons.thumb_down : Icons.thumb_down_outlined,
          tooltip: 'Không hữu ích',
          isActive: isDisliked,
          onTap: () {
            if (widget.message.id != null && context.mounted) {
              chatProvider.submitFeedback(widget.message.id!, 'dislike');
            }
          },
        ),
      ],
    );
  }

  Widget _buildDeepSearchIndicator(Message message) {
    if (message.deepSearchUpdates.isEmpty) return const SizedBox.shrink();

    final updates = message.deepSearchUpdates;
    final isStreaming = message.isStreaming;
    final completedSteps = isStreaming && updates.isNotEmpty
        ? updates.sublist(0, updates.length - 1)
        : updates;

    final activeSteps = isStreaming && updates.isNotEmpty
        ? [updates.last]
        : <String>[];

    final searchType = _determineSearchType(message);
    final metadata = DeepSearchMetadata(
      totalSearches: message.completedSearches.length,
      elapsedTime: DateTime.now().difference(message.timestamp),
      sources: _extractSources(message),
      recentActions: message.completedSearches.take(5).toList(),
      plan: message.plan,
    );

    return DeepSearchIndicator(
      activeSteps: activeSteps,
      completedSteps: completedSteps,
      searchType: searchType,
      metadata: metadata,
      deepSearchData: message.deepSearchData,
    );
  }

  DeepSearchType _determineSearchType(Message message) {
    final content = '${message.content} ${message.thinking ?? ''}'
        .toLowerCase();

    if (content.contains('phân tích') || content.contains('analysis')) {
      return DeepSearchType.analysis;
    } else if (content.contains('sáng tạo') ||
        content.contains('creative') ||
        content.contains('viết')) {
      return DeepSearchType.creative;
    } else if (content.contains('nghiên cứu') || content.contains('research')) {
      return DeepSearchType.research;
    }
    return DeepSearchType.general;
  }

  List<String> _extractSources(Message message) {
    final sources = <String>[];
    final content = message.content;

    final urlPattern = RegExp(r'https?://[^\s\)]+');
    final matches = urlPattern.allMatches(content);
    for (final match in matches.take(5)) {
      final url = match.group(0) ?? '';
      if (url.isNotEmpty) {
        final domain = Uri.tryParse(url)?.host ?? url;
        if (!sources.contains(domain)) {
          sources.add(domain);
        }
      }
    }

    return sources;
  }

  Widget _buildReasoningChain(
    BuildContext context,
    ThemeData theme,
    Message message, {
    String? contentOverride,
  }) {
    if (message.thinking == null && contentOverride == null)
      return const SizedBox.shrink();

    final List<Widget> children = [];
    final splitPattern = RegExp(r'\n\n<<<TOOL:(.*?):(.*?)>>>\n\n');

    final thinkingContent = contentOverride ?? message.thinking!;
    final matches = splitPattern.allMatches(thinkingContent);

    int lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        final segmentText = thinkingContent
            .substring(lastIndex, match.start)
            .trim();
        if (segmentText.isNotEmpty) {
          children.add(_ThinkingSegment(content: segmentText, isStreaming: widget.message.isStreaming));
        }
      }

      final action = match.group(1) ?? 'UNKNOWN';
      final target = match.group(2) ?? '';

      bool isCompleted = false;
      if (action == 'SEARCH') {
        if (message.completedSearches.contains(target)) isCompleted = true;
      } else if (['READ', 'CREATE', 'SEARCH_FILE'].contains(action)) {
        final tag = '$action:$target';
        if (message.completedFileActions.contains(tag)) isCompleted = true;
      }

      children.add(
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8, top: 4),
          child: SimpleToolIndicator(
            action: action,
            target: target,
            isCompleted: isCompleted,
          ),
        ),
      );

      lastIndex = match.end;
    }

    if (lastIndex < thinkingContent.length) {
      final segmentText = thinkingContent.substring(lastIndex).trim();
      if (segmentText.isNotEmpty) {
        children.add(_ThinkingSegment(content: segmentText, isStreaming: widget.message.isStreaming));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;
  final String? tooltip;

  const _ActionButton({
    required this.icon,
    required this.onTap,
    this.isActive = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        splashColor: theme.colorScheme.primary.withOpacity(0.1),
        highlightColor: theme.colorScheme.primary.withOpacity(0.05),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isActive
                ? theme.colorScheme.primary.withOpacity(isDark ? 0.15 : 0.08)
                : Colors.transparent,
          ),
          child: Icon(
            icon,
            size: 15,
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withOpacity(0.4),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        preferBelow: true,
        child: button,
      );
    }

    return button;
  }
}

class _TypingIndicator extends StatefulWidget {
  final int dotCount;

  const _TypingIndicator({this.dotCount = 3});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...List.generate(widget.dotCount, (index) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // Staggered wave: each dot peaks at different times
                final phase = (_controller.value + index * 0.25) % 1.0;
                // Smooth bell curve for scale
                final scale = 0.6 + 0.4 * math.sin(phase * math.pi);
                final opacity = 0.3 + 0.7 * math.sin(phase * math.pi);

                return Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 5),
                  child: Transform.scale(
                    scale: scale,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            primaryColor.withOpacity(opacity),
                            Color.lerp(primaryColor,
                                    theme.colorScheme.tertiary, 0.5)!
                                .withOpacity(opacity),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          }),
          if (widget.dotCount > 1) ...[
            const SizedBox(width: 4),
            Text(
              'Đang trả lời',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark
                    ? Colors.grey[500]
                    : Colors.grey[600],
                fontStyle: FontStyle.italic,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThinkingSegment extends StatefulWidget {
  final String content;
  final bool isStreaming;

  const _ThinkingSegment({
    required this.content,
    this.isStreaming = false,
  });

  @override
  State<_ThinkingSegment> createState() => _ThinkingSegmentState();
}

class _ThinkingSegmentState extends State<_ThinkingSegment>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.isStreaming) {
      _shimmerController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _ThinkingSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isStreaming && !_shimmerController.isAnimating) {
      _shimmerController.repeat();
    } else if (!widget.isStreaming && _shimmerController.isAnimating) {
      _shimmerController.stop();
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.content.trim().isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isDark
                  ? Colors.white.withOpacity(0.04)
                  : Colors.black.withOpacity(0.03),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.psychology_outlined,
                  size: 14,
                  color: theme.colorScheme.primary.withOpacity(0.7),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Quá trình suy nghĩ',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.55),
                      fontWeight: FontWeight.w500,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                if (widget.isStreaming) ...[
                  const SizedBox(width: 6),
                  AnimatedBuilder(
                    animation: _shimmerController,
                    builder: (context, child) {
                      return Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary.withOpacity(
                            0.3 + 0.7 * math.sin(_shimmerController.value * math.pi),
                          ),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _isExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            margin: const EdgeInsets.only(left: 4, top: 8, bottom: 4),
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: isDark
                  ? Colors.white.withOpacity(0.03)
                  : const Color(0xFFF8F9FA),
              border: Border(
                left: BorderSide(
                  color: theme.colorScheme.primary.withOpacity(0.3),
                  width: 2.5,
                ),
              ),
            ),
            child: MarkdownBody(
              data: widget.content,
              styleSheet: MarkdownStyleSheet(
                p: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  height: 1.5,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          crossFadeState: _isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
      ],
    );
  }
}

/// Custom painter for smooth animated spinner arc around avatar
class _SpinnerArcPainter extends CustomPainter {
  final double rotation;
  final Color color;
  final double strokeWidth;

  _SpinnerArcPainter({
    required this.rotation,
    required this.color,
    this.strokeWidth = 2.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Create gradient arc shader
    paint.shader = SweepGradient(
      startAngle: 0,
      endAngle: math.pi * 2,
      colors: [
        Colors.transparent,
        color.withOpacity(0.1),
        color.withOpacity(0.6),
        color,
      ],
      stops: const [0.0, 0.3, 0.7, 1.0],
      transform: GradientRotation(rotation * math.pi * 2),
    ).createShader(rect);

    // Draw arc (270 degrees, leaving a gap)
    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      rotation * math.pi * 2,
      math.pi * 1.5,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpinnerArcPainter oldDelegate) {
    return oldDelegate.rotation != rotation || oldDelegate.color != color;
  }
}

class _AvatarSpinner extends StatefulWidget {
  final bool isAnimating;
  final Widget child;

  const _AvatarSpinner({required this.isAnimating, required this.child});

  @override
  State<_AvatarSpinner> createState() => _AvatarSpinnerState();
}

class _AvatarSpinnerState extends State<_AvatarSpinner>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (widget.isAnimating) {
      _rotationController.repeat();
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _AvatarSpinner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnimating != oldWidget.isAnimating) {
      if (widget.isAnimating) {
        _rotationController.repeat();
        _pulseController.repeat(reverse: true);
      } else {
        _rotationController.stop();
        _rotationController.reset();
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAnimating) return widget.child;

    final primaryColor = Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: Listenable.merge([_rotationController, _pulseController]),
      builder: (context, child) {
        final pulseValue = _pulseController.value;
        final glowOpacity = 0.15 + 0.25 * pulseValue;
        final glowSpread = 2.0 + 4.0 * pulseValue;

        return SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing glow
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withOpacity(glowOpacity),
                      blurRadius: 10,
                      spreadRadius: glowSpread,
                    ),
                  ],
                ),
              ),
              // Spinning arc using CustomPainter
              CustomPaint(
                size: const Size(38, 38),
                painter: _SpinnerArcPainter(
                  rotation: _rotationController.value,
                  color: primaryColor,
                ),
              ),
              // Avatar on top
              child!,
            ],
          ),
        );
      },
      child: widget.child,
    );
  }
}


