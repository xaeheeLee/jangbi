import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../jobs/job_format.dart';
import '../jobs/job_models.dart';
import 'calendar_providers.dart';

/// 캘린더 탭(crop_calendar.png 기준). 월 그리드 + 선택일 일감 카드.
/// 데이터는 calendarJobsProvider(읽기 전용). 기능/RPC 변경 없음 — 비주얼만.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  /// 현재 보고 있는 월(해당 월 1일).
  late DateTime _month;

  /// 선택된 날짜(자정).
  late DateTime _selected;

  static final _today = _dayKey(DateTime.now());

  @override
  void initState() {
    super.initState();
    _selected = _today;
    _month = DateTime(_today.year, _today.month);
  }

  static DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final byDay = ref.watch(calendarEventsByDayProvider);
    final selectedEvents = byDay[_selected] ?? const [];

    return Container(
      color: AppColors.card,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          _MonthHeader(
            month: _month,
            onPrev: () => _shiftMonth(-1),
            onNext: () => _shiftMonth(1),
          ),
          const SizedBox(height: 14),
          const _WeekdayRow(),
          const SizedBox(height: 6),
          _MonthGrid(
            month: _month,
            selected: _selected,
            today: _today,
            byDay: byDay,
            onSelect: (d) => setState(() => _selected = d),
          ),
          const SizedBox(height: 20),
          _SelectedHeader(
            day: _selected,
            today: _today,
            count: selectedEvents.length,
          ),
          const SizedBox(height: 12),
          if (selectedEvents.isEmpty)
            const _EmptyDay()
          else
            for (final e in selectedEvents) ...[
              _EventCard(
                event: e,
                onTap: () => context.push('/job/${e.job.id}'),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

/// "2026년 6월"(좌, 굵게) + ‹ › 흰 원형 버튼(우).
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  static final _fmt = DateFormat('yyyy년 M월', 'ko_KR');

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          _fmt.format(month),
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: AppColors.ink,
          ),
        ),
        const Spacer(),
        _NavButton(icon: Icons.chevron_left, onTap: onPrev),
        const SizedBox(width: 8),
        _NavButton(icon: Icons.chevron_right, onTap: onNext),
      ],
    );
  }
}

/// 월 이동 흰 원형 버튼(테두리 line + shadow-sm).
class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.card,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.line),
          boxShadow: AppShadows.sm,
        ),
        child: Icon(icon, size: 20, color: AppColors.ink2),
      ),
    );
  }
}

/// 요일 행: 일(빨강) 월~금(ink-3) 토(파랑). 작은 캡션.
class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  static const _labels = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: Text(
                _labels[i],
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: i == 0
                      ? AppColors.red
                      : (i == 6 ? AppColors.blue : AppColors.ink3),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 날짜 그리드(7열). 빈 셀 + 날짜셀(오늘/선택 = 네이비 라운드 정사각 + 흰 숫자).
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.today,
    required this.byDay,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final Map<DateTime, List<CalendarEvent>> byDay;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // 일요일=0 으로 정렬(DateTime.weekday: 월=1..일=7).
    final leadBlanks = first.weekday % 7;
    final totalCells = leadBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: [
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: _cell(r * 7 + c - leadBlanks)),
            ],
          ),
      ],
    );
  }

  Widget _cell(int dayNum) {
    if (dayNum < 0 ||
        dayNum >= DateTime(month.year, month.month + 1, 0).day) {
      return const SizedBox(height: 50);
    }
    final date = DateTime(month.year, month.month, dayNum + 1);
    final weekday = date.weekday % 7; // 0=일, 6=토
    final isSelected = date == selected;
    final isToday = date == today;
    final highlight = isSelected || isToday;
    final events = byDay[date] ?? const [];

    Color numColor;
    if (highlight) {
      numColor = Colors.white;
    } else if (weekday == 0) {
      numColor = AppColors.red;
    } else if (weekday == 6) {
      numColor = AppColors.blue;
    } else {
      numColor = AppColors.ink;
    }

    return GestureDetector(
      onTap: () => onSelect(date),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 50,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: highlight
                  ? BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(11),
                    )
                  : null,
              child: Text(
                '${dayNum + 1}',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: numColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 3),
            _Dots(events: events, onHighlight: highlight),
          ],
        ),
      ),
    );
  }
}

