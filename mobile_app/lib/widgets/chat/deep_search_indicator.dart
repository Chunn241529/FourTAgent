import 'package:flutter/material.dart';

/// Widget to show active and completed deep search steps
class DeepSearchIndicator extends StatefulWidget {
  final List<String> activeSteps;
  final List<String> completedSteps;

  const DeepSearchIndicator({
    super.key,
    required this.activeSteps,
    required this.completedSteps,
  });

  @override
  State<DeepSearchIndicator> createState() => _DeepSearchIndicatorState();
}

class _DeepSearchIndicatorState extends State<DeepSearchIndicator>
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
    final hasSteps = widget.activeSteps.isNotEmpty || widget.completedSteps.isNotEmpty;
    if (!hasSteps) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Compact Mode: Only show the "latest/active" status.
    // If there are active steps, show the last active one.
    // If no active steps but completed ones, show "Search Complete" or the last completed one?
    // Actually, usually we show the current activity.
    
    String? currentStatus;
    bool isActive = false;
    
    if (widget.activeSteps.isNotEmpty) {
      currentStatus = widget.activeSteps.last;
      isActive = true;
    } else if (widget.completedSteps.isNotEmpty) {
      // Don't show anything if all done? Or show a checkmark?
      // User said "loại bỏ những widget thừa thải". If it's done, maybe we hide it 
      // because the content is generating?
      // But let's keep a small "Research Complete" or just hide it.
      // Let's assume we want to know what's happening.
       return const SizedBox.shrink();
    }
    
    if (currentStatus == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) => _buildStepItem(
        theme: theme,
        isDark: isDark,
        text: currentStatus!,
        isActive: isActive,
        shimmerValue: _shimmerAnimation.value,
      ),
    );
  }

  Widget _buildStepItem({
    required ThemeData theme,
    required bool isDark,
    required String text,
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
              ? theme.colorScheme.secondary.withOpacity(0.4) // Use secondary color for Deep Search
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
                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.secondary),
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
            Icons.psychology, // Brain icon for Deep Search
            size: 13,
            color: theme.colorScheme.secondary.withOpacity(0.8),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              _truncateText(text),
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

  String _truncateText(String text) {
    // Remove "status" prefixes if present for cleaner UI
    // e.g. "Starting Deep Search for: ..." -> "Starting Deep Search..."
    return text.length > 60 ? '${text.substring(0, 60)}...' : text;
  }
}
