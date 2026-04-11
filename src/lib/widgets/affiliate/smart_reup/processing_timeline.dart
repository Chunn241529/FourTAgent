import 'package:flutter/material.dart';
import '../../../screens/affiliate/theme/affiliate_theme.dart';

class ProcessingTimeline extends StatelessWidget {
  final Map<String, dynamic>? jobStatus;
  final List<Map<String, dynamic>> stages;
  final int activeIndex;
  final String activeJobId;

  const ProcessingTimeline({
    super.key,
    required this.jobStatus,
    required this.stages,
    required this.activeIndex,
    required this.activeJobId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDone = jobStatus?['status'] == 'done';
    final progress = (jobStatus?['progress'] ?? 0) / 100.0;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: AffiliateTheme.cardDecoration(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildProgressHeader(context, progress, isDone),
          const SizedBox(height: 48),
          _buildTimeline(context),
          const SizedBox(height: 32),
          Text(
            'Job ID: $activeJobId',
            style: theme.textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressHeader(BuildContext context, double progress, bool isDone) {
    final theme = Theme.of(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 10,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
            color: isDone ? Colors.green : theme.colorScheme.primary,
            strokeCap: StrokeCap.round,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${(progress * 100).toInt()}%',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: isDone ? Colors.green : theme.colorScheme.primary,
              ),
            ),
            Text(
              isDone ? 'Finished' : 'Processing',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeline(BuildContext context) {
    return Column(
      children: List.generate(stages.length, (index) {
        final isCompleted = activeIndex > index || jobStatus?['progress'] == 100;
        final isActive = activeIndex == index && jobStatus?['progress'] != 100;

        return _TimelineItem(
          label: stages[index]['label'] as String,
          icon: stages[index]['icon'] as IconData,
          isCompleted: isCompleted,
          isActive: isActive,
          isLast: index == stages.length - 1,
        );
      }),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isCompleted;
  final bool isActive;
  final bool isLast;

  const _TimelineItem({
    required this.label,
    required this.icon,
    required this.isCompleted,
    required this.isActive,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isCompleted ? Colors.green : (isActive ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.1));

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: isCompleted
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Icon(icon, size: 12, color: isActive ? Colors.white : theme.iconTheme.color?.withOpacity(0.3)),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: color.withOpacity(0.2),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? color : theme.textTheme.bodyMedium?.color?.withOpacity(isCompleted ? 0.8 : 0.4),
              ),
            ),
          ),
          if (isActive) ...[
            const SizedBox(width: 12),
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }
}
