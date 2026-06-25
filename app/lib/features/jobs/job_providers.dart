import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/supabase/supabase_service.dart';
import 'job_models.dart';

/// 일감 목록 필터(지역코드·장비 카테고리). null=전체.
class JobsFilter {
  const JobsFilter({this.regionCode, this.category});
  final String? regionCode;
  final String? category;

  JobsFilter copyWith({Object? regionCode = _sentinel, Object? category = _sentinel}) =>
      JobsFilter(
        regionCode:
            regionCode == _sentinel ? this.regionCode : regionCode as String?,
        category: category == _sentinel ? this.category : category as String?,
      );

  static const _sentinel = Object();
}

/// 현재 적용 중인 목록 필터(지역·장비 카테고리).
class JobsFilterNotifier extends Notifier<JobsFilter> {
  @override
  JobsFilter build() => const JobsFilter();

  void update(JobsFilter Function(JobsFilter) fn) => state = fn(state);
}

final jobsFilterProvider =
    NotifierProvider<JobsFilterNotifier, JobsFilter>(JobsFilterNotifier.new);

/// jobs 실시간 스트림(열람 가능 건은 RLS 가 제한). 옵션은 별도 조회 후 병합.
/// stream() 은 조인을 지원하지 않으므로 옵션은 [jobOptionsProvider] 로 따로 받는다.
final _jobsStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  // 미설정(골격 실행)에서는 빈 목록으로 즉시 확정(무한 로딩 방지).
  if (!Env.isSupabaseConfigured) {
    return Stream.value(const <Map<String, dynamic>>[]);
  }
  return SupabaseService.client
      .from('jobs')
      .stream(primaryKey: ['id']).order('work_date');
});

/// 전체 job_equipment_options(열람 가능 일감의 옵션만 RLS 노출).
final _jobOptionsProvider =
    FutureProvider<Map<String, List<JobEquipmentOption>>>((ref) async {
  if (!Env.isSupabaseConfigured) return const {};
  // 스트림이 갱신될 때 옵션도 다시 읽도록 의존성 등록.
  ref.watch(_jobsStreamProvider);
  final rows = await SupabaseService.client
      .from('job_equipment_options')
      .select('job_id, category, min_model');
  final map = <String, List<JobEquipmentOption>>{};
  for (final r in rows) {
    final jobId = r['job_id'] as String;
    (map[jobId] ??= []).add(JobEquipmentOption.fromMap(r));
  }
  return map;
});

/// 필터 적용된 일감 목록. 스트림 + 옵션 병합 + 클라이언트 필터.
final jobsListProvider = Provider<AsyncValue<List<Job>>>((ref) {
  final streamAsync = ref.watch(_jobsStreamProvider);
  final optionsAsync = ref.watch(_jobOptionsProvider);
  final filter = ref.watch(jobsFilterProvider);

  return streamAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
    data: (rows) {
      final options = optionsAsync.value ?? const {};
      var jobs = rows.map((m) {
        final merged = Map<String, dynamic>.of(m);
        merged['job_equipment_options'] = (options[m['id']] ?? const [])
            .map((o) => {'category': o.category, 'min_model': o.minModel})
            .toList();
        return Job.fromMap(merged);
      }).where((j) {
        // 닫힌(완료·취소·만료) 건은 목록 하단에 노출하되 별도 처리 없이 모두 보임.
        if (filter.regionCode != null && j.regionCode != filter.regionCode) {
          return false;
        }
        if (filter.category != null) {
          final cats = {
            if (j.requiredCategory != null) j.requiredCategory,
            ...j.options.map((o) => o.category),
          };
          if (!cats.contains(filter.category)) return false;
        }
        return true;
      }).toList();
      // 활성 건 우선, 그다음 작업일 오름차순.
      jobs.sort((a, b) {
        final ac = a.status.isClosed ? 1 : 0;
        final bc = b.status.isClosed ? 1 : 0;
        if (ac != bc) return ac - bc;
        return a.workDate.compareTo(b.workDate);
      });
      return AsyncValue.data(jobs);
    },
  );
});

/// 단일 일감 상세(옵션 조인 포함).
final jobDetailProvider =
    FutureProvider.family<Job?, String>((ref, jobId) async {
  if (!Env.isSupabaseConfigured) return null;
  final m = await SupabaseService.client
      .from('jobs')
      .select('*, job_equipment_options(category, min_model)')
      .eq('id', jobId)
      .maybeSingle();
  if (m == null) return null;
  return Job.fromMap(m);
});

/// 장비 카테고리 마스터.
final equipmentCategoriesProvider =
    FutureProvider<List<EquipmentCategory>>((ref) async {
  if (!Env.isSupabaseConfigured) return const [];
  final rows = await SupabaseService.client
      .from('equipment_categories')
      .select('code, label, sort_order')
      .order('sort_order');
  return rows.map(EquipmentCategory.fromMap).toList();
});

/// 장비 모델 마스터(활성만).
final equipmentModelsProvider =
    FutureProvider<List<EquipmentModel>>((ref) async {
  if (!Env.isSupabaseConfigured) return const [];
  final rows = await SupabaseService.client
      .from('equipment_models')
      .select('category_code, code, label, sort_order')
      .eq('is_active', true)
      .order('sort_order');
  return rows.map(EquipmentModel.fromMap).toList();
});
