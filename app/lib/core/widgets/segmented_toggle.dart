import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';

/// 목업 .seg 1:1: 배경 #EEF1F5, radius 13, padding 4, gap 4.
/// 내부 버튼 height 40 / radius 10 / 13.5px / w800 / ink-2,
/// 활성(.on) 흰배경 + navy + shadow-sm.
class SegmentedToggle extends StatelessWidget {
  const SegmentedToggle({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.segBg,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i != 0) const SizedBox(width: 4),
            Expanded(
              child: _SegButton(
                label: labels[i],
                on: i == selectedIndex,
                onTap: () => onChanged(i),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SegButton extends StatelessWidget {
  const _SegButton({
    required this.label,
    required this.on,
    required this.onTap,
  });
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: on ? AppShadows.sm : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.14,
            color: on ? AppColors.navy : AppColors.ink2,
          ),
        ),
      ),
    );
  }
}
