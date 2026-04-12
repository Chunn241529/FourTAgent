import 'package:flutter/material.dart';

/// Simple widget to show fetched URLs (no success/fail state)
class WebFetchIndicator extends StatelessWidget {
  final List<String> urls;

  const WebFetchIndicator({
    super.key,
    required this.urls,
    // Keep old params for backward compat but ignore them
    List<String>? activeFetches,
    List<String>? completedFetches,
    List<String>? failedFetches,
  });

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: urls.map((url) => _buildFetchItem(theme, isDark, url)).toList(),
    );
  }

  Widget _buildFetchItem(ThemeData theme, bool isDark, String url) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.language,
            size: 13,
            color: theme.colorScheme.primary.withOpacity(0.8),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _truncateUrl(url),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.75),
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _truncateUrl(String url) {
    String display = url.replaceFirst(RegExp(r'https?://'), '').replaceFirst(RegExp(r'www\.'), '');
    if (display.length > 50) {
      return '${display.substring(0, 50)}...';
    }
    return display;
  }
}
