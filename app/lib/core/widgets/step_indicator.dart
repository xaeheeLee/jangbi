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
    // .stepper: 라벨 포함 칼럼(width 62) + 사이 연결선(.ln, margin-top 13).
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
                margin: const EdgeInsets.only(top: 13),
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
    // .stepper .st .sd: 27x27 원. done=E7F6EC/green check, on=navy/흰글씨, todo=EAEDF2/ink-3.
    late final Color circleBg;
    late final Color circleFg;
    switch (state) {
      case _StepState.done:
        circleBg = AppColors.okBg;
        circleFg = AppColors.okFg;
      case _StepState.active:
        circleBg = AppColors.navy;
        circleFg = Colors.white;
      case _StepState.todo:
        circleBg = AppColors.line;
        circleFg = AppColors.ink3;
    }

    return SizedBox(
      width: 62,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 27,
            height: 27,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: circleBg, shape: BoxShape.circle),
            child: state == _StepState.done
                ? Icon(Icons.check, size: 14, color: circleFg)
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: circleFg,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: state == _StepState.active
                  ? AppColors.navy
                  : AppColors.ink3,
            ),
          ),
        ],
      ),
    );
  }
}
