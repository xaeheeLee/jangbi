import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/supabase/supabase_service.dart';
import '../auth/auth_providers.dart';
import '../jobs/job_models.dart';

/// 캘린더 이벤트 색 구분(점/좌측 컬러바).
/// navy = 배차 확정/받은 일감(matched), red = 우선(우선배차 윈도우 진행 중).
enum CalendarMarkKind { dispatch, priority }

/// 캘린더 한 건(내 일감 = 발주 or 매칭). 점/바 색은 [kind].
class CalendarEvent {
  const CalendarEvent({required this.job, required this.kind});

  final Job job;
  final CalendarMarkKind kind;

  /// 그룹 키(로컬 날짜의 자정).
  DateTime get day =>
      DateTime(job.workDate.year, job.workDate.month, job.workDate.day);
}

CalendarMarkKind _kindOf(Job j) {
  // 우선배차 윈도우 진행 중 = red, 그 외(배차 확정/모집/받은 일감) = navy.
  if (j.status == JobStatus.priorityWindow) return CalendarMarkKind.priority;
  return CalendarMarkKind.dispatch;
}

/// 내 일감(발주 poster_id=내uid 또는 매칭 matched_worker_id=내uid).
/// work_date 로 그룹. stream() 은 필터 1개만 지원하므로 .or() 로 한 번에 읽는다.
/// 읽기 전용 — 기능/RPC 변경 없음(쿼리만 신규).
final calendarJobsProvider = FutureProvider<List<CalendarEvent>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (!Env.isSupabaseConfigured || session == null) return const [];

  final uid = session.user.id;
  final rows = await SupabaseService.client
      .from('jobs')
      .select('*, job_equipment_options(category, min_model)')
      .or('poster_id.eq.$uid,matched_worker_id.eq.$uid')
      .order('work_date');

  return rows.map((m) {
    final job = Job.fromMap(m);
    return CalendarEvent(job: job, kind: _kindOf(job));
  }).toList();
});

/// 날짜(자정 키) → 그 날의 이벤트들. 시간순.
final calendarEventsByDayProvider =
    Provider<Map<DateTime, List<CalendarEvent>>>((ref) {
  final events = ref.watch(calendarJobsProvider).value ?? const [];
  final map = <DateTime, List<CalendarEvent>>{};
  for (final e in events) {
    (map[e.day] ??= []).add(e);
  }
  for (final list in map.values) {
    list.sort((a, b) => a.job.workDate.compareTo(b.job.workDate));
  }
  return map;
});
