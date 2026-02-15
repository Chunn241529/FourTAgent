import 'package:flutter/material.dart';

enum DeepSearchType { research, analysis, creative, general }

class DeepSearchConfig {
  final Color primaryColor;
  final Color secondaryColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final IconData icon;
  final String label;
  final List<Color> gradientColors;

  const DeepSearchConfig({
    required this.primaryColor,
    required this.secondaryColor,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.icon,
    required this.label,
    required this.gradientColors,
  });

  static DeepSearchConfig fromType(DeepSearchType type, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    switch (type) {
      case DeepSearchType.research:
        return DeepSearchConfig(
          primaryColor: isDark
              ? const Color(0xFF60A5FA)
              : const Color(0xFF2563EB),
          secondaryColor: isDark
              ? const Color(0xFF93C5FD)
              : const Color(0xFF3B82F6),
          backgroundColor: isDark
              ? const Color(0xFF1E3A5F)
              : const Color(0xFFDBEAFE),
          surfaceColor: isDark
              ? const Color(0xFF172554)
              : const Color(0xFFEFF6FF),
          icon: Icons.science_outlined,
          label: 'Nghiên cứu',
          gradientColors: [const Color(0xFF2563EB), const Color(0xFF3B82F6)],
        );
      case DeepSearchType.analysis:
        return DeepSearchConfig(
          primaryColor: isDark
              ? const Color(0xFFC084FC)
              : const Color(0xFF9333EA),
          secondaryColor: isDark
              ? const Color(0xFFE9D5FF)
              : const Color(0xFFA855F7),
          backgroundColor: isDark
              ? const Color(0xFF3B0764)
              : const Color(0xFFF3E8FF),
          surfaceColor: isDark
              ? const Color(0xFF1E0338)
              : const Color(0xFFFAF5FF),
          icon: Icons.analytics_outlined,
          label: 'Phân tích',
          gradientColors: [const Color(0xFF9333EA), const Color(0xFFA855F7)],
        );
      case DeepSearchType.creative:
        return DeepSearchConfig(
          primaryColor: isDark
              ? const Color(0xFFFB923C)
              : const Color(0xFFEA580C),
          secondaryColor: isDark
              ? const Color(0xFFFED7AA)
              : const Color(0xFFF97316),
          backgroundColor: isDark
              ? const Color(0xFF431407)
              : const Color(0xFFFEF3C7),
          surfaceColor: isDark
              ? const Color(0xFF290D0A)
              : const Color(0xFFFFFBEB),
          icon: Icons.auto_awesome_outlined,
          label: 'Sáng tạo',
          gradientColors: [const Color(0xFFEA580C), const Color(0xFFF97316)],
        );
      case DeepSearchType.general:
      default:
        return DeepSearchConfig(
          primaryColor: isDark
              ? const Color(0xFF4ADE80)
              : const Color(0xFF16A34A),
          secondaryColor: isDark
              ? const Color(0xFF86EFAC)
              : const Color(0xFF22C55E),
          backgroundColor: isDark
              ? const Color(0xFF052E16)
              : const Color(0xFFDCFCE7),
          surfaceColor: isDark
              ? const Color(0xFF022C22)
              : const Color(0xFFF0FDF4),
          icon: Icons.psychology_outlined,
          label: 'Deep Search',
          gradientColors: [const Color(0xFF16A34A), const Color(0xFF22C55E)],
        );
    }
  }
}

class DeepSearchStepData {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final DeepSearchStepStatus status;
  final int searchCount;
  final List<String> sources;
  final List<String> actions;
  final bool isExpanded;

  const DeepSearchStepData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.status,
    this.searchCount = 0,
    this.sources = const [],
    this.actions = const [],
    this.isExpanded = false,
  });
}

enum DeepSearchStepStatus { pending, active, completed }

class DeepSearchMetadata {
  final int totalSearches;
  final Duration elapsedTime;
  final List<String> sources;
  final List<String> recentActions;

