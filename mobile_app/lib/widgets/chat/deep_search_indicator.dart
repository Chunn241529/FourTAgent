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
  final String? planContent;
  final dynamic content;

  DeepSearchStepData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.status,
    this.searchCount = 0,
    this.sources = const [],
    this.actions = const [],
    this.isExpanded = false,
    this.planContent,
    this.content,
  });
}

enum DeepSearchStepStatus { pending, active, completed }

class DeepSearchMetadata {
  final int totalSearches;
  final Duration elapsedTime;
  final List<String> sources;
  final List<String> recentActions;

  final String? plan;

  const DeepSearchMetadata({
    this.totalSearches = 0,
    this.elapsedTime = Duration.zero,
    this.sources = const [],
    this.recentActions = const [],
    this.plan,
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
                      stops: const [0.0, 1.0],
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
        if (widget.step.actions.isNotEmpty || widget.step.searchCount > 0 || widget.step.planContent != null)
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
          // 1. Render Specific Step Content if available
          if (widget.step.content != null) ...[
             // PLANNING: List of Queries
             if (widget.step.id == 'planning' && widget.step.content is List)
               ..._buildQueriesList(theme, widget.step.content),
             
             // SEARCHING: List of Results
             if (widget.step.id == 'searching' && widget.step.content is List)
               ..._buildResultsList(theme, widget.step.content),
               
             // REFLECTING: List of Sources
             if (widget.step.id == 'reflecting' && widget.step.content is List)
               ..._buildSourcesList(theme, widget.step.content),
             
             // PLANNING CREATE: Markdown Plan (handled mostly by planContent but checking data too)
             if (widget.step.id == 'planning_create' && widget.step.content is String)
                _buildPlanText(theme, widget.step.content),
                
             const SizedBox(height: 12),
          ],

          // 2. Existing fallback rendering (Plan, Actions, Sources from Metadata)
          if (widget.step.planContent != null && widget.step.content == null) ...[
             _buildPlanText(theme, widget.step.planContent!),
             const SizedBox(height: 12),
          ],
          
          if (widget.step.searchCount > 0 && widget.step.id == 'searching' && widget.step.content == null) ...[
            _buildInfoRow(
              theme,
              Icons.search_rounded,
              '${widget.step.searchCount} truy vấn', // Changed text to be shorter
              widget.config.primaryColor,
            ),
            const SizedBox(height: 8),
          ],
          
          if (widget.step.actions.isNotEmpty && widget.step.content == null) ...[
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
             const SizedBox(height: 8),
          ],
          
          if (widget.step.sources.isNotEmpty && widget.step.content == null) ...[
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
                .map((source) => _buildSourceItem(theme, source)),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanText(ThemeData theme, String text) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RESEARCH PLAN',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.config.backgroundColor.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.config.primaryColor.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  height: 1.4,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
      );
  }

  List<Widget> _buildQueriesList(ThemeData theme, List dynamicList) {
      final list = dynamicList.cast<String>();
      return [
          Text(
              'Truy vấn tìm kiếm',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
          ...list.map((q) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
              ),
              child: Row(
                  children: [
                      Icon(Icons.search, size: 14, color: widget.config.primaryColor),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              q, 
                              style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                          ),
                      ),
                  ],
              ),
          )),
      ];
  }

  List<Widget> _buildResultsList(ThemeData theme, List dynamicList) {
      return [
           Text(
              'Kết quả tìm kiếm (${dynamicList.length})',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...dynamicList.take(5).map((item) {
                final map = Map<String, dynamic>.from(item);
                final title = map['title'] ?? 'Unknown';
                final url = map['url'] ?? '#';
                return _buildResultCard(theme, title, url);
            }),
             if (dynamicList.length > 5)
                Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                        '+ ${dynamicList.length - 5} kết quả khác',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                    ),
                ),
      ];
  }
  
  List<Widget> _buildSourcesList(ThemeData theme, List dynamicList) {
      return [
           Text(
              'Nguồn đã kiểm chứng (${dynamicList.length})',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...dynamicList.map((item) {
                final map = Map<String, dynamic>.from(item);
                final title = map['title'] ?? 'Unknown';
                final url = map['url'] ?? '#';
                return _buildResultCard(theme, title, url, isVerified: true);
            }),
      ];
  }

  Widget _buildResultCard(ThemeData theme, String title, String url, {bool isVerified = false}) {
      return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: isVerified ? Colors.green.withValues(alpha: 0.05) : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: isVerified ? Colors.green.withValues(alpha: 0.3) : theme.colorScheme.outline.withValues(alpha: 0.1)
              ),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  Row(
                      children: [
                          Icon(
                              isVerified ? Icons.verified_user_outlined : Icons.public, 
                              size: 14, 
                              color: isVerified ? Colors.green : theme.colorScheme.primary
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(
                                  title,
                                  style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                              ),
                          ),
                      ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                      url,
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          decoration: TextDecoration.underline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                  ),
              ],
          ),
      );
  }

  Widget _buildSourceItem(ThemeData theme, String source) {
      return Padding(
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
      );
  }
}

