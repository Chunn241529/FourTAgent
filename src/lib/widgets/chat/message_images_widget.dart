import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

class MessageImagesWidget extends StatelessWidget {
  final List<String> images;
  final Function(BuildContext, Uint8List, String) onDownload;
  final bool isGenerating;

  const MessageImagesWidget({
    super.key,
    required this.images,
    required this.onDownload,
    this.isGenerating = false,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty && !isGenerating) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...images.map((imageBase64) => _buildImageThumbnail(context, imageBase64)),
          if (isGenerating)
             const ImageGeneratingPlaceholder(width: 256, height: 256),
        ],
      ),
    );
  }

  Widget _buildImageThumbnail(BuildContext context, String imageBase64) {
    final imageBytes = base64Decode(imageBase64);
    final key = ValueKey(imageBase64.hashCode);

    return GestureDetector(
      key: key,
      onTap: () => _showFullScreenImage(context, imageBytes, imageBase64),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          imageBytes,
          width: 256,
          height: 256,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Container(
            width: 256,
            height: 256,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.broken_image, size: 48),
          ),
        ),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, Uint8List imageBytes, String imageBase64) {
     showDialog(
      context: context,
      builder: (ctx) => LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: isMobile ? const EdgeInsets.all(8) : const EdgeInsets.all(40),
            child: Stack(
              children: [
                 InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.memory(imageBytes, fit: BoxFit.contain),
                 ),
                 Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(backgroundColor: Colors.black54),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                 ),
                 Positioned(
                    bottom: 16,
                    right: 16,
                    child: FloatingActionButton(
                      onPressed: () => onDownload(context, imageBytes, imageBase64),
                      child: const Icon(Icons.download),
                    ),
                 ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Premium animated placeholder shown while image is being generated
class ImageGeneratingPlaceholder extends StatefulWidget {
  final double width;
  final double height;
  
  const ImageGeneratingPlaceholder({super.key, required this.width, required this.height});

  @override
  State<ImageGeneratingPlaceholder> createState() => _ImageGeneratingPlaceholderState();
}

class _ImageGeneratingPlaceholderState extends State<ImageGeneratingPlaceholder> with TickerProviderStateMixin {
  late AnimationController _shimmerController;
  late AnimationController _pulseController;
  late AnimationController _borderController;
  late Animation<double> _shimmerAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    
    // Shimmer sweep animation
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _shimmerAnimation = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );
    
    // Pulse animation for icon/text
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Border rotation
    _borderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _pulseController.dispose();
    _borderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final secondaryColor = theme.colorScheme.secondary;

    return AnimatedBuilder(
      animation: Listenable.merge([_shimmerAnimation, _pulseAnimation, _borderController]),
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            // Subtle base background
            color: isDark
                ? Colors.grey[900]!.withOpacity(0.6)
                : Colors.grey[100]!.withOpacity(0.8),
          ),
          child: Stack(
            children: [
              // Animated gradient border
              Positioned.fill(
                child: CustomPaint(
                  painter: _AnimatedBorderPainter(
                    progress: _borderController.value,
                    primaryColor: primaryColor,
                    secondaryColor: secondaryColor,
                    borderRadius: 12,
                    strokeWidth: 2,
                  ),
                ),
              ),
              
              // Shimmer sweep overlay
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ShaderMask(
                    shaderCallback: (bounds) {
                      return LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.transparent,
                          primaryColor.withOpacity(0.08),
                          primaryColor.withOpacity(0.15),
                          primaryColor.withOpacity(0.08),
                          Colors.transparent,
                        ],
                        stops: [
                          0.0,
                          (_shimmerAnimation.value - 0.3).clamp(0.0, 1.0),
                          _shimmerAnimation.value.clamp(0.0, 1.0),
                          (_shimmerAnimation.value + 0.3).clamp(0.0, 1.0),
                          1.0,
                        ],
                      ).createShader(bounds);
                    },
                    blendMode: BlendMode.srcATop,
                    child: Container(
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ),
              
              // Center content: icon + text
              Center(
                child: Opacity(
                  opacity: _pulseAnimation.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Sparkle icon with gradient
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [primaryColor, secondaryColor],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds),
                        child: const Icon(
                          Icons.auto_awesome,
                          size: 36,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Đang tạo ảnh...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isDark
                              ? Colors.grey[400]
                              : Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Custom painter that draws an animated gradient border that sweeps around the rectangle
class _AnimatedBorderPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color secondaryColor;
  final double borderRadius;
  final double strokeWidth;

  _AnimatedBorderPainter({
    required this.progress,
    required this.primaryColor,
    required this.secondaryColor,
    required this.borderRadius,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(borderRadius),
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          primaryColor.withOpacity(0.8),
          secondaryColor.withOpacity(0.6),
          primaryColor.withOpacity(0.1),
          Colors.transparent,
          primaryColor.withOpacity(0.8),
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(rect);

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _AnimatedBorderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
