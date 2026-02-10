import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../models/canvas_model.dart';
import '../../providers/canvas_provider.dart';
import '../../utils/html_detector.dart';
import '../chat/code_block_builder.dart'; // Reuse code block builder
import 'html_preview_widget.dart';

/// View modes for canvas content
enum CanvasViewMode { markdown, html, source }

class CanvasView extends StatefulWidget {
  final CanvasModel canvas;
  final VoidCallback onClose;

  const CanvasView({
    super.key,
    required this.canvas,
    required this.onClose,
  });

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  bool _isEditing = false;
  CanvasViewMode _viewMode = CanvasViewMode.markdown; // Current view mode
  bool _hasFrontendCode = false; // Whether content has HTML/CSS/JS
  
  // Undo/Redo stacks
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  String _lastSavedContent = '';
  
  // Current heading level for dropdown display
  String _currentHeading = 'p';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.canvas.title);
    _contentController = TextEditingController(text: widget.canvas.content);
    _lastSavedContent = widget.canvas.content;
    _contentController.addListener(_onContentChanged);
    _checkFrontendCode();
  }
  
  /// Check if content contains frontend code (HTML/CSS/JS)
  void _checkFrontendCode() {
    _hasFrontendCode = HtmlDetector.isFrontendCode(widget.canvas.content);
  }

  @override
  void didUpdateWidget(covariant CanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.canvas.id != oldWidget.canvas.id) {
      _titleController.text = widget.canvas.title;
      _contentController.text = widget.canvas.content;
      _lastSavedContent = widget.canvas.content;
      _undoStack.clear();
      _redoStack.clear();
      _isEditing = false;
      _viewMode = CanvasViewMode.markdown;
      _checkFrontendCode();
    }
  }

  @override
  void dispose() {
    _contentController.removeListener(_onContentChanged);
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }
  
  // Save content to undo stack when changed
  void _onContentChanged() {
    // Debounce: only save if content changed significantly
    if (_contentController.text != _lastSavedContent) {
      _undoStack.add(_lastSavedContent);
      _redoStack.clear(); // Clear redo stack on new change
      _lastSavedContent = _contentController.text;
      // Limit undo stack size
      if (_undoStack.length > 50) _undoStack.removeAt(0);
    }
  }
  
  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_contentController.text);
    final previousContent = _undoStack.removeLast();
    _contentController.removeListener(_onContentChanged);
    _contentController.text = previousContent;
    _lastSavedContent = previousContent;
    _contentController.addListener(_onContentChanged);
    setState(() {});
  }
  
  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_contentController.text);
    final nextContent = _redoStack.removeLast();
    _contentController.removeListener(_onContentChanged);
    _contentController.text = nextContent;
    _lastSavedContent = nextContent;
    _contentController.addListener(_onContentChanged);
    setState(() {});
  }
  
  // Wrap selected text with markdown syntax
  void _wrapSelection(String prefix, String suffix) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    
    // Check if selection is valid
    if (selection.start < 0 || selection.end < 0 || selection.start > text.length || selection.end > text.length) {
      // No valid selection, insert at end
      _contentController.text = text + prefix + suffix;
      _contentController.selection = TextSelection.collapsed(
        offset: text.length + prefix.length,
      );
      setState(() {});
      return;
    }
    
    if (selection.isCollapsed) {
      // No selection, insert at cursor
      final newText = text.substring(0, selection.start) + 
                      prefix + suffix + 
                      text.substring(selection.end);
      _contentController.text = newText;
      _contentController.selection = TextSelection.collapsed(
        offset: selection.start + prefix.length,
      );
    } else {
      // Wrap selected text
      final selectedText = text.substring(selection.start, selection.end);
      final newText = text.substring(0, selection.start) + 
                      prefix + selectedText + suffix + 
                      text.substring(selection.end);
      _contentController.text = newText;
      _contentController.selection = TextSelection(
        baseOffset: selection.start + prefix.length,
        extentOffset: selection.end + prefix.length,
      );
    }
    setState(() {});
  }
  
  // Toggle line prefix (for headings, lists)
  void _toggleLinePrefix(String prefix) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    
    // Check if selection is valid
    if (selection.start < 0 || selection.start > text.length) {
      // No valid cursor, add prefix to new line at end
      final newText = text.isEmpty ? prefix : '$text\n$prefix';
      _contentController.text = newText;
      _contentController.selection = TextSelection.collapsed(offset: newText.length);
      setState(() {});
      return;
    }
    
    // Find current line start
    int lineStart = selection.start;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }
    
    // Find current line end  
    int lineEnd = selection.start;
    while (lineEnd < text.length && text[lineEnd] != '\n') {
      lineEnd++;
    }
    
    final currentLine = text.substring(lineStart, lineEnd);
    
    String newLine;
    int offset;
    if (currentLine.startsWith(prefix)) {
      // Remove prefix
      newLine = currentLine.substring(prefix.length);
      offset = -prefix.length;
    } else {
      // Remove any existing heading prefixes first
      final cleanLine = currentLine.replaceFirst(RegExp(r'^#{1,6}\s*|^[-*]\s*|^\d+\.\s*'), '');
      // Add new prefix
      newLine = prefix + cleanLine;
      offset = newLine.length - currentLine.length;
    }
    
    final newText = text.substring(0, lineStart) + newLine + text.substring(lineEnd);
    _contentController.text = newText;
    _contentController.selection = TextSelection.collapsed(
      offset: (selection.start + offset).clamp(0, newText.length),
    );
    setState(() {});
  }
  
  // Copy content to clipboard
  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _contentController.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã sao chép nội dung'), duration: Duration(seconds: 1)),
      );
    }
  }
  
  // Export to file
  Future<void> _exportToFile() async {
    // Use file_picker to save file
    try {
      final fileName = '${_titleController.text.replaceAll(RegExp(r'[^\w\s-]'), '')}.md';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Xuất canvas',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['md', 'txt'],
      );
      if (path != null) {
        final file = File(path);
        await file.writeAsString(_contentController.text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã xuất file: $path'), duration: const Duration(seconds: 2)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xuất file: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  Future<void> _save() async {
    await context.read<CanvasProvider>().updateCanvas(
      widget.canvas.id,
      title: _titleController.text,
      content: _contentController.text,
    );
    setState(() {
      _isEditing = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu canvas'), duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
          children: [
            // Gemini-style Header Toolbar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.3))),
              ),
              child: Row(
                children: [
                  // LEFT SECTION - Fixed: Document icon + Title
                  Icon(Icons.description_outlined, size: 18, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150, minWidth: 80),
                    child: GestureDetector(
                      onTap: () => setState(() => _isEditing = true),
                      child: _isEditing
                          ? TextField(
                              controller: _titleController,
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(color: theme.colorScheme.primary.withOpacity(0.5)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(color: theme.colorScheme.primary),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                isDense: true,
                              ),
                              onSubmitted: (_) => _save(),
                            )
                          : Text(
                              widget.canvas.title,
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Edit button to enable editing
                  _ToolbarIconButton(
                    icon: Icons.edit_outlined, 
                    tooltip: 'Chỉnh sửa', 
                    onTap: () => setState(() => _isEditing = !_isEditing), 
                    theme: theme,
                  ),
                  const SizedBox(width: 4),
                  Container(width: 1, height: 20, color: theme.dividerColor.withOpacity(0.5)),
                  
                  // MIDDLE SECTION - Scrollable formatting buttons
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          const SizedBox(width: 4),
                          // Undo/Redo buttons
                          _ToolbarIconButton(icon: Icons.undo, tooltip: 'Hoàn tác', onTap: _undo, theme: theme, enabled: _undoStack.isNotEmpty),
                          _ToolbarIconButton(icon: Icons.redo, tooltip: 'Làm lại', onTap: _redo, theme: theme, enabled: _redoStack.isNotEmpty),
                          const SizedBox(width: 4),
                          Container(width: 1, height: 20, color: theme.dividerColor.withOpacity(0.5)),
                          const SizedBox(width: 4),
                          // Heading dropdown
                          PopupMenuButton<String>(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: Colors.transparent,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _currentHeading == 'h1' ? 'H1' : _currentHeading == 'h2' ? 'H2' : _currentHeading == 'h3' ? 'H3' : 'P',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                                    ),
                                  ),
                                  Icon(Icons.keyboard_arrow_down, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                                ],
                              ),
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            itemBuilder: (context) => [
                              const PopupMenuItem(value: 'h1', child: Text('Tiêu đề 1', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                              const PopupMenuItem(value: 'h2', child: Text('Tiêu đề 2', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                              const PopupMenuItem(value: 'h3', child: Text('Tiêu đề 3', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                              const PopupMenuItem(value: 'p', child: Text('Đoạn văn')),
                            ],
                            onSelected: (value) {
                              switch (value) {
                                case 'h1': _toggleLinePrefix('# '); break;
                                case 'h2': _toggleLinePrefix('## '); break;
                                case 'h3': _toggleLinePrefix('### '); break;
                                case 'p': _toggleLinePrefix(''); break;
                              }
                              setState(() => _currentHeading = value ?? 'p');
                            },
                          ),
                          const SizedBox(width: 4),
                          // Format buttons: Bold, Italic, Underline
                          _ToolbarIconButton(icon: Icons.format_bold, tooltip: 'Đậm', onTap: () => _wrapSelection('**', '**'), theme: theme),
                          _ToolbarIconButton(icon: Icons.format_italic, tooltip: 'Nghiêng', onTap: () => _wrapSelection('*', '*'), theme: theme),
                          _ToolbarIconButton(icon: Icons.format_underlined, tooltip: 'Gạch chân', onTap: () => _wrapSelection('<u>', '</u>'), theme: theme),
                          const SizedBox(width: 4),
                          Container(width: 1, height: 20, color: theme.dividerColor.withOpacity(0.5)),
                          const SizedBox(width: 4),
                          // List buttons
                          _ToolbarIconButton(icon: Icons.format_list_bulleted, tooltip: 'Danh sách', onTap: () => _toggleLinePrefix('- '), theme: theme),
                          _ToolbarIconButton(icon: Icons.format_list_numbered, tooltip: 'Danh sách đánh số', onTap: () => _toggleLinePrefix('1. '), theme: theme),
                        ],
                      ),
                    ),
                  ),
                  
                  // RIGHT SECTION - Fixed: Copy, Tạo, Close
                  Container(width: 1, height: 20, color: theme.dividerColor.withOpacity(0.5)),
                  const SizedBox(width: 4),
                  _ToolbarIconButton(icon: Icons.copy_outlined, tooltip: 'Sao chép', onTap: _copyToClipboard, theme: theme),
                  const SizedBox(width: 4),
                  // "Tạo" button
                  PopupMenuButton<String>(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Tạo',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                          Icon(Icons.keyboard_arrow_down, size: 16, color: theme.colorScheme.onPrimary),
                        ],
                      ),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'save', child: Text('Lưu')),
                      const PopupMenuItem(value: 'export', child: Text('Xuất file')),
                      const PopupMenuItem(value: 'copy', child: Text('Sao chép nội dung')),
                    ],
                    onSelected: (value) async {
                      switch (value) {
                        case 'save': await _save(); break;
                        case 'export': await _exportToFile(); break;
                        case 'copy': await _copyToClipboard(); break;
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  // Close button
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Đóng',
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(6),
                      minimumSize: const Size(32, 32),
                    ),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
          // View mode toggle (below toolbar when not editing)
          if (!_isEditing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.2))),
              ),
              child: Row(
                children: [
                  _buildViewModeChip(
                    'Xem trước', 
                    _viewMode == CanvasViewMode.markdown, 
                    () => setState(() => _viewMode = CanvasViewMode.markdown), 
                    theme,
                  ),
                  const SizedBox(width: 8),
                  // Show HTML preview tab when frontend code detected
                  if (_hasFrontendCode) ...[
                    _buildViewModeChip(
                      'HTML Preview', 
                      _viewMode == CanvasViewMode.html, 
                      () => setState(() => _viewMode = CanvasViewMode.html), 
                      theme,
                      icon: Icons.web,
                    ),
                    const SizedBox(width: 8),
                  ],
                  _buildViewModeChip(
                    'Mã nguồn', 
                    _viewMode == CanvasViewMode.source, 
                    () => setState(() => _viewMode = CanvasViewMode.source), 
                    theme,
                  ),
                  const Spacer(),
                  // Type badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _hasFrontendCode 
                          ? Colors.green.withOpacity(0.1)
                          : (widget.canvas.type == 'code' ? Colors.blue : Colors.orange).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _hasFrontendCode ? 'HTML' : widget.canvas.type.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _hasFrontendCode 
                            ? Colors.green 
                            : (widget.canvas.type == 'code' ? Colors.blue : Colors.orange),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Save/Cancel buttons when editing
          if (_isEditing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.2))),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Lưu'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green,
                    ),
                    onPressed: _save,
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Hủy'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.withOpacity(0.8),
                    ),
                    onPressed: () {
                      setState(() {
                        _isEditing = false;
                        _titleController.text = widget.canvas.title;
                        _contentController.text = widget.canvas.content;
                        _viewMode = CanvasViewMode.markdown;
                      });
                    },
                  ),
                ],
              ),
            ),
          // Content
          Expanded(
            child: _isEditing
                ? _buildEditor(theme)
                : _buildContentView(theme, isDark),
          ),
        ],
      );
  }

  Widget _buildEditor(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _contentController,
        maxLines: null,
        expands: true,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          height: 1.5,
          color: theme.textTheme.bodyMedium?.color,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Nhập nội dung...',
        ),
      ),
    );
  }

  Widget _buildRawView(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        widget.canvas.content,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          height: 1.5,
          color: theme.textTheme.bodyMedium?.color,
        ),
      ),
    );
  }

  Widget _buildPreview(ThemeData theme, bool isDark) {
    return Markdown(
      data: widget.canvas.content,
      selectable: true,
      builders: {
        'code': CodeBlockBuilder(isDark: isDark),
      },
      styleSheet: MarkdownStyleSheet(
        p: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
        codeblockDecoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Switch between view modes (markdown, html, source)
  Widget _buildContentView(ThemeData theme, bool isDark) {
    switch (_viewMode) {
      case CanvasViewMode.markdown:
        return _buildPreview(theme, isDark);
      case CanvasViewMode.html:
        return _buildHtmlPreview(isDark);
      case CanvasViewMode.source:
        return _buildRawView(theme);
    }
  }

  /// Build HTML preview using flutter_widget_from_html
  Widget _buildHtmlPreview(bool isDark) {
    return HtmlPreviewWidget(
      content: widget.canvas.content,
      isDark: isDark,
    );
  }

  Widget _buildToggleIcon({
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required String tooltip,
    required ThemeData theme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 2,
              offset: const Offset(0, 1),
            )
          ] : null,
        ),
        child: Tooltip(
          message: tooltip,
          child: Icon(
            icon,
            size: 18,
            color: isSelected 
                ? theme.colorScheme.primary 
                : theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
          ),
        ),
      ),
    );
  }

  Widget _buildViewModeChip(String label, bool isSelected, VoidCallback onTap, ThemeData theme, {IconData? icon}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected 
              ? theme.colorScheme.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? theme.colorScheme.primary.withOpacity(0.3)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon, 
                size: 14, 
                color: isSelected 
                    ? theme.colorScheme.primary 
                    : theme.colorScheme.onSurface.withOpacity(0.6),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected 
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Toolbar icon button for canvas header
class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final ThemeData theme;
  final bool enabled;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.theme,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurface.withOpacity(enabled ? 0.7 : 0.3),
          ),
        ),
      ),
    );
  }
}
