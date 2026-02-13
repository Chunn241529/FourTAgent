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
  Offset _position = const Offset(20, 20); // Default position
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  // Hover state for icons
  int? _hoveredIndex;
  final double _hoverScale = 1.3;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOutBack,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
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

  Axis _getOrientation(Size screenSize) {
    if (_position.dx < 100 || _position.dx > screenSize.width - 100) {
      return Axis.vertical;
    }
    return Axis.horizontal;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final theme = Theme.of(context);

    if (!_isExpanded) {
      return Positioned(
        left: _position.dx,
        top: _position.dy,
        child: _buildCollapsedTrigger(theme),
      );
    }

    final axis = _getOrientation(screenSize);
    final isLeft = _position.dx < screenSize.width / 2;
    final isTop = _position.dy < screenSize.height / 2;

    Alignment dockingAlignment;
    if (axis == Axis.vertical) {
      dockingAlignment = isLeft ? Alignment.centerLeft : Alignment.centerRight;
    } else {
      dockingAlignment = isTop ? Alignment.topCenter : Alignment.bottomCenter;
    }

    return Positioned.fill(
      child: Align(
        alignment: dockingAlignment,
        child: _buildExpandedDock(axis, theme, screenSize),
      ),
    );
  }

  Widget _buildCollapsedTrigger(ThemeData theme) {
    return Draggable(
      feedback: Material(
        type: MaterialType.transparency,
        child: _buildIconContent(Icons.auto_awesome, theme, isDragging: true),
      ),
      childWhenDragging: const SizedBox.shrink(),
      onDragEnd: (details) {
        setState(() {
          // Snap to edges
          final screenSize = MediaQuery.of(context).size;
          double dx = details.offset.dx;
          double dy = details.offset.dy;

          if (dx < screenSize.width / 2) {
            dx = 10;
          } else {
            dx = screenSize.width - 60;
          }

          if (dy < 50) {
            dy = 50;
          }
          if (dy > screenSize.height - 100) {
            dy = screenSize.height - 100;
          }

          _position = Offset(dx, dy);
        });
      },
      child: GestureDetector(
        onTap: _toggleExpanded,
        child: _buildIconContent(Icons.auto_awesome, theme),
      ),
    );
  }

  Widget _buildIconContent(IconData icon, ThemeData theme, {bool isDragging = false}) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withAlpha(isDragging ? 150 : 255),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(50),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ],
      ),
      child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
    );
  }

  Widget _buildExpandedDock(Axis axis, ThemeData theme, Size screenSize) {
    return FadeTransition(
      opacity: _expandAnimation,
      child: ScaleTransition(
        scale: _expandAnimation,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withAlpha(120), // More transparent
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(80)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(30),
                blurRadius: 30, // Softer shadow
                spreadRadius: 2,
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), // Higher blur
              child: Flex(
                direction: axis,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Collapse button
                  _buildDockItem(
                    DockItem(
                      icon: Icons.close_fullscreen,
                      label: 'Thu nhỏ',
                      onTap: _toggleExpanded,
                    ),
                    theme,
                    -1,
                  ),
                  const SizedBox(width: 8, height: 8),
                  Container(
                    width: axis == Axis.horizontal ? 1 : 20,
                    height: axis == Axis.horizontal ? 20 : 1,
                    color: theme.colorScheme.outlineVariant.withAlpha(80),
                  ),
                  const SizedBox(width: 8, height: 8),
                  // Main items
                  ...widget.items.asMap().entries.map((entry) => _buildDockItem(entry.value, theme, entry.key)),
                  const SizedBox(width: 8, height: 8),
                  Container(
                    width: axis == Axis.horizontal ? 1 : 20,
                    height: axis == Axis.horizontal ? 20 : 1,
                    color: theme.colorScheme.outlineVariant.withAlpha(80),
                  ),
                  const SizedBox(width: 8, height: 8),
                  // Action items
                  ...widget.actionItems.asMap().entries.map((entry) => _buildDockItem(entry.value, theme, entry.key + 100)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDockItem(DockItem item, ThemeData theme, int index) {
    final bool isHovered = _hoveredIndex == index;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() => _hoveredIndex = null),
      child: GestureDetector(
        onTap: item.onTap,
        child: Tooltip(
          key: ValueKey('dock_tooltip_$index'),
          message: item.label,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: item.isSelected ? theme.colorScheme.primaryContainer.withAlpha(180) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 300),
              scale: isHovered ? _hoverScale : 1.0,
              curve: Curves.easeOutBack,
              child: Icon(
                item.isSelected && item.selectedIcon != null ? item.selectedIcon : item.icon,
                color: item.isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : (item.color ?? theme.colorScheme.onSurface.withAlpha(200)),
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
