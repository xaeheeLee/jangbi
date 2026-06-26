import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/supabase/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/primary_button.dart';
import '../auth/auth_providers.dart';
import 'job_format.dart';
import 'job_models.dart';
import 'job_providers.dart';
import 'widgets/job_map.dart';

/// 일감 상세(목업 ③). 지도 placeholder + 작업정보 + 지원 버튼.
/// 지원은 status 별로 apply_with_priority / apply_general / apply_designated RPC 호출.
class JobDetailScreen extends ConsumerStatefulWidget {
  const JobDetailScreen({super.key, required this.jobId});
  final String jobId;

  @override
  ConsumerState<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends ConsumerState<JobDetailScreen> {
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final jobAsync = ref.watch(jobDetailProvider(widget.jobId));
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('일감 상세'),
        centerTitle: true,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: AppColors.line),
        ),
      ),
      body: jobAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(mapJobRpcError(e),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.ink2)),
          ),
        ),
        data: (job) {
          if (job == null) {
            return const Center(child: Text('일감을 찾을 수 없습니다.'));
          }
          return _Body(
            job: job,
            submitting: _submitting,
            onApply: ({bool priority = false}) =>
                _apply(job, priority: priority),
          );
        },
      ),
    );
  }

  Future<void> _apply(Job job, {bool priority = false}) async {
    // 우선 윈도우 + 장비 불일치 시 확인 팝업 후 force_apply.
    Future<void> run() async {
      setState(() => _submitting = true);
      try {
        final client = SupabaseService.client;
        final uid = client.auth.currentUser?.id;
        Map<String, dynamic> res;
        switch (job.status) {
          case JobStatus.priorityWindow:
            res = (await client.rpc('apply_with_priority', params: {
              'p_job_id': job.id,
              'p_applicant_id': uid,
              'p_force_apply': true,
            })) as Map<String, dynamic>;
          case JobStatus.open:
            res = (await client.rpc('apply_general', params: {
              'p_job_id': job.id,
              'p_applicant_id': uid,
              'p_force_apply': true,
            })) as Map<String, dynamic>;
          case JobStatus.designatedWindow:
            final pw = await _askDesignatePassword();
            if (pw == null) {
              setState(() => _submitting = false);
              return;
            }
            res = (await client.rpc('apply_designated', params: {
              'p_job_id': job.id,
              'p_applicant_id': uid,
              'p_password': pw,
            })) as Map<String, dynamic>;
          default:
            throw Exception('JOB_UNAVAILABLE');
        }
        if (!mounted) return;
        final status = res['status'] as String?;
        final msg = status == 'matched'
            ? '배차가 성사되었습니다.'
            : '지원이 접수되었습니다. 마감 시 결과가 안내됩니다.';
        _snack(msg);
        ref.invalidate(jobDetailProvider(widget.jobId));
      } catch (e) {
        if (mounted) _snack(mapJobRpcError(e));
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
    }

    // priority 윈도우에서 장비 불일치면 확인 팝업.
    if (priority && _hasEquipmentMismatch(job)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('장비 요건 불일치'),
          content: const Text('보유 장비가 일감 요건과 일치하지 않습니다.\n그래도 지원하시겠습니까?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('지원')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await run();
  }

  /// 본인 보유 장비 vs 일감 요건 단순 비교(카테고리 기준). 최종 판정은 RPC.
  bool _hasEquipmentMismatch(Job job) {
    if (!Env.isSupabaseConfigured) return false;
    final myCat =
        ref.read(profileProvider).value?['equipment_category'] as String?;
    if (myCat == null) return true;
    final cats = {
      if (job.requiredCategory != null) job.requiredCategory,
      ...job.options.map((o) => o.category),
    };
    if (cats.isEmpty) return false;
    return !cats.contains(myCat);
  }

  Future<String?> _askDesignatePassword() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('지정배차 지원'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '지정 비밀번호',
            hintText: '발주자가 알려준 비밀번호',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('지원'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.job,
    required this.submitting,
    required this.onApply,
  });
  final Job job;
  final bool submitting;
  final void Function({bool priority}) onApply;

  @override
  Widget build(BuildContext context) {
    final referral = (job.amount * 0.10).round();
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              JobMap(lat: job.lat, lng: job.lng, label: job.regionName),
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                transform: Matrix4.translationValues(0, -20, 0),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 상태 pill 단독(좌측 정렬).
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _statusPill(),
                    ),
                    const SizedBox(height: 11),
                    Text(
                      job.regionName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${job.address ?? job.regionName} · ${JobFormat.workDate(job.workDate)} 시작',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('일감 금액',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink3)),
                            const SizedBox(height: 3),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: JobFormat.amount(job.amount)),
                                  const TextSpan(
                                      text: '원',
                                      style: TextStyle(fontSize: 13)),
                                ],
                                style: const TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navy,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('소개비(10%)',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink2)),
                            const SizedBox(height: 2),
                            Text(
                              '${JobFormat.amount(referral)}p 차감',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (job.status == JobStatus.priorityWindow &&
                        job.priorityWindowEndsAt != null) ...[
                      const SizedBox(height: 15),
                      _RingCountdown(endsAt: job.priorityWindowEndsAt!),
                    ],
                    const SizedBox(height: 16),
                    if (job.jobTypeTags.isNotEmpty)
                      _InfoRow(
                          k: '작업 종류', v: job.jobTypeTags.join(' · ')),
                    _InfoRow(k: '장비 조건', v: _equipmentLine(job)),
                    if (job.paymentMethod != null)
                      _InfoRow(k: '결제 방식', v: job.paymentMethod!),
                    if ((job.description ?? '').isNotEmpty)
                      _InfoRow(k: '작업 정보', v: job.description!),
                    if ((job.memo ?? '').isNotEmpty)
                      _InfoRow(k: '메모', v: job.memo!),
                  ],
                ),
              ),
            ],
          ),
        ),
        _ActionBar(job: job, submitting: submitting, onApply: onApply),
      ],
    );
  }

  Widget _statusPill() {
    late final String label;
    late final Color bg;
    late final Color fg;
    switch (job.status) {
      case JobStatus.priorityWindow:
        label = '우선배차 진행 중';
        bg = AppColors.red;
        fg = Colors.white;
      case JobStatus.designatedWindow:
        label = '지정배차 진행 중';
        bg = AppColors.navy;
        fg = Colors.white;
      case JobStatus.open:
        label = '모집중';
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
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
    );
  }

  static String _equipmentLine(Job job) {
    final parts = <String>[];
    if (job.requiredCategory != null) {
      parts.add(JobFormat.equipmentLabel(job.requiredCategory!, job.requiredModel));
    }
    for (final o in job.options) {
      parts.add(JobFormat.equipmentLabel(o.category, o.minModel));
    }
    if (parts.isEmpty) return '장비 무관';
    return parts.join(' · ');
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.job,
    required this.submitting,
    required this.onApply,
  });
  final Job job;
  final bool submitting;
  final void Function({bool priority}) onApply;

  @override
  Widget build(BuildContext context) {
    final closed = job.status.isClosed;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      child: SafeArea(
        top: false,
        child: _buildButtons(context, closed),
      ),
    );
  }

  Widget _buildButtons(BuildContext context, bool closed) {
    if (closed) {
      return const PrimaryButton(
        label: '마감된 일감입니다',
        enabled: false,
      );
    }

    if (job.status == JobStatus.designatedWindow) {
      return PrimaryButton(
        label: '지정배차 지원',
        loading: submitting,
        onPressed: () => onApply(),
      );
    }

    if (job.status == JobStatus.priorityWindow) {
      // .actions: 일반 지원(ghost) | 우선 지원(red) 1 : 1.35 비율.
      return Row(
        children: [
          Expanded(
            flex: 100,
            child: PrimaryButton(
              label: '일반 지원',
              variant: PrimaryButtonVariant.ghost,
              onPressed: submitting ? null : () => onApply(),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            flex: 135,
            child: PrimaryButton(
              label: '우선 지원',
              variant: PrimaryButtonVariant.red,
              loading: submitting,
              onPressed: () => onApply(priority: true),
            ),
          ),
        ],
      );
    }

    // open
    return PrimaryButton(
      label: '일반 지원',
      loading: submitting,
      onPressed: () => onApply(),
    );
  }
}

