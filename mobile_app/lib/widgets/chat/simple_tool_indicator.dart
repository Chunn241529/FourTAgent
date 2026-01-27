import 'package:flutter/material.dart';

class SimpleToolIndicator extends StatelessWidget {
  final String action; // 'SEARCH', 'READ', 'CREATE', etc.
  final String target; // Query or File Path
  final bool isCompleted;

  const SimpleToolIndicator({
    super.key,
    required this.action,
    required this.target,
    this.isCompleted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    IconData icon;
    String labelText;
    Color color;

    switch (action.toUpperCase()) {
      case 'SEARCH':
        icon = Icons.search;
        labelText = 'Đang tìm kiếm';
        color = Colors.orange;
        break;
      case 'READ':
        icon = Icons.file_open_outlined;
        labelText = 'Đang đọc file';
        color = Colors.blue;
        break;
      case 'CREATE':
        icon = Icons.create_new_folder_outlined;
        labelText = 'Đang tạo file';
        color = Colors.green;
        break;
      case 'SEARCH_FILE':
        icon = Icons.find_in_page_outlined;
        labelText = 'Đang tìm file';
        color = Colors.purple;
        break;
      default:
        icon = Icons.code;
        labelText = 'Tool: $action';
        color = Colors.grey;
    }

    if (isCompleted) {
       labelText = labelText.replaceFirst('Đang', 'Đã');
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCompleted ? Icons.check_circle_outline : icon,
            size: 16,
            color: isCompleted ? Colors.green : color,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: RichText(
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.8),
                ),
                children: [
                   TextSpan(
                     text: '$labelText: ',
                     style: const TextStyle(fontWeight: FontWeight.bold),
                   ),
                   TextSpan(
                     text: target,
                     style: const TextStyle(fontStyle: FontStyle.italic),
                   ),
                ],
              ),
            ),
          ),
          if (!isCompleted) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
