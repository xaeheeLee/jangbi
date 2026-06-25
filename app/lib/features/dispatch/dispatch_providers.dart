import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/supabase/supabase_service.dart';
import '../auth/auth_providers.dart';
import '../jobs/job_models.dart';
import 'dispatch_models.dart';

/// 내 priority_tickets 실시간 스트림(owner_id=내 uid). RLS 가 본인 행만 노출.
/// stream() 은 필터 1개만 지원 → owner_id 로 받고 사용/만료 구분은 클라이언트에서.
final _myTicketsStreamProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  final session = ref.watch(sessionProvider);
  if (!Env.isSupabaseConfigured || session == null) {
    return Stream.value(const <Map<String, dynamic>>[]);
  }
  return SupabaseService.client
      .from('priority_tickets')
      .stream(primaryKey: ['id'])
      .eq('owner_id', session.user.id)
      .order('expires_at');
});

/// 내 배차권 전체(파싱본). 만료/사용 구분은 모델 게터로.
final myTicketsProvider = Provider<AsyncValue<List<PriorityTicket>>>((ref) {
  return ref.watch(_myTicketsStreamProvider).whenData(
        (rows) => rows.map(PriorityTicket.fromMap).toList(),
      );
});

/// 사용 가능한 배차권만(미사용·미만료). 만료 임박 순.
final availableTicketsProvider =
    Provider<AsyncValue<List<PriorityTicket>>>((ref) {
  return ref.watch(myTicketsProvider).whenData(
        (all) => all.where((t) => t.isAvailable).toList()
          ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt)),
      );
});

/// 사용 이력(used_at IS NOT NULL). 최근 사용 순.
final usedTicketsProvider = Provider<AsyncValue<List<PriorityTicket>>>((ref) {
  return ref.watch(myTicketsProvider).whenData(
        (all) => all.where((t) => t.isUsed).toList()
          ..sort((a, b) => b.usedAt!.compareTo(a.usedAt!)),
      );
});

/// 내 job_applications 실시간 스트림(applicant_id=내 uid).
final _myApplicationsStreamProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  final session = ref.watch(sessionProvider);
  if (!Env.isSupabaseConfigured || session == null) {
    return Stream.value(const <Map<String, dynamic>>[]);
  }
  return SupabaseService.client
      .from('job_applications')
      .stream(primaryKey: ['id'])
      .eq('applicant_id', session.user.id)
      .order('created_at', ascending: false);
});

/// 지원에 조인할 job 들. 지원 스트림이 갱신될 때 함께 재조회.
final _applicationJobsProvider =
    FutureProvider<Map<String, Job>>((ref) async {
  if (!Env.isSupabaseConfigured) return const {};
  final apps = ref.watch(_myApplicationsStreamProvider).value ?? const [];
  final ids = apps.map((a) => a['job_id'] as String).toSet().toList();
  if (ids.isEmpty) return const {};
  final rows = await SupabaseService.client
      .from('jobs')
      .select('*, job_equipment_options(category, min_model)')
      .inFilter('id', ids);
  final map = <String, Job>{};
  for (final r in rows) {
    final job = Job.fromMap(r);
    map[job.id] = job;
  }
  return map;
});

/// 내 지원/매칭 현황(일감 조인 병합). 매칭 성사 → 대기 → 미선정 순 정렬.
final myApplicationsProvider =
    Provider<AsyncValue<List<JobApplication>>>((ref) {
  final appsAsync = ref.watch(_myApplicationsStreamProvider);
  final jobsAsync = ref.watch(_applicationJobsProvider);

  return appsAsync.when(
    loading: () => const AsyncValue.loading(),
    error: AsyncValue.error,
    data: (rows) {
      final jobs = jobsAsync.value ?? const <String, Job>{};
      final apps = rows
          .map((m) =>
              JobApplication.fromMap(m, job: jobs[m['job_id'] as String]))
          .toList();
      int rank(ApplicationPhase p) => switch (p) {
            ApplicationPhase.matched => 0,
            ApplicationPhase.waiting => 1,
            ApplicationPhase.rejected => 2,
          };
      apps.sort((a, b) {
        final r = rank(a.phase) - rank(b.phase);
        if (r != 0) return r;
        return b.createdAt.compareTo(a.createdAt);
      });
      return AsyncValue.data(apps);
    },
  );
});

/// 나를 지정한 지정배차 일감(designate_target_id=내 uid 且 status='designated_window').
/// 5분 윈도우 진행 중인 수신 건만. 상단 배너로 노출.
final incomingDesignationsProvider = FutureProvider<List<Job>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (!Env.isSupabaseConfigured || session == null) return const [];
  // 지원 스트림 갱신 시 함께 재조회(수락하면 사라지도록).
  ref.watch(_myApplicationsStreamProvider);
  final rows = await SupabaseService.client
      .from('jobs')
      .select('*, job_equipment_options(category, min_model)')
      .eq('designate_target_id', session.user.id)
      .eq('status', 'designated_window')
      .order('work_date');
  return rows.map(Job.fromMap).toList();
});
