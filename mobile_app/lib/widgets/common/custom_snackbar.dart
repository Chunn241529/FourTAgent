import 'package:flutter/material.dart';

class CustomSnackBar {
  static void showError(BuildContext context, String message) {
    _show(context, message, isError: true);
  }

  static void showSuccess(BuildContext context, String message) {
    _show(context, message, isError: false);
  }

  static void _show(BuildContext context, String message, {required bool isError}) {
    // Clear existing snackbars to prevent stacking
    ScaffoldMessenger.of(context).clearSnackBars();

    final theme = Theme.of(context);
    final color = isError ? theme.colorScheme.error : const Color(0xFF10B981); // Emerald green for success
    final icon = isError ? Icons.error_rounded : Icons.check_circle_rounded;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: color.withOpacity(0.95),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        width: MediaQuery.of(context).size.width > 600 ? 400 : null, // Limit width on desktop
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Đóng',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }
}