/// 날짜 아래 이벤트 점(최대 2개). navy=배차, red=우선.
/// 선택/오늘 셀(네이비 배경) 위에서는 흰 점으로 대비.
class _Dots extends StatelessWidget {
  const _Dots({required this.events, required this.onHighlight});
  final List<CalendarEvent> events;
  final bool onHighlight;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox(height: 5);
    final shown = events.take(2).toList();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: onHighlight
                  ? Colors.white
                  : (shown[i].kind == CalendarMarkKind.priority
                      ? AppColors.red
                      : AppColors.navy),
            ),
          ),
        ],
      ],
    );
  }
}

/// 선택일 헤더 "6월 15일 (월) [오늘·N건]" + 범례.
class _SelectedHeader extends StatelessWidget {
  const _SelectedHeader({
    required this.day,
    required this.today,
    required this.count,
  });

  final DateTime day;
  final DateTime today;
  final int count;

  static final _fmt = DateFormat('M월 d일 (E)', 'ko_KR');

  @override
  Widget build(BuildContext context) {
    final isToday = day == today;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          _fmt.format(day),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          isToday ? '오늘 · $count건' : '$count건',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.blueInk,
          ),
        ),
        const Spacer(),
        const _LegendDot(color: AppColors.navy, label: '배차'),
        const SizedBox(width: 10),
        const _LegendDot(color: AppColors.red, label: '우선'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink2,
          ),
        ),
      ],
    );
  }
}

/// 선택일 일감 카드: 좌측 컬러바 + 제목 + pill + 서브(시간·장비·금액).
class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, this.onTap});
  final CalendarEvent event;
  final VoidCallback? onTap;

  static final _time = DateFormat('HH:mm', 'ko_KR');

  @override
  Widget build(BuildContext context) {
    final job = event.job;
    final isPriority = event.kind == CalendarMarkKind.priority;
    final barColor = isPriority ? AppColors.red : AppColors.navy;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
          boxShadow: AppShadows.sm,
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 좌측 컬러바(배차확정=navy / 우선=red).
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(18),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _title(job),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _EventPill(event: event),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _subtitle(job),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink2,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _title(Job job) {
    final model = _model(job);
    return model == null
        ? '${job.regionName} 현장'
        : '${job.regionName} 현장 · $model';
  }

  String? _model(Job job) {
    if (job.requiredModel != null && job.requiredModel!.isNotEmpty) {
      return job.requiredModel;
    }
    for (final o in job.options) {
      if (o.minModel != null && o.minModel!.isNotEmpty) return o.minModel;
    }
    return null;
  }

  String _subtitle(Job job) {
    final cat = job.requiredCategory ?? job.options.firstOrNull?.category;
    final eq = cat == null
        ? '장비 무관'
        : '굴착기 ${JobFormat.categoryLabel(cat)}';
    return '${_time.format(job.workDate)} · $eq · ${JobFormat.amount(job.amount)}원';
  }
}

/// 카드 상태 pill: 배차 확정=green / 우선 지원중=red. 그 외 모집중=blue.
class _EventPill extends StatelessWidget {
  const _EventPill({required this.event});
  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color bg;
    late final Color fg;

    if (event.kind == CalendarMarkKind.priority) {
      label = '우선 지원중';
      bg = AppColors.red;
      fg = Colors.white;
    } else {
      switch (event.job.status) {
        case JobStatus.matched:
        case JobStatus.completed:
          label = '배차 확정';
          bg = AppColors.okBg;
          fg = AppColors.okFg;
        case JobStatus.designatedWindow:
          label = '지정배차';
          bg = AppColors.navy;
          fg = Colors.white;
        default:
          label = '모집중';
          bg = AppColors.pillOpenBg;
          fg = AppColors.blueInk;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}

/// 선택일 일감 없음.
class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: const Column(
        children: [
          Icon(Icons.event_available_outlined, size: 32, color: AppColors.ink3),
          SizedBox(height: 10),
          Text(
            '이 날짜에는 일정이 없습니다.',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.ink2,
            ),
          ),
        ],
      ),
    );
  }
}
