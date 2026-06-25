import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../jobs/job_format.dart';
import '../dispatch_models.dart';

/// 우선배차권 카드(목업 우선배차권 빨강 포인트 차용).
/// 만료 임박(D-3 이내)=red, 그 외=line. 사용/만료 이력은 회색 처리.
class TicketCard extends StatelessWidget {
  const TicketCard({super.key, required this.ticket});

  final PriorityTicket ticket;

  @override
  Widget build(BuildContext context) {
    final used = ticket.isUsed;
    final expired = ticket.isExpired;
    final inactive = used || expired;
    final urgent = ticket.isAvailable && ticket.daysLeft <= 3;

    final borderColor = inactive
        ? AppColors.line
        : (urgent ? AppColors.red : AppColors.line);

    return Opacity(
      opacity: inactive ? 0.62 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: urgent ? 1.4 : 1,
          ),
        ),
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: inactive ? const Color(0xFFEEF1F5) : const Color(0xFFFEF1EC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.confirmation_number_outlined,
                size: 22,
                color: inactive ? AppColors.ink3 : AppColors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ticket.source.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: inactive ? AppColors.ink2 : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _subtitle(),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _DdayBadge(ticket: ticket),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    if (ticket.isUsed) {
      return '${JobFormat.workDateLong(ticket.usedAt!)} 사용';
    }
    return '만료 ${JobFormat.workDateLong(ticket.expiresAt)}';
  }
}

/// D-day 배지. 미사용=만료까지 D-N, 사용=사용완료, 만료=만료.
class _DdayBadge extends StatelessWidget {
  const _DdayBadge({required this.ticket});
  final PriorityTicket ticket;

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color bg;
    late final Color fg;

    if (ticket.isUsed) {
      label = '사용완료';
      bg = AppColors.line;
      fg = AppColors.ink2;
    } else if (ticket.isExpired) {
      label = '만료';
      bg = AppColors.line;
      fg = AppColors.ink2;
    } else {
      final d = ticket.daysLeft;
      label = d <= 0 ? '오늘 만료' : 'D-$d';
      if (d <= 1) {
        bg = AppColors.red;
        fg = Colors.white;
      } else if (d <= 3) {
        bg = AppColors.revBg;
        fg = AppColors.revFg;
      } else {
        bg = const Color(0xFFFEF1EC);
        fg = AppColors.red;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}
