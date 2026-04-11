import 'package:flutter/material.dart';

/// Local theme constants for the Affiliate Studio module.
class AffiliateTheme {
  // Colors - Premium Palette
  static const Color primary = Color(0xFF6366F1); // Indigo
  static const Color secondary = Color(0xFF8B5CF6); // Violet
  static const Color accent = Color(0xFF10B981); // Emerald
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color error = Color(0xFFEF4444); // Red

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient glassGradient(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LinearGradient(
      colors: isDark
          ? [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.05)]
          : [Colors.black.withOpacity(0.05), Colors.black.withOpacity(0.01)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  // Decorations
  static BoxDecoration glassDecoration(BuildContext context, {double borderRadius = 16}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.02),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          spreadRadius: 0,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  static BoxDecoration cardDecoration(BuildContext context) {
    return glassDecoration(context, borderRadius: 24);
  }

  // Text Styles
  static TextStyle titleStyle(BuildContext context) {
    return Theme.of(context).textTheme.titleLarge!.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        );
  }

  static TextStyle subtitleStyle(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
        );
  }

  // Inputs
  static InputDecoration inputDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon, color: primary, size: 20) : null,
      filled: true,
      fillColor: primary.withOpacity(0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      floatingLabelStyle: const TextStyle(color: primary, fontWeight: FontWeight.bold),
    );
  }
}
