import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';

/// 브랜드 원형 엠블럼 로고 에셋 경로.
abstract final class BrandAssets {
  static const color = 'assets/brand/logo_color.png'; // 흰 배경용
  static const white = 'assets/brand/logo_white.png'; // 네이비 위
  static const whiteMono = 'assets/brand/logo_white_mono.png';
}

/// 로그인 큰 로고 배지(.logo-badge): 흰 라운드 정사각 + 그림자 + inset 흰 보더.
/// 정본 사이즈 132 / radius 30. 안에 컬러 엠블럼.
class LogoBadge extends StatelessWidget {
  const LogoBadge({super.key, this.size = 132, this.radius = 30});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppShadows.logoBadge,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.16),
        child: Image.asset(
          BrandAssets.color,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              Icon(Icons.construction, color: AppColors.navy, size: size * 0.4),
        ),
      ),
    );
  }
}

/// 앱바 소형 컬러 로고(목록 상단). 25px 정도.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 26});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      BrandAssets.color,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          Icon(Icons.construction, color: AppColors.navy, size: size),
    );
  }
}
