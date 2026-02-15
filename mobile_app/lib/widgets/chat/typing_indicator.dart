import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';

/// Typing indicator for AI response
class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              'assets/icon/icon.png',
              width: 16,
              height: 16,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 12),
          DefaultTextStyle(
            style: theme.textTheme.bodyMedium!.copyWith(
              color: theme.colorScheme.primary,
            ),
            child: AnimatedTextKit(
              animatedTexts: [
                WavyAnimatedText('Đang suy nghĩ...'),
              ],
              isRepeatingAnimation: true,
              repeatForever: true,
            ),
          ),
        ],
      ),
    );
  }
}
