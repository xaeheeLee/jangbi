import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_theme.dart';

/// 버튼 변형(.btn-navy / .btn-red / .btn-ghost / .btn-white).
enum PrimaryButtonVariant { navy, red, ghost, white }

/// 목업 .btn 1:1: height 52, radius 14, font 15.5/w800, gap 7, ls -.01em.
/// navy/red 는 shadow-lift, ghost 는 1.5px 보더, white 는 흰 배경+그림자.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.enabled = true,
    this.variant = PrimaryButtonVariant.navy,
    this.icon,
    this.height = AppTheme.buttonHeight,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool enabled;
  final PrimaryButtonVariant variant;
  final IconData? icon;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final isEnabled = enabled && !loading && onPressed != null;

    Color bg;
    Color fg;
    List<BoxShadow> shadow = const [];
    BoxBorder? border;
    switch (variant) {
      case PrimaryButtonVariant.navy:
        bg = AppColors.navy;
        fg = Colors.white;
        shadow = AppShadows.lift;
      case PrimaryButtonVariant.red:
        bg = AppColors.red;
        fg = Colors.white;
        shadow = AppShadows.liftRed;
      case PrimaryButtonVariant.ghost:
        bg = AppColors.card;
        fg = AppColors.navy;
        border = Border.all(color: AppColors.ghostBorder, width: 1.5);
      case PrimaryButtonVariant.white:
        bg = Colors.white;
        fg = AppColors.navy;
        shadow = AppShadows.whiteBtn;
    }
    if (!isEnabled) {
      bg = AppColors.ink3;
      fg = Colors.white;
      shadow = const [];
      border = null;
    }

    final content = loading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 19, color: fg),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.15,
                  color: fg,
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: label,
      child: GestureDetector(
        onTap: isEnabled ? onPressed : null,
        child: Container(
          height: height,
          width: expand ? double.infinity : null,
          alignment: Alignment.center,
          padding: expand ? null : const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
            boxShadow: shadow,
            border: border,
          ),
          child: content,
        ),
      ),
    );
  }
}
