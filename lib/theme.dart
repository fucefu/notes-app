import 'package:flutter/material.dart';

/// 便签 App 的视觉基调：暖白纸感 + 棕褐墨色，与 notes 网页的锤子便签风格保持一致。
class AppPalette {
  static const Color paper = Color(0xFFFAF6EF);
  static const Color card = Color(0xFFFFFDF9);
  static const Color ink = Color(0xFF2E2A24);
  static const Color inkSoft = Color(0xFF7A7166);
  static const Color accent = Color(0xFF8C6A4A);
  static const Color internal = Color(0xFF2E7D5B);
  static const Color publicNet = Color(0xFF3A6EA5);
  static const Color danger = Color(0xFFB4442F);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppPalette.accent,
    brightness: Brightness.light,
  ).copyWith(
    surface: AppPalette.paper,
    primary: AppPalette.accent,
    onSurface: AppPalette.ink,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppPalette.paper,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppPalette.paper,
      foregroundColor: AppPalette.ink,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppPalette.ink,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: .5,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppPalette.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppPalette.inkSoft.withValues(alpha: .25)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppPalette.inkSoft.withValues(alpha: .25)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppPalette.accent, width: 1.4),
      ),
      labelStyle: const TextStyle(color: AppPalette.inkSoft),
      hintStyle: TextStyle(color: AppPalette.inkSoft.withValues(alpha: .7)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppPalette.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppPalette.accent),
    ),
    dividerTheme: DividerThemeData(
      color: AppPalette.inkSoft.withValues(alpha: .15),
      thickness: 1,
    ),
  );
}