  const DeepSearchMetadata({
    this.totalSearches = 0,
    this.elapsedTime = Duration.zero,
    this.sources = const [],
    this.recentActions = const [],
  });
}

class PulsingDot extends StatefulWidget {
  final Color color;
  final double size;

  const PulsingDot({super.key, required this.color, this.size = 12});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: _animation.value),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.4 * _animation.value),
                blurRadius: widget.size * _animation.value,
                spreadRadius: widget.size * 0.2 * _animation.value,
              ),
            ],
          ),
        );
      },
    );
  }
}

class DeepSearchStepCard extends StatefulWidget {
  final DeepSearchStepData step;
  final bool isFirst;
  final bool isLast;
  final DeepSearchConfig config;
  final VoidCallback? onTap;

  const DeepSearchStepCard({
    super.key,
    required this.step,
    required this.isFirst,
    required this.isLast,
    required this.config,
    this.onTap,
  });

  @override
  State<DeepSearchStepCard> createState() => _DeepSearchStepCardState();
}

class _DeepSearchStepCardState extends State<DeepSearchStepCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  late Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );
    _rotateAnimation = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(parent: _expandController, curve: Curves.easeInOut),
    );

    if (widget.step.isExpanded) {
      _expandController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(DeepSearchStepCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.step.isExpanded != oldWidget.step.isExpanded) {
      if (widget.step.isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompleted = widget.step.status == DeepSearchStepStatus.completed;
    final isActive = widget.step.status == DeepSearchStepStatus.active;

    return GestureDetector(
      onTap: widget.onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTimelineIndicator(theme, isCompleted, isActive),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: EdgeInsets.all(isActive ? 16 : 14),
              decoration: BoxDecoration(
                color: isActive
                    ? widget.config.surfaceColor
                    : theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.3,
                      ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isActive
                      ? widget.config.primaryColor.withValues(alpha: 0.3)
                      : theme.colorScheme.outline.withValues(alpha: 0.1),
                  width: isActive ? 1.5 : 1,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: widget.config.primaryColor.withValues(
                            alpha: 0.1,
                          ),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(theme, isCompleted, isActive),
                  if (isActive || widget.step.isExpanded)
                    SizeTransition(
                      sizeFactor: _expandAnimation,
                      child: _buildExpandedContent(theme),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineIndicator(
    ThemeData theme,
    bool isCompleted,
    bool isActive,
  ) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: isActive ? 48 : 40,
          height: isActive ? 48 : 40,
          decoration: BoxDecoration(
            gradient: isCompleted
                ? LinearGradient(
                    colors: widget.config.gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isCompleted
                ? null
                : isActive
                ? widget.config.backgroundColor
                : theme.colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
            border: Border.all(
              color: isCompleted || isActive
                  ? widget.config.primaryColor
                  : theme.colorScheme.outline.withValues(alpha: 0.2),
              width: isActive ? 2.5 : 2,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: widget.config.primaryColor.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: isCompleted
                ? Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: isActive ? 24 : 20,
                  )
                : isActive
                ? PulsingDot(color: widget.config.primaryColor, size: 14)
                : Icon(
                    widget.step.icon,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    size: 18,
                  ),
          ),
        ),
        if (!widget.isLast)
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 3,
            height: 60,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              gradient: isCompleted
                  ? LinearGradient(
                      colors: [
                        widget.config.primaryColor,
                        widget.config.secondaryColor,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    )
                  : null,
              color: isCompleted
                  ? null
                  : theme.colorScheme.outline.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme, bool isCompleted, bool isActive) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.step.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isCompleted || isActive
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.step.subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (widget.step.actions.isNotEmpty || widget.step.searchCount > 0)
          RotationTransition(
            turns: _rotateAnimation,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: widget.config.primaryColor,
              size: 24,
            ),
          ),
      ],
    );
  }

  Widget _buildExpandedContent(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.step.searchCount > 0) ...[
            _buildInfoRow(
              theme,
              Icons.search_rounded,
              '${widget.step.searchCount} truy vấn',
              widget.config.primaryColor,
            ),
            const SizedBox(height: 8),
          ],
          if (widget.step.actions.isNotEmpty) ...[
            Text(
              'Hành động',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.step.actions.map((action) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: widget.config.backgroundColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    action,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: widget.config.primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (widget.step.sources.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Nguồn tham khảo',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            ...widget.step.sources
                .take(3)
                .map(
                  (source) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.link_rounded,
                          size: 14,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            source,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    ThemeData theme,
    IconData icon,
    String text,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class DeepSearchIndicator extends StatefulWidget {
  final List<String> activeSteps;
  final List<String> completedSteps;
  final DeepSearchType searchType;
  final DeepSearchMetadata? metadata;

  const DeepSearchIndicator({
    super.key,
    required this.activeSteps,
    required this.completedSteps,
    this.searchType = DeepSearchType.general,
    this.metadata,
  });

  @override
  State<DeepSearchIndicator> createState() => _DeepSearchIndicatorState();
}

class _DeepSearchIndicatorState extends State<DeepSearchIndicator> {
  final List<String> _expandedSteps = [];

  void _toggleStep(String stepId) {
    setState(() {
      if (_expandedSteps.contains(stepId)) {
        _expandedSteps.remove(stepId);
      } else {
        _expandedSteps.add(stepId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final config = DeepSearchConfig.fromType(widget.searchType, brightness);

    final updates = [...widget.completedSteps, ...widget.activeSteps];
    if (updates.isEmpty) return const SizedBox.shrink();

    final lastStatus = updates.last.toLowerCase();
    final currentStage = _getCurrentStage(lastStatus);
    final isStreaming = widget.activeSteps.isNotEmpty;
    final isCompleted =
        currentStage >= 5 ||
        (!isStreaming && currentStage >= 0 && updates.isNotEmpty);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            config.surfaceColor,
            config.surfaceColor.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: config.primaryColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: config.primaryColor.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(theme, config, isCompleted, isStreaming),
          if (widget.metadata != null) _buildMetadataBar(theme, config),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _buildSteps(config, currentStage, isCompleted),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    DeepSearchConfig config,
    bool isCompleted,
    bool isStreaming,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            config.primaryColor.withValues(alpha: 0.1),
            config.primaryColor.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: config.gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: config.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(config.icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: config.primaryColor,
                  ),
                ),
                Text(
                  isCompleted ? 'Hoàn tất' : 'Đang xử lý...',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          if (!isCompleted)
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  config.primaryColor.withValues(alpha: 0.8),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.green,
                size: 16,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetadataBar(ThemeData theme, DeepSearchConfig config) {
    final meta = widget.metadata!;
    final showTime = meta.elapsedTime.inSeconds > 0;
    final showSearches = meta.totalSearches > 0;
    final showSources = meta.sources.isNotEmpty;

    if (!showTime && !showSearches && !showSources)
      return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            if (showSearches)
              Expanded(
                child: _buildMetaItem(
                  theme,
                  Icons.search_rounded,
                  '${meta.totalSearches}',
                  'Tìm kiếm',
                  config.primaryColor,
                ),
              ),
            if (showSearches && showTime) _buildDivider(theme),
            if (showTime)
              Expanded(
                child: _buildMetaItem(
                  theme,
                  Icons.timer_outlined,
                  _formatDuration(meta.elapsedTime),
                  'Thời gian',
                  config.secondaryColor,
                ),
              ),
            if (showTime && showSources) _buildDivider(theme),
            if (showSources)
              Expanded(
                child: _buildMetaItem(
                  theme,
                  Icons.source_outlined,
                  '${meta.sources.length}',
                  'Nguồn',
                  config.primaryColor,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaItem(
    ThemeData theme,
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: theme.colorScheme.outline.withValues(alpha: 0.1),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0)
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    if (duration.inMinutes > 0)
      return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    return '${duration.inSeconds}s';
  }

  Widget _buildSteps(
    DeepSearchConfig config,
    int currentStage,
    bool isCompleted,
  ) {
    final steps = [
      DeepSearchStepData(
        id: 'planning',
        title: 'Phân tích',
        subtitle: 'Phân tích yêu cầu',
        icon: Icons.analytics_outlined,
        status: _getStepStatus(0, currentStage, isCompleted),
        isExpanded: _expandedSteps.contains('planning'),
      ),
      DeepSearchStepData(
        id: 'planning_create',
        title: 'Lập kế hoạch',
        subtitle: 'Xây dựng chiến lược tìm kiếm',
        icon: Icons.lightbulb_outline,
        status: _getStepStatus(1, currentStage, isCompleted),
        isExpanded: _expandedSteps.contains('planning_create'),
      ),
      DeepSearchStepData(
        id: 'searching',
        title: 'Tìm kiếm',
        subtitle: 'Thu thập thông tin',
        icon: Icons.travel_explore,
        status: _getStepStatus(2, currentStage, isCompleted),
        searchCount: widget.metadata?.totalSearches ?? 0,
        actions: widget.metadata?.recentActions ?? [],
        sources: widget.metadata?.sources ?? [],
        isExpanded: _expandedSteps.contains('searching'),
      ),
      DeepSearchStepData(
        id: 'reflecting',
        title: 'Kiểm chứng',
        subtitle: 'Xác minh thông tin',
        icon: Icons.fact_check_outlined,
        status: _getStepStatus(3, currentStage, isCompleted),
        isExpanded: _expandedSteps.contains('reflecting'),
      ),
      DeepSearchStepData(
        id: 'synthesizing',
        title: 'Tổng hợp',
        subtitle: 'Tạo kết quả cuối cùng',
        icon: Icons.auto_stories_outlined,
        status: _getStepStatus(4, currentStage, isCompleted),
        isExpanded: _expandedSteps.contains('synthesizing'),
      ),
    ];

    return Column(
      children: steps
          .map(
            (step) => DeepSearchStepCard(
              key: ValueKey(step.id),
              step: step,
              isFirst: step.id == 'planning',
              isLast: step.id == 'synthesizing',
              config: config,
              onTap: () => _toggleStep(step.id),
            ),
          )
          .toList(),
    );
  }

  int _getCurrentStage(String lastStatus) {
    if (lastStatus.contains('planning') &&
        !lastStatus.contains('search') &&
        !lastStatus.contains('lập kế hoạch')) {
      return 0;
    } else if (lastStatus.contains('lập kế hoạch') ||
        lastStatus.contains('create plan')) {
      return 1;
    } else if (lastStatus.contains('searching') ||
        lastStatus.contains('tìm kiếm') ||
        lastStatus.contains('researching')) {
      return 2;
    } else if (lastStatus.contains('reflecting') ||
        lastStatus.contains('analyzing') ||
        lastStatus.contains('kiểm chứng') ||
        lastStatus.contains('chi tiết')) {
      return 3;
    } else if (lastStatus.contains('synthesizing') ||
        lastStatus.contains('tổng hợp')) {
      return 4;
    } else if (lastStatus.contains('done') || lastStatus.contains('complete')) {
      return 5;
    }
    return -1;
  }

  DeepSearchStepStatus _getStepStatus(
    int stepIndex,
    int currentStage,
    bool isCompleted,
  ) {
    if (isCompleted || currentStage > stepIndex)
      return DeepSearchStepStatus.completed;
    if (currentStage == stepIndex) return DeepSearchStepStatus.active;
    return DeepSearchStepStatus.pending;
  }
}
