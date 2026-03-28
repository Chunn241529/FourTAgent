import 'dart:ui';
import 'package:flutter/material.dart';

class DockItem {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final VoidCallback onTap;
  final bool isSelected;
  final Color? color;

  const DockItem({
    required this.icon,
    this.selectedIcon,
    required this.label,
    required this.onTap,
    this.isSelected = false,
    this.color,
  });
}

class MacDock extends StatefulWidget {
  final List<DockItem> items;
  final List<DockItem> actionItems;

  const MacDock({
    super.key,
    required this.items,
    required this.actionItems,
  });

  @override
  State<MacDock> createState() => _MacDockState();
}

class _MacDockState extends State<MacDock> with TickerProviderStateMixin {
  bool _isExpanded = true;
  int? _hoveredIndex;
  String? _tooltipLabel;

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: 1.0, // start expanded
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.2), // slide down off-screen
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    _fadeAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _slideController.forward();
      } else {
        _slideController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Tooltip floating above dock ──
          if (_tooltipLabel != null)
            AnimatedOpacity(
              opacity: _tooltipLabel != null ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.12)
                      : Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _tooltipLabel!,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

          // ── Dock bar ──
          SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: _buildDockBar(theme, isDark),
            ),
          ),

          // ── Collapsed pill trigger ──
          if (!_isExpanded)
            GestureDetector(
              onTap: _toggleExpanded,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.25)
                      : Colors.black.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDockBar(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1C1C1E).withOpacity(0.85)
                : Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.5 : 0.12),
                blurRadius: 32,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                blurRadius: 8,
                spreadRadius: 0,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Main nav items ──
                  ...widget.items.asMap().entries.map((entry) =>
                      _buildDockIcon(entry.value, theme, isDark, entry.key)),

                  // ── Divider ──
                  _buildDivider(isDark),

                  // ── Action items ──
                  ...widget.actionItems.asMap().entries.map((entry) =>
                      _buildDockIcon(
                          entry.value, theme, isDark, entry.key + 100)),

                  // ── Divider ──
                  _buildDivider(isDark),

                  // ── Collapse button ──
                  _buildDockIcon(
                    DockItem(
                      icon: Icons.keyboard_arrow_down_rounded,
                      label: 'Thu nhỏ Dock',
                      onTap: _toggleExpanded,
                    ),
                    theme,
                    isDark,
                    -1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: isDark
          ? Colors.white.withOpacity(0.08)
          : Colors.black.withOpacity(0.08),
    );
  }

  Widget _buildDockIcon(
      DockItem item, ThemeData theme, bool isDark, int index) {
    final bool isHovered = _hoveredIndex == index;
    final bool isSelected = item.isSelected;
    final iconData =
        isSelected && item.selectedIcon != null ? item.selectedIcon! : item.icon;

    final Color iconColor;
    if (isSelected) {
      iconColor = theme.colorScheme.primary;
    } else if (item.color != null) {
      iconColor = item.color!;
    } else {
      iconColor = isDark
          ? Colors.white.withOpacity(0.6)
          : Colors.black.withOpacity(0.55);
    }

    return MouseRegion(
      onEnter: (_) => setState(() {
        _hoveredIndex = index;
        _tooltipLabel = item.label;
      }),
      onExit: (_) => setState(() {
        _hoveredIndex = null;
        _tooltipLabel = null;
      }),
      child: GestureDetector(
        onTap: item.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: 44,
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          // slight upward translation on hover
          transform: Matrix4.translationValues(
              0, isHovered ? -6 : 0, 0),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primary.withOpacity(isDark ? 0.15 : 0.10)
                : (isHovered
                    ? (isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.black.withOpacity(0.05))
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: isHovered ? 1.2 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                child: Icon(iconData, size: 22, color: iconColor),
              ),
              // Selection dot
              if (isSelected)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
