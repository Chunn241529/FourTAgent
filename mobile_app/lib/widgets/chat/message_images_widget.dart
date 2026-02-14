import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../widgets/chat/message_bubble.dart';

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
             const ShimmerPlaceholder(width: 256, height: 256),
        ],
      ),
    );
  }

  Widget _buildImageThumbnail(BuildContext context, String imageBase64) {
    // We decode here, but since this widget is now separate, 
    // we can use const constructors or keys to help Flutter identify it.
    
    final imageBytes = base64Decode(imageBase64);
    final key = ValueKey(imageBase64.hashCode); // key based on content

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
          gaplessPlayback: true, // Crucial for preventing flicker during updates
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
     // ... Implementation from existing MessageBubble ...
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

class ShimmerPlaceholder extends StatefulWidget {
  final double width;
  final double height;
  
  const ShimmerPlaceholder({super.key, required this.width, required this.height});

  @override
  State<ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<ShimmerPlaceholder> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
       width: widget.width,
       height: widget.height,
       decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
       ),
       child: AnimatedBuilder(
         animation: _animation,
         builder: (context, child) {
           return DecoratedBox(
             decoration: BoxDecoration(
               gradient: LinearGradient(
                 begin: Alignment.topLeft,
                 end: Alignment.bottomRight,
                 colors: [
                   Colors.transparent,
                   Colors.white.withOpacity(0.1),
                   Colors.transparent,
                 ],
                 stops: const [0.1, 0.3, 0.5],
                 transform: GradientRotation(_animation.value),
               ),
             ),
           );
         },
       ),
    );
  }
}
