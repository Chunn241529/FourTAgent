import 'package:flutter/material.dart';

/// Widget to show active and completed web searches
class SearchIndicator extends StatefulWidget {
  final List<String> activeSearches;
  final List<String> completedSearches;

  const SearchIndicator({
    super.key,
    required this.activeSearches,
    required this.completedSearches,
  });

  @override
  State<SearchIndicator> createState() => _SearchIndicatorState();
}

class _SearchIndicatorState extends State<SearchIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSearches = widget.activeSearches.isNotEmpty || widget.completedSearches.isNotEmpty;
    if (!hasSearches) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Completed searches (static, with check icon)
        ...widget.completedSearches.map((query) => _buildSearchItem(
          theme: theme,
          isDark: isDark,
          query: query,
          isActive: false,
        )),
        // Active searches (with animation)
        ...widget.activeSearches.map((query) => AnimatedBuilder(
          animation: _shimmerAnimation,
          builder: (context, child) => _buildSearchItem(
            theme: theme,
            isDark: isDark,
            query: query,
            isActive: true,
            shimmerValue: _shimmerAnimation.value,
          ),
        )),
      ],
    );
  }

  Widget _buildSearchItem({
    required ThemeData theme,
    required bool isDark,
    required String query,
    required bool isActive,
    double shimmerValue = 0,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: isActive
            ? LinearGradient(
                begin: Alignment(shimmerValue - 1, 0),
                end: Alignment(shimmerValue, 0),
                colors: [
                  isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
                  isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE8E8E8),
                  isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
                ],
                stops: const [0.0, 0.5, 1.0],
              )
            : null,
        color: isActive ? null : (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive
              ? theme.colorScheme.primary.withOpacity(0.4)
              : theme.colorScheme.onSurface.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
              ),
            ),
          ] else ...[
            Icon(
              Icons.check_circle,
              size: 14,
              color: Colors.green.shade600,
            ),
          ],
          const SizedBox(width: 6),
          Icon(
            Icons.search,
            size: 13,
            color: theme.colorScheme.primary.withOpacity(0.8),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              _truncateQuery(query),
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

  String _truncateQuery(String query) {
    if (query.length > 50) {
      return '${query.substring(0, 50)}...';
    }
    return query;
  }
}
