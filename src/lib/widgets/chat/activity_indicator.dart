import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

enum ActivityType { thinking, search, tool, fetch, error, read, write, execute, image, canvas }

class ActivityItem {
  final ActivityType type;
  final String label;
  final String? detail;
  final bool isActive;
  final bool isCompleted;
  final int? elapsedSeconds;

  ActivityItem({
    required this.type,
    required this.label,
    this.detail,
    this.isActive = false,
    this.isCompleted = false,
    this.elapsedSeconds,
  });
}

class ModernActivityIndicator extends StatefulWidget {
  final List<ActivityItem> activities;
  final bool initiallyExpanded;
  final DateTime? messageTimestamp; // Added to sync timer

  const ModernActivityIndicator({
    super.key,
    required this.activities,
    this.initiallyExpanded = false,
    this.messageTimestamp,
  });

  @override
  State<ModernActivityIndicator> createState() => _ModernActivityIndicatorState();
}

class _ModernActivityIndicatorState extends State<ModernActivityIndicator>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    if (_isExpanded) {
      _expandController.value = 1.0;
    }
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.fastOutSlowIn,
    );
    _checkTimer();
  }

  void _checkTimer() {
    final hasActive = widget.activities.any((a) => a.isActive);
    if (hasActive) {
      if (_timer == null || !_timer!.isActive) {
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) setState(() {});
        });
      }
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void didUpdateWidget(ModernActivityIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkTimer();
  }

  @override
  void dispose() {
    _expandController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.activities.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMainPill(theme, isDark),
          _buildExpandedDetails(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildMainPill(ThemeData theme, bool isDark) {
    final activeActivities = widget.activities.where((a) => a.isActive).toList();
    final activeActivity = activeActivities.isNotEmpty 
        ? activeActivities.last 
        : widget.activities.last;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _toggleExpanded,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          Colors.white.withValues(alpha: 0.1),
                          Colors.white.withValues(alpha: 0.03),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.9),
                          Colors.white.withValues(alpha: 0.7),
                        ],
                ),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (activeActivities.length > 1)
                     _buildHubBadge(activeActivities.length, theme)
                  else
                     _buildAnimatedIcon(activeActivity, theme),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      activeActivities.length > 1 
                          ? 'Đang thực hiện ${activeActivities.length} tác vụ...'
                          : _getSummaryText(activeActivity),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                        fontSize: 12,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildExpandIcon(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedIcon(ActivityItem activity, ThemeData theme) {
    final color = _getActivityColor(activity.type, theme);

    if (activity.isActive) {
      if (activity.type == ActivityType.thinking) {
        return _RotatingIcon(
          icon: Icons.psychology_outlined,
          color: color,
        );
      } else if (activity.type == ActivityType.image) {
        return _PulseIcon(
          icon: Icons.auto_awesome_rounded,
          color: color,
        );
      } else {
        return _PulseIcon(
          icon: _getActivityIcon(activity.type),
          color: color,
        );
      }
    }

    return Icon(
      activity.isCompleted ? Icons.check_circle_rounded : _getActivityIcon(activity.type),
      size: 16,
      color: activity.isCompleted ? Colors.green : color,
    );
  }

  Widget _buildHubBadge(int count, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.tertiary],
        ),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt, size: 10, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            'HUB',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 9,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandIcon(ThemeData theme) {
    return AnimatedRotation(
      turns: _isExpanded ? 0.5 : 0,
      duration: const Duration(milliseconds: 300),
      child: Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 18,
        color: theme.colorScheme.onSurface.withOpacity(0.4),
      ),
    );
  }

  Widget _buildExpandedDetails(ThemeData theme, bool isDark) {
    return ClipRect(
      child: SizeTransition(
        sizeFactor: _expandAnimation,
        child: Container(
          margin: const EdgeInsets.only(top: 8, left: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                width: 2,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: widget.activities.map((activity) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSmallIcon(activity, theme),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activity.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: activity.isActive ? FontWeight.w700 : FontWeight.w500,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: activity.isActive ? 1.0 : 0.6,
                              ),
                            ),
                          ),
                          if (activity.detail != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                activity.detail!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildSmallIcon(ActivityItem activity, ThemeData theme) {
    final color = _getActivityColor(activity.type, theme);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.1),
      ),
      child: Icon(
        activity.isCompleted 
            ? Icons.check_rounded 
            : _getActivityIcon(activity.type),
        size: 12,
        color: activity.isCompleted ? Colors.green : color,
      ),
    );
  }

  int? _getElapsedSeconds(ActivityItem activity) {
    if (activity.isActive && widget.messageTimestamp != null) {
      return DateTime.now().difference(widget.messageTimestamp!).inSeconds;
    }
    return activity.elapsedSeconds;
  }

  String _getSummaryText(ActivityItem active) {
    if (active.type == ActivityType.thinking && active.isActive) {
      final seconds = _getElapsedSeconds(active);
      return 'Stella đang suy nghĩ... ${seconds ?? ""}s';
    }
    if (active.type == ActivityType.search && active.isActive) {
      return 'Đang tìm kiếm...';
    }
    if (active.type == ActivityType.fetch && active.isActive) {
      return 'Đang truy cập web...';
    }
    if (active.type == ActivityType.image && active.isActive) {
      return 'Đang tạo ảnh nghệ thuật...';
    }
    if (active.type == ActivityType.canvas && active.isActive) {
      return 'Đang khởi tạo không gian làm việc...';
    }
    if (active.isCompleted) {
      return 'Đã hoàn thành ${active.label}';
    }
    return active.label;
  }

  IconData _getActivityIcon(ActivityType type) {
    switch (type) {
      case ActivityType.thinking: return Icons.psychology_outlined;
      case ActivityType.search: return Icons.search_rounded;
      case ActivityType.tool: return Icons.handyman_outlined;
      case ActivityType.fetch: return Icons.language_rounded;
      case ActivityType.error: return Icons.error_outline_rounded;
      case ActivityType.read: return Icons.file_open_rounded;
      case ActivityType.write: return Icons.edit_note_rounded;
      case ActivityType.execute: return Icons.terminal_rounded;
      case ActivityType.image: return Icons.auto_awesome_rounded;
      case ActivityType.canvas: return Icons.art_track_rounded;
    }
  }

  Color _getActivityColor(ActivityType type, ThemeData theme) {
    switch (type) {
      case ActivityType.thinking: return Colors.indigo;
      case ActivityType.search: return Colors.amber.shade800;
      case ActivityType.tool: return Colors.blueGrey;
      case ActivityType.fetch: return Colors.blue;
      case ActivityType.error: return Colors.red;
      case ActivityType.read: return Colors.cyan.shade700;
      case ActivityType.write: return Colors.teal.shade700;
      case ActivityType.execute: return Colors.deepPurple.shade700;
      case ActivityType.image: return Colors.pink.shade400;
      case ActivityType.canvas: return Colors.blue.shade600;
    }
  }
}

class _RotatingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;

  const _RotatingIcon({required this.icon, required this.color});

  @override
  State<_RotatingIcon> createState() => _RotatingIconState();
}

class _RotatingIconState extends State<_RotatingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(widget.icon, size: 18, color: widget.color),
    );
  }
}

class _PulseIcon extends StatefulWidget {
  final IconData icon;
  final Color color;

  const _PulseIcon({required this.icon, required this.color});

  @override
  State<_PulseIcon> createState() => _PulseIconState();
}

class _PulseIconState extends State<_PulseIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.6, end: 1.0).animate(
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
    return FadeTransition(
      opacity: _animation,
      child: Icon(widget.icon, size: 18, color: widget.color),
    );
  }
}
