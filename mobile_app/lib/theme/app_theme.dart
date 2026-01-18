import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// App theme definitions - ChatGPT-like modern design
class AppTheme {
  // Dark theme colors (ChatGPT-like dark)
  static const Color _darkBgPrimary = Color(0xFF212121);     // Main background - dark gray
  static const Color _darkBgSecondary = Color(0xFF2F2F2F);   // Cards/surfaces - slightly lighter
  static const Color _darkBgTertiary = Color(0xFF171717);    // Even darker for contrast
  static const Color _darkAccent = Color(0xFF10A37F);        // ChatGPT green accent
  static const Color _darkAccentSecondary = Color(0xFF19C37D);
  static const Color _darkTextPrimary = Color(0xFFEFEFEF);   // Bright white text
  static const Color _darkTextSecondary = Color(0xFF8E8E8E); // Muted gray text
  static const Color _darkBorder = Color(0xFF3F3F3F);        // Border color
  static const Color _darkSuccess = Color(0xFF10A37F);
  static const Color _darkError = Color(0xFFEF4444);
  static const Color _darkInputBg = Color(0xFF40414F);       // Input field background - lighter

  // Light theme colors (contrasting light)
  static const Color _lightBgPrimary = Color(0xFFF7F7F8);    // Main background - light gray
  static const Color _lightBgSecondary = Color(0xFFFFFFFF);  // Cards/surfaces - white
  static const Color _lightBgTertiary = Color(0xFFECECEC);   // Slightly darker for contrast
  static const Color _lightAccent = Color(0xFF10A37F);       // Same green accent
  static const Color _lightAccentSecondary = Color(0xFF19C37D);
  static const Color _lightTextPrimary = Color(0xFF1A1A1A);  // Dark text
  static const Color _lightTextSecondary = Color(0xFF6E6E80);// Muted text
  static const Color _lightBorder = Color(0xFFD1D5DB);       // Light border
  static const Color _lightSuccess = Color(0xFF10A37F);
  static const Color _lightError = Color(0xFFDC2626);
  static const Color _lightInputBg = Color(0xFFFFFFFF);      // Input field - pure white

  /// Dark theme
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _darkBgPrimary,
    primaryColor: _darkAccent,
    colorScheme: const ColorScheme.dark(
      primary: _darkAccent,
      secondary: _darkAccentSecondary,
      surface: _darkBgSecondary,
      error: _darkError,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: _darkTextPrimary,
      onError: Colors.white,
    ),
    textTheme: GoogleFonts.interTextTheme(
      ThemeData.dark().textTheme.copyWith(
        displayLarge: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: _darkTextPrimary,
        ),
        headlineMedium: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: _darkTextPrimary,
        ),
        titleLarge: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: _darkTextPrimary,
        ),
        titleMedium: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: _darkTextPrimary,
        ),
        bodyLarge: const TextStyle(
          fontSize: 16,
          color: _darkTextPrimary,
        ),
        bodyMedium: const TextStyle(
          fontSize: 14,
          color: _darkTextSecondary,
        ),
        labelLarge: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: _darkTextPrimary,
        ),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _darkBgSecondary,
      foregroundColor: _darkTextPrimary,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: _darkBgSecondary,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _darkBorder, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _darkBgSecondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _darkAccent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _darkError),
      ),
      hintStyle: const TextStyle(color: _darkTextSecondary),
      labelStyle: const TextStyle(color: _darkTextSecondary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _darkAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _darkAccent,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    iconTheme: const IconThemeData(color: _darkTextPrimary),
    dividerTheme: const DividerThemeData(
      color: _darkBorder,
      thickness: 1,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: _darkBgSecondary,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: _darkBgSecondary,
      contentTextStyle: const TextStyle(color: _darkTextPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
  );

  /// Light theme
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: _lightBgPrimary,
    primaryColor: _lightAccent,
    colorScheme: const ColorScheme.light(
      primary: _lightAccent,
      secondary: _lightAccentSecondary,
      surface: _lightBgSecondary,
      error: _lightError,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: _lightTextPrimary,
      onError: Colors.white,
    ),
    textTheme: GoogleFonts.interTextTheme(
      ThemeData.light().textTheme.copyWith(
        displayLarge: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: _lightTextPrimary,
        ),
        headlineMedium: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: _lightTextPrimary,
        ),
        titleLarge: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: _lightTextPrimary,
        ),
        titleMedium: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: _lightTextPrimary,
        ),
        bodyLarge: const TextStyle(
          fontSize: 16,
          color: _lightTextPrimary,
        ),
        bodyMedium: const TextStyle(
          fontSize: 14,
          color: _lightTextSecondary,
        ),
        labelLarge: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: _lightTextPrimary,
        ),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _lightBgSecondary,
      foregroundColor: _lightTextPrimary,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: _lightBgSecondary,
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _lightBgSecondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _lightBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _lightAccent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _lightError),
      ),
      hintStyle: const TextStyle(color: _lightTextSecondary),
      labelStyle: const TextStyle(color: _lightTextSecondary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _lightAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 2,
        shadowColor: _lightAccent.withOpacity(0.3),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _lightAccent,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    iconTheme: const IconThemeData(color: _lightTextPrimary),
    dividerTheme: const DividerThemeData(
      color: _lightBorder,
      thickness: 1,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: _lightBgSecondary,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: _lightBgSecondary,
      contentTextStyle: const TextStyle(color: _lightTextPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
  );

  // Gradient for accent backgrounds
  static const LinearGradient accentGradient = LinearGradient(
    colors: [_darkAccent, _darkAccentSecondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Colors for direct access
  static Color get accent => _darkAccent;
  static Color get success => _darkSuccess;
  static Color get error => _darkError;
}
