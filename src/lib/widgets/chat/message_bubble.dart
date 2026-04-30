import 'dart:convert';
import 'dart:async';
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
import 'web_fetch_indicator.dart';
import 'deep_search_indicator.dart';
import 'canvas_indicator.dart';
import '../common/custom_snackbar.dart';
import 'plan_indicator.dart';
import 'code_block_builder.dart';
import 'file_action_indicator.dart';
import 'simple_tool_indicator.dart';
import 'code_execution_widget.dart';
import 'activity_indicator.dart';
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

  // Streaming text animation state
  String _displayedText = '';
  int _targetLength = 0;
  Timer? _revealTimer;
  bool _streamComplete = false;

  String? _lastFeedback;
  String? _lastStatusMessage;

  @override
  void initState() {
    super.initState();
    _displayedText = widget.message.content;
    _targetLength = widget.message.content.length;
    _editController = TextEditingController(text: widget.message.content);
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.content != widget.message.content && !_isEditing) {
      _editController.text = widget.message.content;
    }

    // Handle streaming animation
    if (widget.message.isStreaming && widget.message.content.isNotEmpty) {
      // Reset if this is a new stream (content was empty before)
      if (_displayedText.isEmpty && _streamComplete) {
        _streamComplete = false;
      }
      final newLength = widget.message.content.length;
      if (newLength > _targetLength && !_streamComplete) {
        _targetLength = newLength;
        _startRevealAnimation();
      }
    } else if (!widget.message.isStreaming) {
      // Stream finished - show all content immediately
      _streamComplete = true;
      _displayedText = widget.message.content;
      _targetLength = widget.message.content.length;
      _revealTimer?.cancel();
    }

    // Note: Since message object reference might be the same,
    // we handled change detection in build() via _shouldRebuild()
  }

  void _startRevealAnimation() {
    _revealTimer?.cancel();

    // Reveal ~6 chars per 16ms (60fps) for smooth & fast typewriter effect
    const charsPerTick = 6;
    const tickDuration = Duration(milliseconds: 16);

    _revealTimer = Timer.periodic(tickDuration, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        final remaining = _targetLength - _displayedText.length;
        if (remaining <= 0) {
          timer.cancel();
          _displayedText = widget.message.content;
        } else {
          final toAdd = remaining < charsPerTick ? remaining : charsPerTick;
          _displayedText = widget.message.content.substring(0, _displayedText.length + toAdd);
        }
      });
    });
  }

  @override
  void dispose() {
    _editController.dispose();
    _revealTimer?.cancel();
    super.dispose();
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
      final filePath = '${downloadsDir.path}/Stella_image_$timestamp.png';

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
    final isUser = widget.message.role == 'user';
    
    Widget content = isUser 
        ? _buildUserMessage(context, theme)
        : _buildAIMessage(context, theme, isDark);

    return RepaintBoundary(child: content);
  }

  /// User message - right aligned with soft bubble
  Widget _buildUserMessage(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                // 1. Image/File attachments
                if (widget.message.imageBase64 != null &&
                    widget.message.imageBase64!.isNotEmpty)
                  _buildUserAttachment(context, theme),

                // 2. Text Message Bubble
                if (widget.message.content.isNotEmpty &&
                    !widget.message.content.startsWith('[Đã gửi'))
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Edit Button (Visible on hover/cleaner layout)
                      if (!_isEditing)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _isEditing = true;
                                _editController.text = widget.message.content;
                              });
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Icon(
                                Icons.edit_outlined,
                                size: 16,
                                color: theme.colorScheme.onSurface.withOpacity(0.3),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: _isEditing 
                              ? theme.colorScheme.primaryContainer 
                              : theme.colorScheme.primaryContainer.withOpacity(isDark ? 0.4 : 0.7),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(20),
                              topRight: Radius.circular(20),
                              bottomLeft: Radius.circular(20),
                              bottomRight: Radius.circular(4),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(_isEditing ? 0.1 : 0.03),
                                blurRadius: _isEditing ? 8 : 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: _isEditing
                              ? _buildUserEditingField(context, theme)
                              : SelectableText(
                                  widget.message.content,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    height: 1.5,
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
      ),
    );
  }

  Widget _buildUserAttachment(BuildContext context, ThemeData theme) {
    String base64Str = widget.message.imageBase64!;
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

    String base64Data = base64Str;
    if (base64Data.contains(',')) {
      base64Data = base64Data.split(',').last;
    }

    if (isImage) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.memory(
            base64Decode(base64Data),
            width: 240,
            fit: BoxFit.contain,
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
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getFileIcon(mimeType),
              color: theme.colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Tệp đính kèm (${mimeType.split('/').last.toUpperCase()})',
                style: theme.textTheme.bodyMedium?.copyWith(
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
  }

  Widget _buildUserEditingField(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _editController,
          autofocus: true,
          maxLines: null,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w500,
          ),
          cursorColor: theme.colorScheme.onPrimaryContainer,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 4),
            border: InputBorder.none,
            filled: false,
            fillColor: Colors.transparent,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  _editController.text = widget.message.content;
                });
              },
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onPrimaryContainer.withOpacity(0.7),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Hủy', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final newContent = _editController.text.trim();
                if (newContent.isNotEmpty &&
                    newContent != widget.message.content) {
                  context
                      .read<ChatProvider>()
                      .editMessage(widget.message, newContent);
                }
                setState(() {
                  _isEditing = false;
                });
              },
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.onPrimaryContainer,
                foregroundColor: theme.colorScheme.primaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Lưu', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ],
    );
  }

  /// AI message - left aligned with premium card style
  Widget _buildAIMessage(BuildContext context, ThemeData theme, bool isDark) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // 1. AI Avatar with Spinner
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: _AvatarSpinner(
              isAnimating: (widget.message.isStreaming &&
                      widget.message.content.isEmpty) ||
                  widget.message.isGeneratingImage,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Image.asset(
                      'assets/icon/icon.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // 2. Message content container
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reasoning Chain (Thinking)
                if (widget.message.thinking != null &&
                    widget.message.thinking!.isNotEmpty) ...[
                  Builder(
                    builder: (context) {
                      final thinking = widget.message.thinking!;
                      final splitIndex = widget.message.deepSearchStartIndex;

                      String preThinking = thinking;
                      if (splitIndex != null && splitIndex < thinking.length) {
                        preThinking = thinking.substring(0, splitIndex);
                      }

                      if (preThinking.isNotEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
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

                // Deep Search Indicator
                if (widget.message.deepSearchUpdates.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildDeepSearchIndicator(widget.message),
                  ),

                // Canvas Indicator
                if (widget.message.isCreatingCanvas)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: CanvasIndicator(),
                  ),

                // Status Message
                if (widget.message.isStreaming &&
                    widget.message.statusMessage != null &&
                    widget.message.statusMessage!.isNotEmpty &&
                    (widget.message.content.isEmpty &&
                        (widget.message.thinking == null ||
                            widget.message.thinking!.isEmpty)) &&
                    !widget.message.isCreatingCanvas)
                  _buildStreamingStatus(theme, isDark),

                // Post-Search Thinking
                if (widget.message.thinking != null &&
                    widget.message.thinking!.isNotEmpty) ...[
                  Builder(
                    builder: (context) {
                      final thinking = widget.message.thinking!;
                      final splitIndex = widget.message.deepSearchStartIndex;

                      if (splitIndex != null && splitIndex < thinking.length) {
                        final postThinking = thinking.substring(splitIndex);
                        if (postThinking.isNotEmpty) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
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

                // Code Executions
                if (widget.message.codeExecutions.isNotEmpty)
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

                // Main Markdown Content
                _buildMarkdownContent(theme, isDark),

                // Generated Images
                if (widget.message.generatedImages.isNotEmpty ||
                    widget.message.isGeneratingImage)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: MessageImagesWidget(
                      images: widget.message.generatedImages,
                      isGenerating: widget.message.isGeneratingImage,
                      onDownload: _downloadImage,
                    ),
                  ),

                // Bottom area: Transition between Streaming Status and Actions
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: widget.message.isStreaming
                      ? (widget.message.statusMessage != null &&
                              widget.message.statusMessage!.isNotEmpty &&
                              (widget.message.content.isEmpty &&
                                  (widget.message.thinking == null ||
                                      widget.message.thinking!.isEmpty)) &&
                              !widget.message.isCreatingCanvas
                          ? KeyedSubtree(
                              key: const ValueKey('streaming_status'),
                              child: _buildStreamingStatus(theme, isDark),
                            )
                          : const SizedBox.shrink(key: ValueKey('empty_status')))
                      : (widget.message.content.isNotEmpty
                          ? KeyedSubtree(
                              key: const ValueKey('actions'),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: _buildActions(context, theme),
                              ),
                            )
                          : const SizedBox.shrink(key: ValueKey('empty_actions'))),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24), // Spacing from right
        ],
      ),
    ),
      ),
    );
  }

  Widget _buildStreamingStatus(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary.withOpacity(0.5),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            widget.message.statusMessage!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontStyle: FontStyle.italic,
              letterSpacing: 0.2,
            ),
          ),
        ],
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
    // During streaming, show animated text. When done, show full content.
    // Use _displayedText as the primary source of truth for the UI
    final content = _displayedText.isEmpty ? widget.message.content : _displayedText;

    return _buildSegmentedContent(
      context,
      theme,
      content,
      isThinking: false,
    );
  }

  Widget _buildMarkdownBody(ThemeData theme, bool isDark, String content) {
    return MarkdownBody(
      data: content,
      selectable: true,
      softLineBreak: true,
      builders: {'code': CodeBlockBuilder(isDark: isDark)},
      styleSheet: MarkdownStyleSheet(
        p: theme.textTheme.bodyLarge?.copyWith(
          height: 1.6,
          color: isDark ? const Color(0xFFE0E0E0) : const Color(0xFF202124),
          letterSpacing: 0.2,
        ),
        h1: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black,
          height: 1.4,
        ),
        h2: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.grey[100] : Colors.black,
          height: 1.4,
        ),
        h3: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.grey[200] : Colors.black,
          height: 1.4,
        ),
        strong: TextStyle(
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : Colors.black,
        ),
        em: const TextStyle(fontStyle: FontStyle.italic),
        a: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        code: TextStyle(
          backgroundColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          fontFamily: 'monospace',
          fontSize: 13,
        ),
        codeblockDecoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F1117) : const Color(0xFFF1F3F4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          ),
        ),
        codeblockPadding: const EdgeInsets.all(16),
        blockquoteDecoration: BoxDecoration(
          color: theme.colorScheme.primary.withOpacity(0.05),
          border: Border(
            left: BorderSide(color: theme.colorScheme.primary, width: 4),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        blockquotePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white10 : Colors.black12,
              width: 1,
            ),
          ),
        ),
        listIndent: 24,
        listBullet: theme.textTheme.bodyMedium?.copyWith(
          color: isDark ? Colors.grey[400] : Colors.grey[700],
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

        // Handle custom CANVAS indicator (embedded in content)
        if (uriStr.startsWith('canvas:')) {
           return const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: CanvasIndicator(),
            ),
          );
        }

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

        // Handle custom FETCH indicator
        if (uriStr.startsWith('fetch:')) {
          final url = Uri.decodeComponent(uriStr.substring(6)).trim();
          return Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: WebFetchIndicator(urls: [url]),
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
    final text = contentOverride ?? message.thinking;
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    return _buildSegmentedContent(
      context,
      theme,
      text,
      isThinking: true,
    );
  }

  Widget _buildSegmentedContent(
    BuildContext context,
    ThemeData theme,
    String text, {
    required bool isThinking,
  }) {
    final message = widget.message;
    final isDark = theme.brightness == Brightness.dark;
    final List<Widget> children = [];
    final splitPattern = RegExp(r'<<<TOOL:(.*?):(.*?)>>>');

    final matches = splitPattern.allMatches(text);
    final isFinished = !message.isStreaming || message.content.isNotEmpty;
    
    // Grouping activities
    List<ActivityItem> activityGroup = [];

    void flushActivities() {
      if (activityGroup.isNotEmpty) {
        children.add(
          Padding(
            padding: EdgeInsets.only(left: isThinking ? 12 : 0, bottom: 8),
            child: ModernActivityIndicator(
              activities: List.from(activityGroup),
              messageTimestamp: message.timestamp,
            ),
          ),
        );
        activityGroup.clear();
      }
    }

    int lastIndex = 0;
    final now = DateTime.now();
    final elapsedTotal = now.difference(message.timestamp).inSeconds;

    for (final match in matches) {
      if (match.start > lastIndex) {
        final segmentText = text.substring(lastIndex, match.start).trim();
        if (segmentText.isNotEmpty) {
          if (isThinking) {
            // Treat thinking text as an activity item
            final newItem = ActivityItem(
              type: ActivityType.thinking,
              label: 'Suy nghĩ',
              detail: segmentText.length > 250 
                  ? '${segmentText.substring(0, 250)}...' 
                  : segmentText,
              isActive: !isFinished,
              isCompleted: isFinished,
              elapsedSeconds: elapsedTotal,
            );

            // Deduplicate thinking segments if they are identical (rare but possible)
            if (activityGroup.isEmpty || activityGroup.last.detail != newItem.detail) {
              activityGroup.add(newItem);
            }
          } else {
            flushActivities();
            children.add(_buildMarkdownBody(theme, isDark, segmentText));
          }
        }
      }

      final action = match.group(1) ?? 'UNKNOWN';
      final target = match.group(2) ?? '';

      bool isCompleted = false;
      bool isFailed = false;

      final normalizedTarget = target.trim().replaceFirst(RegExp(r'/+$'), '');

      if (action == 'SEARCH') {
        if (message.completedSearches.any((s) => s.trim() == target.trim())) {
          isCompleted = true;
        } else if (message.failedSearches.any((s) => s.trim() == target.trim())) {
          isFailed = true;
        }
      } else if (action == 'FETCH') {
        if (message.completedFetches.any((u) =>
            u.trim().replaceFirst(RegExp(r'/+$'), '') == normalizedTarget)) {
          isCompleted = true;
        } else if (message.failedFetches.any((u) =>
            u.trim().replaceFirst(RegExp(r'/+$'), '') == normalizedTarget)) {
          isFailed = true;
        }
      } else if (['READ', 'CREATE', 'SEARCH_FILE'].contains(action)) {
        final tag = '$action:$target';
        if (message.completedFileActions.contains(tag)) isCompleted = true;
      }

      // Convert TOOL to ActivityItem
      ActivityType type;
      String label;
      switch (action) {
        case 'SEARCH': type = ActivityType.search; label = 'Tìm kiếm: $target'; break;
        case 'FETCH': type = ActivityType.fetch; label = 'Truy cập: $target'; break;
        case 'READ': type = ActivityType.read; label = 'Đọc file: $target'; break;
        case 'CREATE': type = ActivityType.write; label = 'Tạo file: $target'; break;
        case 'SEARCH_FILE': type = ActivityType.search; label = 'Tìm trong file: $target'; break;
        case 'RUN': type = ActivityType.execute; label = 'Thực thi: $target'; break;
        default: type = ActivityType.tool; label = '$action: $target';
      }

      final newItem = ActivityItem(
        type: isFailed ? ActivityType.error : type,
        label: label,
        isActive: !isCompleted && !isFailed && message.isStreaming,
        isCompleted: isCompleted,
      );

      // Deduplicate sequential identical activities
      bool isDuplicate = false;
      if (activityGroup.isNotEmpty) {
        final last = activityGroup.last;
        if (last.label == newItem.label && last.type == newItem.type) {
          isDuplicate = true;
        }
      }

      if (!isDuplicate) {
        activityGroup.add(newItem);
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      final segmentText = text.substring(lastIndex).trim();
      if (segmentText.isNotEmpty) {
        if (isThinking) {
          final newItem = ActivityItem(
            type: ActivityType.thinking,
            label: 'Suy nghĩ',
            detail: segmentText.length > 250 
                ? '${segmentText.substring(0, 250)}...' 
                : segmentText,
            isActive: !isFinished,
            isCompleted: isFinished,
            elapsedSeconds: elapsedTotal,
          );
          if (activityGroup.isEmpty || activityGroup.last.detail != newItem.detail) {
            activityGroup.add(newItem);
          }
        } else {
          flushActivities();
          children.add(_buildMarkdownBody(theme, isDark, segmentText));
        }
      }
    }

    flushActivities();

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
  final bool isFinished;

  const _ThinkingSegment({
    required this.content,
    this.isStreaming = false,
    this.isFinished = false,
  });

  @override
  State<_ThinkingSegment> createState() => _ThinkingSegmentState();
}

class _ThinkingSegmentState extends State<_ThinkingSegment>
    with TickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _shimmerController;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  Timer? _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    // Start collapsed as requested
    _isExpanded = false;
    
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    // Keep shimmer logic if needed for other parts, but we'll stop using it for the dot
    if (widget.isStreaming && !widget.isFinished) {
      _shimmerController.repeat();
      _startTimer();
    }

    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandController.value = 0.0;
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.fastOutSlowIn,
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedSeconds++;
        });
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didUpdateWidget(covariant _ThinkingSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    final shouldBeRunning = widget.isStreaming && !widget.isFinished;
    
    if (shouldBeRunning && !_shimmerController.isAnimating) {
      _shimmerController.repeat();
      _startTimer();
    } else if (!shouldBeRunning && _shimmerController.isAnimating) {
      _shimmerController.stop();
      _stopTimer();
    }

    // Auto-collapse logic REMOVED - expansion is now strictly manual
  }

  @override
  void dispose() {
    _stopTimer();
    _shimmerController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.content.trim().isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _toggleExpanded,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : theme.colorScheme.primary.withOpacity(0.04),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : theme.colorScheme.primary.withOpacity(0.1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Spinning psychology icon if streaming
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(seconds: 2),
                    curve: Curves.linear,
                    builder: (context, value, child) {
                      return Transform.rotate(
                        angle: widget.isFinished ? 0 : (value * 2 * math.pi),
                        child: child,
                      );
                    },
                    onEnd: () {
                      if (!widget.isFinished) setState(() {});
                    },
                    child: Icon(
                      Icons.psychology_outlined,
                      size: 16,
                      color: theme.colorScheme.primary.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      !widget.isFinished
                          ? 'Đang suy nghĩ trong ${_elapsedSeconds}s...'
                          : 'Đã suy nghĩ xong',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ClipRect(
          child: SizeTransition(
            sizeFactor: _expandAnimation,
            axisAlignment: -1.0,
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: isDark
                    ? Colors.white.withOpacity(0.02)
                    : const Color(0xFFF8F9FA),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.black.withOpacity(0.03),
                ),
              ),
              child: MarkdownBody(
                data: widget.content,
                styleSheet: MarkdownStyleSheet(
                  p: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.65),
                    height: 1.6,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
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
    final primaryColor = Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: Listenable.merge([_rotationController, _pulseController]),
      builder: (context, child) {
        final pulseValue = _pulseController.value;
        final glowOpacity = widget.isAnimating ? (0.15 + 0.25 * pulseValue) : 0.0;
        final glowSpread = widget.isAnimating ? (2.0 + 4.0 * pulseValue) : 0.0;

        return SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing glow
              AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: widget.isAnimating ? 1.0 : 0.0,
                child: Container(
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
              ),
              // Spinning arc using CustomPainter
              if (widget.isAnimating)
                CustomPaint(
                  size: const Size(38, 38),
                  painter: _SpinnerArcPainter(
                    rotation: _rotationController.value,
                    color: primaryColor,
                  ),
                ),
              // Avatar on top
              widget.child,
            ],
          ),
        );
      },
    );
  }
}


