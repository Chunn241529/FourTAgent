import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

class FileActionIndicator extends StatelessWidget {
  final String action;
  final String target;
  final bool isCompleted;

  const FileActionIndicator({
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
    String actionText;
    Color color;

    switch (action.toLowerCase()) {
      case 'read':
        icon = Icons.file_open_outlined;
        actionText = 'Đang đọc tệp tin';
        color = Colors.blue;
        break;
      case 'search':
        icon = Icons.search;
        actionText = 'Đang tìm kiếm tệp tin';
        color = Colors.orange;
        break;
      case 'create':
        icon = Icons.create_new_folder_outlined;
        actionText = 'Đang tạo tệp tin';
        color = Colors.green;
        break;
      default:
        icon = Icons.security;
        actionText = 'Đang thực hiện: ${action.toUpperCase()}';
        color = Colors.grey;
    }

    return InkWell(
      onTap: () async {
        if (target.isNotEmpty && !target.contains('*')) {
            try {
               await OpenFilex.open(target);
            } catch (e) {
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text('Không thể mở file: $target')),
               );
            }
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        actionText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      if (!isCompleted) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ] else ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.check_circle, size: 14, color: Colors.green),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    target,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
