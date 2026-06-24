import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 3단계 스텝 인디케이터. 현재 단계 강조(navy), 완료/대기 구분.
class StepIndicator extends StatelessWidget {
  const StepIndicator({
    super.key,
    required this.steps,
    required this.currentIndex,
  });

  /// 각 단계 라벨.
  final List<String> steps;

  /// 0-based 현재 단계.
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          _Dot(
            index: i,
            label: steps[i],
            state: i < currentIndex
                ? _StepState.done
                : (i == currentIndex ? _StepState.active : _StepState.todo),
          ),
          if (i != steps.length - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: i < currentIndex ? AppColors.navy : AppColors.line,
              ),
            ),
        ],
      ],
    );
  }
}

enum _StepState { done, active, todo }

class _Dot extends StatelessWidget {
  const _Dot({required this.index, required this.label, required this.state});

  final int index;
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final active = state != _StepState.todo;
    final circleColor = active ? AppColors.navy : AppColors.line;
    final fg = active ? Colors.white : AppColors.ink3;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: circleColor, shape: BoxShape.circle),
          child: state == _StepState.done
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: active ? AppColors.navy : AppColors.ink3,
          ),
        ),
      ],
    );
  }
}
