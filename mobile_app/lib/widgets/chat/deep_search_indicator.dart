import 'package:flutter/material.dart';

/// Premium widget to show Deep Search progress timeline
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Current statuses from DeepSearchService:
    // planning, searching, reflecting, synthesizing

    final updates = [...widget.completedSteps, ...widget.activeSteps];
    if (updates.isEmpty) return const SizedBox.shrink();

    final lastStatus = updates.last.toLowerCase();
    
    int currentStage = 0;
    if (lastStatus.contains('planning') || lastStatus.contains('chiến lược')) {
      currentStage = 0;
    } else if (lastStatus.contains('searching') || lastStatus.contains('tìm kiếm') || lastStatus.contains('researching')) {
      currentStage = 1;
    } else if (lastStatus.contains('reflecting') || lastStatus.contains('analyzing') || lastStatus.contains('kiểm chứng') || lastStatus.contains('chi tiết')) {
      currentStage = 2;
    } else if (lastStatus.contains('synthesizing') || lastStatus.contains('tổng hợp')) {
      currentStage = 3;
    } else if (lastStatus.contains('done')) {
      currentStage = 4;
    }

    // If fully done, we might want to hide or show "Research Complete"
    if (currentStage == 4 && widget.activeSteps.isEmpty) {
       return _buildCompletedHeader(context);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.biotech_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Deep Research',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              const Spacer(),
              if (widget.activeSteps.isNotEmpty)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.secondary.withOpacity(0.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _buildTimeline(context, currentStage),
          const SizedBox(height: 12),
          Text(
            updates.last,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedHeader(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 14, color: Colors.green),
          const SizedBox(width: 6),
          Text(
            'Nghiên cứu hoàn tất',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.green.shade700,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(BuildContext context, int currentStage) {
    return Row(
      children: [
        _buildNode(context, 0, Icons.lightbulb_outline, 'Chiến lược', currentStage),
        _buildConnector(context, 0, currentStage),
        _buildNode(context, 1, Icons.travel_explore, 'Tìm kiếm', currentStage),
        _buildConnector(context, 1, currentStage),
        _buildNode(context, 2, Icons.fact_check_outlined, 'Kiểm chứng', currentStage),
        _buildConnector(context, 2, currentStage),
        _buildNode(context, 3, Icons.auto_stories_outlined, 'Tổng hợp', currentStage),
      ],
    );
  }

  Widget _buildNode(BuildContext context, int stage, IconData icon, String label, int currentStage) {
    bool isCompleted = currentStage > stage;
    bool isActive = currentStage == stage;
    final theme = Theme.of(context);

    return Expanded(
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isCompleted
                  ? theme.colorScheme.secondary
                  : isActive
                      ? theme.colorScheme.secondaryContainer
                      : theme.colorScheme.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive || isCompleted
                    ? theme.colorScheme.secondary
                    : theme.colorScheme.outline.withOpacity(0.2),
                width: 2,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: theme.colorScheme.secondary.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 2,
                      )
                    ]
                  : null,
            ),
            child: Icon(
              isCompleted ? Icons.check : icon,
              size: 18,
              color: isCompleted
                  ? theme.colorScheme.onSecondary
                  : isActive
                      ? theme.colorScheme.secondary
                      : theme.colorScheme.onSurface.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive || isCompleted
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurface.withOpacity(0.4),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildConnector(BuildContext context, int stage, int currentStage) {
    bool isCompleted = currentStage > stage;
    bool isActive = currentStage == stage;
    final theme = Theme.of(context);

    return Container(
      width: 20,
      height: 2,
      margin: const EdgeInsets.only(bottom: 16), // Align with nodes
      color: isCompleted
          ? theme.colorScheme.secondary
          : theme.colorScheme.outline.withOpacity(0.2),
    );
  }
}
