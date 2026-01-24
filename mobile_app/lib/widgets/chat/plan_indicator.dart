import 'package:flutter/material.dart';

/// A collapsible widget to display the Deep Search research plan.
/// Mirrors the design of _ThinkingIndicator.
class PlanIndicator extends StatefulWidget {
  final String plan;
  final bool isStreaming;

  const PlanIndicator({
    super.key,
    required this.plan,
    required this.isStreaming,
  });

  @override
  State<PlanIndicator> createState() => _PlanIndicatorState();
}

class _PlanIndicatorState extends State<PlanIndicator> {
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    // Auto-expand when plan first arrives
    if (widget.plan.isNotEmpty) {
      _isExpanded = true;
    }
  }

  @override
  void didUpdateWidget(PlanIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-collapse when streaming finishes
    if (oldWidget.isStreaming && !widget.isStreaming) {
      setState(() {
        _isExpanded = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.plan.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  size: 16,
                  color: theme.colorScheme.primary.withOpacity(0.8),
                ),
                const SizedBox(width: 4),
                Text(
                  '📋 Research Plan',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded)
          Container(
            padding: const EdgeInsets.only(left: 12, top: 4, bottom: 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: theme.colorScheme.primary.withOpacity(0.3),
                  width: 2,
                ),
              ),
            ),
            child: Text(
              widget.plan,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.8),
                height: 1.5,
              ),
            ),
          ),
      ],
    );
  }
}
