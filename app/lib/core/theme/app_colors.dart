import 'package:flutter/material.dart';

/// 전중배 디자인 토큰 — CLAUDE.md 절대원칙 #4.
/// 색상 하드코딩 금지. UI에서는 반드시 이 상수를 사용한다.
abstract final class AppColors {
  static const primary = Color(0xFF002F6C);
  static const primaryLight = Color(0xFF3B82F6);
  static const primaryBg = Color(0xFFEFF6FF);

  // 보조 토큰 (목업 기준, 필요 시 확장)
  static const surface = Color(0xFFFFFFFF);
  static const background = Color(0xFFF8FAFC);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFDC2626);
}
