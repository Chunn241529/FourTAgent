import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import '../common/custom_snackbar.dart';

/// Custom code block builder with copy button and language label
class CodeBlockBuilder extends MarkdownElementBuilder {
  final bool isDark;

  CodeBlockBuilder({required this.isDark});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // Extract language from code fence (e.g., ```python)
    String? language;
    String code = element.textContent;

    // Check if element has info string (language)
    if (element.attributes.containsKey('class')) {
      final className = element.attributes['class'] ?? '';
      if (className.startsWith('language-')) {
        language = className.substring(9); // Remove 'language-' prefix
      }
    }

    return _CodeBlockWidget(
      code: code,
      language: language,
      isDark: isDark,
    );
  }
}

class _CodeBlockWidget extends StatefulWidget {
  final String code;
  final String? language;
  final bool isDark;

  const _CodeBlockWidget({
    required this.code,
    this.language,
    required this.isDark,
  });

  @override
  State<_CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<_CodeBlockWidget> {
  bool _copied = false;

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.code.trim()));
    setState(() => _copied = true);
    
    if (mounted) {
      CustomSnackBar.showSuccess(context, 'Đã sao chép code');
    }

    // Reset icon after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark 
        ? const Color(0xFF1E1E1E)  // Dark background
        : const Color(0xFFF6F8FA); // Light background (GitHub style)
    
    final borderColor = widget.isDark
        ? const Color(0xFF3D3D3D)
        : const Color(0xFFE1E4E8);
    
    final headerBgColor = widget.isDark
        ? const Color(0xFF2D2D2D)
        : const Color(0xFFEAEEF2);
    
    final textColor = widget.isDark
        ? const Color(0xFFE6E6E6)
        : const Color(0xFF24292F);
    
    final labelColor = widget.isDark
        ? Colors.grey[400]
        : Colors.grey[600];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with language label and copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: headerBgColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
              border: Border(
                bottom: BorderSide(color: borderColor, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Language label
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getLanguageIcon(widget.language),
                      size: 14,
                      color: labelColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.language?.toUpperCase() ?? 'CODE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                // Copy button
                InkWell(
                  onTap: _copyCode,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check : Icons.copy_outlined,
                          size: 14,
                          color: _copied 
                              ? Colors.green 
                              : labelColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? 'Đã copy' : 'Copy',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: _copied 
                                ? Colors.green 
                                : labelColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Code content
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                widget.code.trim(),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.5,
                  color: textColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getLanguageIcon(String? language) {
    if (language == null) return Icons.code;
    
    switch (language.toLowerCase()) {
      case 'python':
      case 'py':
        return Icons.code;
      case 'javascript':
      case 'js':
      case 'typescript':
      case 'ts':
        return Icons.javascript;
      case 'dart':
        return Icons.flutter_dash;
      case 'html':
      case 'css':
        return Icons.web;
      case 'bash':
      case 'shell':
      case 'sh':
      case 'zsh':
        return Icons.terminal;
      case 'sql':
        return Icons.storage;
      case 'json':
      case 'yaml':
      case 'yml':
        return Icons.data_object;
      case 'java':
      case 'kotlin':
      case 'swift':
        return Icons.phone_android;
      default:
        return Icons.code;
    }
  }
}
