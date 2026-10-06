import 'package:flutter/material.dart';

/// The palette the web app settled on: near-black slate chrome, one teal accent,
/// flat surfaces and hairline borders. No gradients anywhere.
class Brand {
  static const accent = Color(0xFF0D9488);
  static const accentDark = Color(0xFF0F766E);
  static const accentSoft = Color(0xFFEFFBF8);
  static const chrome = Color(0xFF111827); // sidebar / drawer
  static const chromeSoft = Color(0xFF1F2937);
  static const text = Color(0xFF111827);
  static const textSoft = Color(0xFF4B5563);
  static const muted = Color(0xFF9CA3AF);
  static const border = Color(0xFFE5E7EB);
  static const borderSoft = Color(0xFFF1F2F4);
  static const surface = Color(0xFFFFFFFF);
  static const layout = Color(0xFFF6F7F9);
  static const success = Color(0xFF15803D);
  static const warning = Color(0xFFB45309);
  static const error = Color(0xFFBE123C);
  static const info = Color(0xFF0369A1);

  /// Categorical chart colours, used strictly in this order and never cycled.
  static const series = [
    Color(0xFF0D9488),
    Color(0xFFBE123C),
    Color(0xFF0369A1),
    Color(0xFFB45309),
    Color(0xFF6D28D9),
    Color(0xFF15803D),
  ];
}

/// Colour for a status-ish word, so tags read the same way across every screen.
Color statusColor(String? value) {
  switch (value) {
    case 'pass':
    case 'verified':
    case 'selected':
    case 'ready':
    case 'open':
    case 'promoted':
    case 'studying':
    case 'active':
      return Brand.success;
    case 'fail':
    case 'rejected':
    case 'discontinued':
    case 'absent':
      return Brand.error;
    case 'pending':
    case 'close':
    case 'in_process':
    case 'detained':
    case 'upcoming':
      return Brand.warning;
    case 'applied':
    case 'shortlisted':
    case 'passed_out':
      return Brand.info;
    default:
      return Brand.textSoft;
  }
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Brand.accent,
      primary: Brand.accent,
      surface: Brand.surface,
      error: Brand.error,
    ),
    scaffoldBackgroundColor: Brand.layout,
    fontFamily: 'Roboto',
  );
  return base.copyWith(
    // A white app bar with dark text, matching the web header.
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.surface,
      foregroundColor: Brand.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: Brand.text, fontSize: 17, fontWeight: FontWeight.w600),
      shape: Border(bottom: BorderSide(color: Brand.border)),
    ),
    cardTheme: CardThemeData(
      color: Brand.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Brand.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Brand.border, thickness: 1, space: 1),
    chipTheme: ChipThemeData(
      backgroundColor: Brand.borderSoft,
      side: BorderSide.none,
      labelStyle: const TextStyle(fontSize: 12, color: Brand.textSoft, fontWeight: FontWeight.w500),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Brand.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Brand.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Brand.accent, width: 1.5),
      ),
      labelStyle: const TextStyle(color: Brand.textSoft),
      hintStyle: const TextStyle(color: Brand.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.text,
        minimumSize: const Size(0, 44),
        side: const BorderSide(color: Brand.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Brand.accent),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Brand.accent,
      unselectedLabelColor: Brand.textSoft,
      indicatorColor: Brand.accent,
      dividerColor: Brand.border,
      labelStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
    ),
    listTileTheme: const ListTileThemeData(iconColor: Brand.textSoft),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Brand.chrome,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Brand.accent),
    textTheme: base.textTheme.apply(bodyColor: Brand.text, displayColor: Brand.text),
  );
}
