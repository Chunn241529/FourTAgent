import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'code_block_builder.dart';

class CodeExecutionWidget extends StatefulWidget {
  final String code;
  final String output;
  final String error;
  final bool isDark;

  const CodeExecutionWidget({
    super.key,
    required this.code,
    required this.output,
    required this.error,
    required this.isDark,
  });

  @override
  State<CodeExecutionWidget> createState() => _CodeExecutionWidgetState();
}

class _CodeExecutionWidgetState extends State<CodeExecutionWidget> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = widget.error.isNotEmpty;
    final borderColor = isError ? Colors.red.withOpacity(0.5) : (widget.isDark ? Colors.grey[800]! : Colors.grey[300]!);
    final bgColor = widget.isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: widget.isDark ? Colors.black26 : Colors.white54,
              child: Row(
                children: [
                  Icon(
                    Icons.terminal,
                    size: 16,
                    color: widget.isDark ? Colors.grey[400] : Colors.grey[700],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Code Execution',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: widget.isDark ? Colors.grey[400] : Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  // Status indicator
                  if (isError)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Failed',
                        style: TextStyle(
                          color: Colors.red[400],
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else
                     Text(
                        'Success',
                        style: TextStyle(
                          color: Colors.green[400],
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  const SizedBox(width: 8),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: widget.isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),

          if (_isExpanded) ...[
            // Input Code
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                      'Input Code:',
                      style: theme.textTheme.labelSmall?.copyWith(
                         color: widget.isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    CodeBlockWidget(
                      code: widget.code,
                      language: 'python',
                      isDark: widget.isDark,
                    ),
                ],
              ),
            ),
            
            // Output / Error
            Container(
               padding: const EdgeInsets.all(12),
               color: widget.isDark ? const Color(0xFF111111) : const Color(0xFFFFFFFF),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                    Text(
                      isError ? 'Error:' : 'Output:',
                      style: theme.textTheme.labelSmall?.copyWith(
                         color: isError ? Colors.red[400] : (widget.isDark ? Colors.grey[500] : Colors.grey[600]),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                       isError ? widget.error : widget.output,
                       style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: isError ? Colors.red[300] : (widget.isDark ? Colors.green[200] : Colors.green[800]),
                       ),
                    ),
                 ],
               ),
            ),
          ],
        ],
      ),
    );
  }
}
