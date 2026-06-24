import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 상태칩 변형.
enum StatusChipVariant {
  /// 완료(녹색).
  ok,

  /// 업로드 필요(회색/파랑 톤).
  need,

  /// 검토중(주황).
  rev,
}

/// 상태 표시 칩. ok/need/rev 변형. 색상은 AppColors 만 사용.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.variant});

  final String label;
  final StatusChipVariant variant;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    switch (variant) {
      case StatusChipVariant.ok:
        bg = AppColors.okBg;
        fg = AppColors.okFg;
      case StatusChipVariant.rev:
        bg = AppColors.revBg;
        fg = AppColors.revFg;
      case StatusChipVariant.need:
        bg = AppColors.primaryBg;
        fg = AppColors.blueInk;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
