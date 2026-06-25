import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../jobs/job_format.dart';
import '../wallet_models.dart';

/// 포인트 원장 한 줄(목업 ④ 최근 내역).
/// 좌: 유형 라벨 + 일시/메모, 우: +/- 금액(부호색) + balance_after.
class PointTxTile extends StatelessWidget {
  const PointTxTile({super.key, required this.tx, this.last = false});

  final PointTransaction tx;
  final bool last;

  static final _dt = DateFormat('M/d(E) HH:mm', 'ko_KR');

  @override
  Widget build(BuildContext context) {
    final credit = tx.isCredit;
    // 수령(+) okFg, 차감(-) red 포인트 색(목업 기준 — 토큰만 사용).
    final amountColor = credit ? AppColors.okFg : AppColors.red;
    final sign = credit ? '+' : '-';
    final abs = tx.amount.abs();

    final subtitle = [
      _dt.format(tx.createdAt),
      if (tx.memo != null && tx.memo!.isNotEmpty) tx.memo!,
    ].join(' · ');

    // 정본 ⑬: 행 구분선은 line-2(더 옅은 구분선), 행 패딩 11px·좌우 2px.
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.line2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.type.label,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink3)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$sign${JobFormat.amount(abs)}P',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: amountColor,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 2),
              Text('잔액 ${JobFormat.amount(tx.balanceAfter)}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink3,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
        ],
      ),
    );
  }
}
