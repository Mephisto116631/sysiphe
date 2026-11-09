import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryBlue = Color(0xFF1976D2);
  static const Color bgGrey = Color(0xFFF4F6F8);
  static const Color cardWhite = Colors.white;
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color borderColor = Color(0xFFE5E7EB);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
          brightness: Brightness.light,
        ).copyWith(
          primary: primaryBlue,
          onPrimary: Colors.white,
          surface: cardWhite,
          surfaceContainerLowest: bgGrey,
        ),
        scaffoldBackgroundColor: bgGrey,
        appBarTheme: const AppBarTheme(
          backgroundColor: cardWhite,
          foregroundColor: textPrimary,
          elevation: 0,
          scrolledUnderElevation: 1,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: textPrimary),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: cardWhite,
          selectedItemColor: primaryBlue,
          unselectedItemColor: textSecondary,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
          unselectedLabelStyle: TextStyle(fontSize: 11),
        ),
        cardTheme: const CardTheme(
          color: cardWhite,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: borderColor),
          ),
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: cardWhite,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: primaryBlue, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          labelStyle: const TextStyle(color: textSecondary),
          hintStyle: const TextStyle(color: textSecondary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryBlue,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryBlue,
            side: const BorderSide(color: primaryBlue),
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: bgGrey,
          selectedColor: primaryBlue.withOpacity(0.15),
          labelStyle: const TextStyle(fontSize: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: const BorderSide(color: borderColor),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        dividerTheme: const DividerThemeData(
          color: borderColor,
          thickness: 1,
          space: 1,
        ),
        textTheme: const TextTheme(
          headlineLarge:
              TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textPrimary),
          headlineMedium:
              TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textPrimary),
          titleLarge:
              TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
          titleMedium:
              TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary),
          bodyLarge: TextStyle(fontSize: 15, color: textPrimary),
          bodyMedium: TextStyle(fontSize: 13, color: textSecondary),
          labelSmall: TextStyle(fontSize: 11, color: textSecondary),
        ),
      );
}
