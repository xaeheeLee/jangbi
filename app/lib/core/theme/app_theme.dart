import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 앱 전역 테마. 폰트는 Pretendard (CLAUDE.md 디자인 토큰).
/// Pretendard 폰트 에셋은 pubspec.yaml fonts 섹션에 등록되어야 적용된다.
/// 에셋 미번들 시 fontFamily 지정만 유지되어 시스템 폰트로 폴백한다.
abstract final class AppTheme {
  static const _fontFamily = 'Pretendard';

  /// 공용 radius 토큰.
  static const double fieldRadius = 13;
  static const double cardRadius = 16;
  static const double inputHeight = 50;
  static const double buttonHeight = 50;
  static const double appBarHeight = 54;
  static const double tabBarHeight = 64;

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      primary: AppColors.navy,
      surface: AppColors.card,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: _fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: appBarHeight,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          color: AppColors.ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(fieldRadius),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: const BorderSide(color: AppColors.blue, width: 1.4),
        ),
      ),
    );
  }
}