/// 상세 링 카운트다운(.ring): 38px 원형, red 잔여비율 호 + #FBD5D5 트랙,
/// 가운데 숫자. 옆에 "우선배차 진행 중 / 배차권 보유자 우선 지원 가능".
/// #FEF1EC 박스(radius 14).
class _RingCountdown extends StatefulWidget {
  const _RingCountdown({required this.endsAt});
  final DateTime endsAt;

  @override
  State<_RingCountdown> createState() => _RingCountdownState();
}

class _RingCountdownState extends State<_RingCountdown> {
  late final Stream<void> _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Stream.periodic(const Duration(seconds: 1));
  }

  int get _secs {
    final d = widget.endsAt.difference(DateTime.now());
    return d.isNegative ? 0 : d.inSeconds;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: _ticker,
      builder: (context, _) {
        final secs = _secs;
        final ratio = (secs / 30).clamp(0.0, 1.0);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.redBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: CustomPaint(
                  painter: _RingPainter(ratio),
                  child: Center(
                    child: Text(
                      '$secs',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.red,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '우선배차 진행 중',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '배차권 보유자 우선 지원 가능',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink2,
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

class _RingPainter extends CustomPainter {
  const _RingPainter(this.ratio);
  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = AppColors.ringTrack;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = AppColors.red;
    canvas.drawCircle(center, radius, track);
    const start = -1.5707963; // -90deg (12시)
    final sweep = 6.2831853 * ratio;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.ratio != ratio;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.k, required this.v});
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    // .irow: padding 14px 0, border-bottom 1px line-2, k=ink-3, v=ink/w700/우측정렬.
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink3)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(v,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    height: 1.5)),
          ),
        ],
      ),
    );
  }
}

