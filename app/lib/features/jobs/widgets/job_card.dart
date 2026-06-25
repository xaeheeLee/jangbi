import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../job_format.dart';
import '../job_models.dart';

/// 일감 목록 카드(목업 ② 그대로).
/// 우선배차=red 테두리+오렌지 카운트다운 바, 지정=navy 테두리, 일반=line 테두리.
/// 완료/마감 건은 잠금 오버레이.
class JobCard extends StatelessWidget {
  const JobCard({super.key, required this.job, this.onTap});

  final Job job;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isPriority = job.status == JobStatus.priorityWindow;
    final isDesignatedWindow = job.status == JobStatus.designatedWindow;
    final isClosed = job.status.isClosed;

    Color borderColor;
    double borderWidth;
    List<BoxShadow> shadow;
    if (isClosed) {
      borderColor = AppColors.line;
      borderWidth = 1;
      shadow = const [];
    } else if (isPriority) {
      // 우선배차: 1.6px red 테두리 + 빨강 글로우.
      borderColor = AppColors.red;
      borderWidth = 1.6;
      shadow = AppShadows.prioGlow;
    } else if (isDesignatedWindow || job.isDesignated) {
      borderColor = AppColors.navy;
      borderWidth = 1.6;
      shadow = AppShadows.sm;
    } else {
      // 모집중: 1px line + shadow-sm.
      borderColor = AppColors.line;
      borderWidth = 1;
      shadow = AppShadows.sm;
    }

    final card = Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: shadow,
      ),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                JobFormat.workDate(job.workDate),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink3,
                ),
              ),
              _StatusPill(job: job),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            job.regionName,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          if (job.jobTypeTags.isNotEmpty) ...[
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in job.jobTypeTags) _Tag(label: t, gray: isClosed),
              ],
            ),
          ],
          if (!isClosed) ...[
            const SizedBox(height: 13),
            const Divider(height: 1, color: AppColors.line2),
            const SizedBox(height: 13),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    _equipmentSummary(job),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _Price(amount: job.amount),
              ],
            ),
          ],
          if (isPriority && job.priorityWindowEndsAt != null) ...[
            const SizedBox(height: 10),
            _CountdownBar(endsAt: job.priorityWindowEndsAt!),
          ],
        ],
      ),
    );

    final tappable = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: card,
    );

    if (!isClosed) return tappable;

    // 마감 건: 반투명 + 잠금 칩.
    return Stack(
      children: [
        Opacity(opacity: 0.55, child: tappable),
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: AppShadows.card,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 18, color: Color(0xFF64748B)),
                    const SizedBox(width: 8),
                    Text(
                      _closedLabel(job.status),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _equipmentSummary(Job job) {
    if (job.isDesignated) return '지정 기사 우선';
    final parts = <String>[];
    if (job.requiredCategory != null) {
      parts.add(_eqLabel(job.requiredCategory!, job.requiredModel));
    }
    for (final o in job.options) {
      parts.add(_eqLabel(o.category, o.minModel));
    }
    if (parts.isEmpty) return '장비 무관';
    return parts.join(' · ');
  }

  static String _eqLabel(String category, String? model) =>
      JobFormat.equipmentLabel(category, model);

  static String _closedLabel(JobStatus s) {
    switch (s) {
      case JobStatus.matched:
        return '배차완료';
      case JobStatus.completed:
        return '작업완료';
      case JobStatus.expired:
        return '마감';
      default:
        return '종료';
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color bg;
    late final Color fg;
    switch (job.status) {
      case JobStatus.priorityWindow:
        label = '우선배차';
        bg = AppColors.red;
        fg = Colors.white;
      case JobStatus.designatedWindow:
        label = '지정배차';
        bg = AppColors.navy;
        fg = Colors.white;
      case JobStatus.open:
        label = job.isDesignated ? '모집중(전환)' : '모집중';
        bg = const Color(0xFFE4EDFF);
        fg = AppColors.blueInk;
      case JobStatus.matched:
        label = '배차완료';
        bg = AppColors.line;
        fg = AppColors.ink2;
      default:
        label = '종료';
        bg = AppColors.line;
        fg = AppColors.ink2;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.gray = false});
  final String label;
  final bool gray;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: gray ? const Color(0xFFEEF1F5) : const Color(0xFFEAF1FE),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: gray ? const Color(0xFF475569) : AppColors.blueInk,
        ),
      ),
    );
  }
}

class _Price extends StatelessWidget {
  const _Price({required this.amount});
  final int amount;

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
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
        ),
      ),
    );
  }
}

/// 우선배차 마감 카운트다운 바(오렌지). 1초마다 갱신.
class _CountdownBar extends StatefulWidget {
  const _CountdownBar({required this.endsAt});
  final DateTime endsAt;

  @override
  State<_CountdownBar> createState() => _CountdownBarState();
}

class _CountdownBarState extends State<_CountdownBar> {
  late Duration _remaining;
  late final Stream<void> _ticker;

  @override
  void initState() {
    super.initState();
    _remaining = _calc();
    _ticker = Stream.periodic(const Duration(seconds: 1));
  }

  Duration _calc() {
    final d = widget.endsAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: _ticker,
      builder: (context, _) {
        _remaining = _calc();
        final secs = _remaining.inSeconds;
        // 30초 윈도우 가정의 진행률(0~1). app_settings 기본 30초.
        final ratio = (secs / 30).clamp(0.0, 1.0);
        // .countdown: #FEF1EC 박스 + 시계 아이콘 + 라벨 + 잔여초(인라인).
        // 아래 트랙(#FBE3D6) + orange→red 그라데이션 채움 바.
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: AppColors.redBg,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.schedule, size: 13, color: AppColors.orange),
                  const SizedBox(width: 6),
                  const Text(
                    '우선배차 마감까지',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.orange,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$secs초',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.orange,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  children: [
                    Container(height: 6, color: AppColors.countdownTrack),
                    FractionallySizedBox(
                      widthFactor: ratio,
                      child: Container(
                        height: 6,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.orange, AppColors.red],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
