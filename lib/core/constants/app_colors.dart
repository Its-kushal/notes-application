import 'package:flutter/material.dart';

/// Centralized color palette for Privacy Notes.
/// All colors in the app must originate from this class.
abstract final class AppColors {
  // Brand / Seed
  static const Color primary = Color(0xFF0D9488); // Teal 600
  static const Color primaryLight = Color(0xFF14B8A6); // Teal 500
  static const Color primaryDark = Color(0xFF0F766E); // Teal 700

  // Neutral - Light Theme
  static const Color lightBackground = Color(0xFFF8FAFC); // Slate 50
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFF1F5F9); // Slate 100
  static const Color lightBorder = Color(0xFFE2E8F0); // Slate 200
  static const Color lightTextPrimary = Color(0xFF0F172A); // Slate 900
  static const Color lightTextSecondary = Color(0xFF64748B); // Slate 500
  static const Color lightTextHint = Color(0xFF94A3B8); // Slate 400

  // Neutral - Dark Theme
  static const Color darkBackground = Color(0xFF0F172A); // Slate 900
  static const Color darkSurface = Color(0xFF1E293B); // Slate 800
  static const Color darkSurfaceElevated = Color(0xFF334155); // Slate 700
  static const Color darkBorder = Color(0xFF334155); // Slate 700
  static const Color darkTextPrimary = Color(0xFFF8FAFC); // Slate 50
  static const Color darkTextSecondary = Color(0xFF94A3B8); // Slate 400
  static const Color darkTextHint = Color(0xFF64748B); // Slate 500

  // Feedback
  static const Color error = Color(0xFFDC2626); // Red 600
  static const Color errorContainer = Color(0xFFFEE2E2); // Red 100
  static const Color darkErrorContainer = Color(0xFF7F1D1D); // Red 900
  static const Color success = Color(0xFF16A34A); // Green 600
  static const Color warning = Color(0xFFD97706); // Amber 600

  // Transparent / Utility
  static const Color transparent = Colors.transparent;
  static const Color white = Colors.white;
  static const Color black = Colors.black;

  // Note Color Labels (Subtle tint accents)
  static const List<Color> noteLabelColors = [
    Color(0x00000000), // 0: None / Default
    Color(0xFFEF4444), // 1: Red
    Color(0xFFF97316), // 2: Orange
    Color(0xFFEAB308), // 3: Yellow
    Color(0xFF10B981), // 4: Emerald
    Color(0xFF06B6D4), // 5: Cyan
    Color(0xFF3B82F6), // 6: Blue
    Color(0xFF8B5CF6), // 7: Purple
    Color(0xFFEC4899), // 8: Pink
  ];

  // Note Color Label Names for TalkBack accessibility
  static const List<String> noteLabelNames = [
    'None',
    'Red',
    'Orange',
    'Yellow',
    'Emerald',
    'Cyan',
    'Blue',
    'Purple',
    'Pink',
  ];
}