class DeepSearchIndicator extends StatefulWidget {
  final List<String> activeSteps;
  final List<String> completedSteps;
  final DeepSearchType searchType;
  final DeepSearchMetadata? metadata;
  final Map<String, dynamic>? deepSearchData;

  const DeepSearchIndicator({
    super.key,
    required this.activeSteps,
    required this.completedSteps,
    this.searchType = DeepSearchType.general,
    this.metadata,
    this.deepSearchData,
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

    // Fix: Determine stage by scanning ALL updates to find the highest stage reached.
    // This prevents backward jumps if a later status update is generic or unmapped.
    int maxStage = 0;
    bool reflectedSoFar = false;

    for (final update in updates) {
      final s = update.toLowerCase();
      // Check if this specific update is a reflection step
      if (s.contains('reflecting') || 
          s.contains('kiểm chứng') || 
          s.contains('analyzing')) {
        reflectedSoFar = true;
      }
      
      final stage = _parseStage(s, reflectedSoFar);
      if (stage > maxStage) {
        maxStage = stage;
      }
    }
    
    final currentStage = maxStage;
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
    // Removed timer per user request
    final showSearches = meta.totalSearches > 0;
    final showSources = meta.sources.isNotEmpty;

    if (!showSearches && !showSources)
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
            if (showSearches && showSources) _buildDivider(theme),
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



  Widget _buildSteps(
    DeepSearchConfig config,
    int currentStage,
    bool isCompleted,
  ) {
    // Helper to get content safely
    dynamic getContent(String step, String type) {
        if (widget.deepSearchData != null && widget.deepSearchData!.containsKey(step)) {
            return widget.deepSearchData![step][type];
        }
        return null;
    }

    final correctSteps = [
      DeepSearchStepData(
        id: 'planning',
        title: 'Chiến lược',
        subtitle: 'Xác định truy vấn tìm kiếm',
        icon: Icons.analytics_outlined,
        status: _getStepStatus(0, currentStage, isCompleted),
        isExpanded: _expandedSteps.contains('planning'),
        content: getContent('planning', 'queries'),
      ),
       DeepSearchStepData(
        id: 'searching',
        title: 'Tìm kiếm',
        subtitle: 'Quét dữ liệu từ internet',
        icon: Icons.travel_explore,
        status: _getStepStatus(1, currentStage, isCompleted),
        content: getContent('searching', 'results'),
        isExpanded: _expandedSteps.contains('searching'),
        searchCount: widget.metadata?.totalSearches ?? 0,
        actions: widget.metadata?.recentActions ?? [],
      ),
       DeepSearchStepData(
        id: 'reflecting',
        title: 'Đánh giá',
        subtitle: 'Lọc & Kiểm chứng nguồn tin',
        icon: Icons.fact_check_outlined,
        status: _getStepStatus(2, currentStage, isCompleted),
        content: getContent('reflecting', 'sources'),
        isExpanded: _expandedSteps.contains('reflecting'),
        sources: widget.metadata?.sources ?? [],
      ),
       DeepSearchStepData(
        id: 'planning_create',
        title: 'Tổng kết',
        subtitle: 'Tổng hợp thông tin',
        icon: Icons.format_list_bulleted,
        status: _getStepStatus(3, currentStage, isCompleted),
        planContent: widget.metadata?.plan,
        content: getContent('planning_create', 'plan'),
        isExpanded: _expandedSteps.contains('planning_create'),
      ),
      //  DeepSearchStepData(
      //   id: 'synthesizing',
      //   title: 'Tổng hợp',
      //   subtitle: 'Hoàn thiện nội dung',
      //   icon: Icons.auto_stories_outlined,
      //   status: _getStepStatus(4, currentStage, isCompleted),
      //   isExpanded: _expandedSteps.contains('synthesizing'),
      // ),
    ];

    return Column(
      children: correctSteps
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

  int _parseStage(String status, bool hasReflected) {
    if (status.contains('planning') &&
        !status.contains('search') &&
        !status.contains('lập kế hoạch')) {
       // Planning -> 0
      if (hasReflected) return 4;
      return 0;
    } else if (status.contains('searching') ||
        status.contains('tìm kiếm') ||
        status.contains('researching') || 
        status.contains('gathering')) {
       // Searching -> 1
      return 1;
    } else if (status.contains('reflecting') ||
        status.contains('analyzing') ||
        status.contains('kiểm chứng') ||
        status.contains('chi tiết')) {
       // Reflecting -> 2
      return 2;
    } else if (status.contains('lập kế hoạch') ||
        status.contains('create plan') || 
        status.contains('planning_create')) {
       // Create Plan -> 3
      return 3;
    } else if (status.contains('synthesizing') ||
        status.contains('tổng hợp')) {
       // Synthesizing -> 4
      return 4;
    } else if (status.contains('done') || status.contains('complete')) {
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
