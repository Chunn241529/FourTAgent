import 'dart:ui';
import 'package:flutter/material.dart';

/// Widget to show active and completed web searches
class SearchIndicator extends StatefulWidget {
  final List<String> activeSearches;
  final List<String> completedSearches;
  final List<String> failedSearches;

  const SearchIndicator({
    super.key,
    required this.activeSearches,
    required this.completedSearches,
    this.failedSearches = const [],
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
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
    _shimmerAnimation = Tween<double>(begin: -2.0, end: 2.0).animate(
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
    final hasSearches = widget.activeSearches.isNotEmpty || 
                        widget.completedSearches.isNotEmpty || 
                        widget.failedSearches.isNotEmpty;
    if (!hasSearches) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...widget.completedSearches.map((query) => _buildSearchItem(
          theme: theme,
          isDark: isDark,
          query: query,
          status: _ToolStatus.completed,
        )),
        ...widget.failedSearches.map((query) => _buildSearchItem(
          theme: theme,
          isDark: isDark,
          query: query,
          status: _ToolStatus.failed,
        )),
        ...widget.activeSearches.map((query) => AnimatedBuilder(
          animation: _shimmerAnimation,
          builder: (context, child) => _buildSearchItem(
            theme: theme,
            isDark: isDark,
            query: query,
            status: _ToolStatus.active,
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
    required _ToolStatus status,
    double shimmerValue = 0,
  }) {
    final isActive = status == _ToolStatus.active;
    final isFailed = status == _ToolStatus.failed;
    final isCompleted = status == _ToolStatus.completed;

    Color accentColor;
    if (isFailed) {
      accentColor = Colors.redAccent;
    } else if (isCompleted) {
      accentColor = const Color(0xFF10B981); // Emerald
    } else {
      accentColor = Colors.amber.shade700;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: isDark 
                ? Colors.white.withValues(alpha: 0.05) 
                : theme.colorScheme.primary.withValues(alpha: 0.04),
            border: Border.all(
              color: isActive
                  ? accentColor.withValues(alpha: 0.5)
                  : accentColor.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isActive) ...[
                _AnimatedSearchIcon(color: accentColor),
              ] else if (isFailed) ...[
                Icon(Icons.error_outline_rounded, size: 16, color: accentColor),
              ] else ...[
                Icon(Icons.check_circle_rounded, size: 16, color: const Color(0xFF10B981)),
              ],
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _truncateQuery(query),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _truncateQuery(String query) {
    if (query.length > 40) {
      return '${query.substring(0, 40)}...';
    }
    return query;
  }
}

class _AnimatedSearchIcon extends StatefulWidget {
  final Color color;
  const _AnimatedSearchIcon({required this.color});

  @override
  State<_AnimatedSearchIcon> createState() => _AnimatedSearchIconState();
}

class _AnimatedSearchIconState extends State<_AnimatedSearchIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.8, end: 1.1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Icon(Icons.search_rounded, size: 16, color: widget.color),
    );
  }
}

enum _ToolStatus { active, completed, failed }
