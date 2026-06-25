import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 앱 전역 테마. 폰트는 Pretendard (CLAUDE.md 디자인 토큰).
/// 타이포/버튼/입력 스펙은 목업(index.html) CSS 에서 1:1 추출.
abstract final class AppTheme {
  static const fontFamily = 'Pretendard';

  /// 공용 radius 토큰(목업 :root).
  static const double rLg = 22; // --r-lg
  static const double rMd = 16; // --r-md
  static const double rSm = 12; // --r-sm
  static const double buttonRadius = 14; // .btn
  static const double inputRadius = 13; // .input
  static const double segRadius = 13; // .seg
  static const double chipRadius = 999; // .chip (pill)

  // 호환용(기존 참조 유지).
  static const double fieldRadius = 13;
  static const double cardRadius = 16;

  static const double inputHeight = 50; // .input
  static const double buttonHeight = 52; // .btn
  static const double appBarHeight = 54; // .appbar
  static const double tabBarHeight = 64; // .tabbar

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      primary: AppColors.navy,
      surface: AppColors.card,
    );

    // 기본 자간 -.01em ≈ 15px*-0.01 ≈ -0.15. 본문은 명시적으로 지정.
    const ls = -0.15;

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: _textTheme(ls),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: appBarHeight,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: AppColors.ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.36, // -.02em
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w800,
            fontSize: 15.5,
            letterSpacing: -0.15,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(color: AppColors.line, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(color: AppColors.line, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: const BorderSide(color: AppColors.navy, width: 1.5),
        ),
      ),
    );
  }

  /// 목업 타이포 스케일. h1 30/w800/-.03em, h2 17/w800/-.02em, 본문 15/w600.
  static TextTheme _textTheme(double ls) {
    return const TextTheme(
      // page-head h1
      headlineMedium: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.9, // -.03em
        color: AppColors.ink,
      ),
      // section h2
      titleLarge: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.34, // -.02em
        color: AppColors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.15,
        color: AppColors.ink,
      ),
      // 본문 15/w600
      bodyLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.15,
        color: AppColors.ink,
      ),
      bodyMedium: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.13,
        color: AppColors.ink2,
      ),
    );
  }
}
