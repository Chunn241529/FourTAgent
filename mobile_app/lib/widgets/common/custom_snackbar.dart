import 'package:flutter/material.dart';

class CustomSnackBar {
  static OverlayEntry? _currentEntry;

  static void showError(BuildContext context, String message) {
    _show(context, message, isError: true);
  }

  static void showSuccess(BuildContext context, String message) {
    _show(context, message, isError: false);
  }

  static void _show(BuildContext context, String message, {required bool isError}) {
    // Remove existing snackbar if any
    _currentEntry?.remove();
    _currentEntry = null;

    final overlay = Overlay.of(context);
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    
    final color = isError 
        ? theme.colorScheme.error 
        : const Color(0xFF10B981); // Emerald green for success
    final icon = isError ? Icons.error_rounded : Icons.check_circle_rounded;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _AnimatedSnackBar(
        message: message,
        color: color,
        icon: icon,
        screenWidth: screenWidth,
        onDismiss: () {
          entry.remove();
          if (_currentEntry == entry) {
            _currentEntry = null;
          }
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }
}

class _AnimatedSnackBar extends StatefulWidget {
  final String message;
  final Color color;
  final IconData icon;
  final double screenWidth;
  final VoidCallback onDismiss;

  const _AnimatedSnackBar({
    required this.message,
    required this.color,
    required this.icon,
    required this.screenWidth,
    required this.onDismiss,
  });

  @override
  State<_AnimatedSnackBar> createState() => _AnimatedSnackBarState();
}

class _AnimatedSnackBarState extends State<_AnimatedSnackBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    // Auto dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  void _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate width: max 400px, centered
    final maxWidth = widget.screenWidth > 600 ? 400.0 : widget.screenWidth - 32;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 0,
      right: 0,
      child: Center(
        child: SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(maxWidth: maxWidth),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _dismiss,
                      child: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
