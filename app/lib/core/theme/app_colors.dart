import 'package:flutter/material.dart';

/// 전중배 디자인 토큰 — CLAUDE.md 절대원칙 #4.
/// 색상 하드코딩 금지. UI에서는 반드시 이 상수를 사용한다.
abstract final class AppColors {
  // 기존 토큰 (유지)
  static const primary = Color(0xFF002F6C);
  static const primaryLight = Color(0xFF3B82F6);
  static const primaryBg = Color(0xFFEFF6FF);

  // 목업 실측 토큰 (P1)
  static const navy = Color(0xFF002F6C);
  static const navyLight = Color(0xFF013A85);
  static const blue = Color(0xFF3B82F6);
  static const blueInk = Color(0xFF1D4ED8);
  static const red = Color(0xFFDC2626);
  static const orange = Color(0xFFF97316);

  static const bg = Color(0xFFF7F8FA);
  static const ink = Color(0xFF101622);
  static const ink2 = Color(0xFF5A6473);
  static const ink3 = Color(0xFF9AA3B2);
  static const line = Color(0xFFEAEDF2);
  static const card = Color(0xFFFFFFFF);

  static const okBg = Color(0xFFE7F6EC);
  static const okFg = Color(0xFF15803D);
  static const revBg = Color(0xFFFCF0D8);
  static const revFg = Color(0xFFB45309);

  // 목업 추가 hex (그라데이션·세그·태그 등 고유값 토큰화)
  static const navyHi = Color(0xFF013A85); // navy-2 (밝은쪽)
  static const heroMid = Color(0xFF01285A); // hero-navy 60% 지점
  static const heroEnd = Color(0xFF01224D); // hero-navy 100% 지점
  static const line2 = Color(0xFFF0F2F6); // --line-2 (irow 구분선)
  static const segBg = Color(0xFFEEF1F5); // 세그먼트 토글 배경
  static const tagBlueBg = Color(0xFFEAF1FE); // .tag 파랑 배경
  static const tagGrayBg = Color(0xFFEEF1F5); // .tag.gray 배경
  static const tagGrayFg = Color(0xFF475569); // .tag.gray 글자
  static const pillOpenBg = Color(0xFFE4EDFF); // .pill.open 배경
  static const redBg = Color(0xFFFEF1EC); // 우선배차 연한 빨강 박스
  static const ghostBorder = Color(0xFFD7DEE8); // .btn-ghost border
  static const dashBorder = Color(0xFFCFD6E0); // .chip.add dashed border

  // 호환용 별칭 (기존 코드 참조 유지)
  static const surface = card;
  static const background = bg;
  static const textPrimary = ink;
  static const textSecondary = ink2;
  static const border = line;
  static const success = okFg;
  static const warning = orange;
  static const danger = red;
}
