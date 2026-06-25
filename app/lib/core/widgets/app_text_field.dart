import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

// .input.filled: 배경 #F4F6F9, 보더 투명, radius 13.
final _filledBorder = OutlineInputBorder(
  borderRadius: BorderRadius.circular(AppTheme.inputRadius),
  borderSide: BorderSide.none,
);

/// 라벨형 입력 필드 (목업 기준). 라벨 + height 50 + radius 13.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.suffix,
    this.onSubmitted,
    this.filled = false,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  /// .input.filled: 배경 #F4F6F9, 보더 투명(로그인/폼 입력).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink2,
            letterSpacing: -0.13,
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          validator: validator,
          onFieldSubmitted: onSubmitted,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
            letterSpacing: -0.15,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(
              color: AppColors.ink3,
              fontWeight: FontWeight.w500,
            ),
            suffixIcon: suffix,
            constraints: const BoxConstraints(minHeight: AppTheme.inputHeight),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            filled: filled ? true : null,
            fillColor: filled ? const Color(0xFFF4F6F9) : null,
            border: filled ? _filledBorder : null,
            enabledBorder: filled ? _filledBorder : null,
            focusedBorder: filled ? _filledBorder : null,
          ),
        ),
      ],
    );
  }
}
