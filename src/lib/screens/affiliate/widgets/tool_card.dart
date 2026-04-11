import 'package:flutter/material.dart';
import '../theme/affiliate_theme.dart';
import 'affiliate_animations.dart';

class ModernToolCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final bool isActive;
  final int index;

  const ModernToolCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.color,
    this.isActive = false,
    this.index = 0,
  });

  @override
  State<ModernToolCard> createState() => _ModernToolCardState();
}

class _ModernToolCardState extends State<ModernToolCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return FadeInTranslate(
      delay: Duration(milliseconds: 100 * widget.index),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedScale(
          scale: _isHovered ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: AffiliateTheme.cardDecoration(context).copyWith(
                border: Border.all(
                  color: widget.isActive 
                      ? AffiliateTheme.primary 
                      : (_isHovered ? AffiliateTheme.primary.withOpacity(0.5) : Colors.transparent),
                  width: 2,
                ),
              ),
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (widget.color ?? AffiliateTheme.primary).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.icon,
                          size: 28,
                          color: widget.color ?? AffiliateTheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.title,
                        style: AffiliateTheme.titleStyle(context).copyWith(fontSize: 16),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: AffiliateTheme.subtitleStyle(context).copyWith(fontSize: 12),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
