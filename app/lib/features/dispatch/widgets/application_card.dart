import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../jobs/job_format.dart';
import '../../jobs/job_models.dart';
import '../dispatch_models.dart';

/// 내 지원/매칭 현황 카드(목업 ⑤ 배차 현황 카드 구조).
/// 매칭 성사=okBg 강조 테두리, 대기=line, 미선정=line+회색.
class ApplicationCard extends StatelessWidget {
  const ApplicationCard({super.key, required this.application, this.onTap});

  final JobApplication application;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final job = application.job;
    final phase = application.phase;
    final matched = phase == ApplicationPhase.matched;
    final rejected = phase == ApplicationPhase.rejected;

    final borderColor = matched ? AppColors.okFg : AppColors.line;
    final borderWidth = matched ? 1.4 : 1.0;

    final card = Opacity(
      opacity: rejected ? 0.62 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: rejected ? null : AppShadows.sm,
        ),
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  job != null ? JobFormat.workDate(job.workDate) : '일감 정보 없음',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink3,
                  ),
                ),
                _PhasePill(phase: phase),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              job?.regionName ?? '-',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: rejected ? AppColors.ink2 : AppColors.ink,
              ),
            ),
            if (job != null && job.jobTypeTags.isNotEmpty) ...[
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in job.jobTypeTags) _Tag(label: t),
                ],
              ),
            ],
            const SizedBox(height: 10),
            // 정본 일감 카드 패턴과 동일: 더 옅은 구분선(line-2).
            const Divider(height: 1, color: AppColors.line2),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _MetaLine(application: application),
                if (job != null) _Price(amount: job.amount, dim: rejected),
              ],
            ),
            if (matched) ...[
              const SizedBox(height: 11),
              SizedBox(
                height: 44,
                width: double.infinity,
                child: FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: const Text(
                    '발주자에게 연락 · 상세보기',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: card,
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.application});
  final JobApplication application;

  @override
  Widget build(BuildContext context) {
    if (application.isPriority) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.confirmation_number_outlined,
              size: 14, color: AppColors.red),
          SizedBox(width: 4),
          Text(
            '우선배차권 사용',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.red,
            ),
          ),
        ],
      );
    }
    return const Text(
      '일반 지원',
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppColors.ink2,
      ),
    );
  }
}

class _PhasePill extends StatelessWidget {
  const _PhasePill({required this.phase});
  final ApplicationPhase phase;

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color bg;
    late final Color fg;
    switch (phase) {
      case ApplicationPhase.matched:
        label = '배차 성사';
        bg = AppColors.okBg;
        fg = AppColors.okFg;
      case ApplicationPhase.waiting:
        label = '대기중';
        bg = const Color(0xFFE4EDFF);
        fg = AppColors.blueInk;
      case ApplicationPhase.rejected:
        label = '미선정';
        bg = AppColors.line;
        fg = AppColors.ink2;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FE),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.blueInk,
        ),
      ),
    );
  }
}

class _Price extends StatelessWidget {
  const _Price({required this.amount, this.dim = false});
  final int amount;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: JobFormat.amount(amount)),
          const TextSpan(
            text: '원',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: dim ? AppColors.ink2 : AppColors.navy,
        ),
      ),
    );
  }
}

/// 지정배차 수신 배너(목업 지정배차건 안내 + 5분 윈도우 카운트다운).
class DesignationBanner extends StatefulWidget {
  const DesignationBanner({super.key, required this.job, this.onTap});

  final Job job;
  final VoidCallback? onTap;

  @override
  State<DesignationBanner> createState() => _DesignationBannerState();
}

class _DesignationBannerState extends State<DesignationBanner> {
  late final Stream<void> _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Stream.periodic(const Duration(seconds: 1));
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primaryBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.navy, width: 1.4),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_user, size: 18, color: AppColors.navy),
                const SizedBox(width: 6),
                const Text(
                  '지정배차 도착',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const Spacer(),
                _Countdown(endsAt: widget.job.designateWindowExpires, ticker: _ticker),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.job.regionName} · ${JobFormat.workDate(widget.job.workDate)}',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '나를 지정한 일감이에요. 5분 내 미수락 시 일반 선착순으로 전환돼요.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.endsAt, required this.ticker});
  final DateTime? endsAt;
  final Stream<void> ticker;

  @override
  Widget build(BuildContext context) {
    if (endsAt == null) return const SizedBox.shrink();
    return StreamBuilder<void>(
      stream: ticker,
      builder: (context, _) {
        final d = endsAt!.difference(DateTime.now());
        final secs = d.isNegative ? 0 : d.inSeconds;
        final mm = (secs ~/ 60).toString().padLeft(2, '0');
        final ss = (secs % 60).toString().padLeft(2, '0');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$mm:$ss',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}
