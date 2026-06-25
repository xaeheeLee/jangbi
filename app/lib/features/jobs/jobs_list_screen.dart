import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import 'job_models.dart';
import 'job_providers.dart';
import 'widgets/job_card.dart';

/// 일감 목록 화면(목업 ②). HomeShell '일감' 탭 본문.
/// ListHead + 가로 필터칩(지역·장비) + 카드 리스트 + 등록 FAB.
class JobsListScreen extends ConsumerWidget {
  const JobsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(jobsListProvider);
    final filter = ref.watch(jobsFilterProvider);
    final categories = ref.watch(equipmentCategoriesProvider).value ?? const [];

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: _AddFab(onTap: () => context.push('/job/create')),
      body: Column(
        children: [
          _FilterChips(filter: filter, categories: categories),
          const SizedBox(height: 4),
          Expanded(
            child: jobsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(message: e.toString()),
              data: (jobs) {
                if (jobs.isEmpty) return const _EmptyState();
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
                  itemCount: jobs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final job = jobs[i];
                    return JobCard(
                      job: job,
                      onTap: () => context.push('/job/${job.id}'),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChips extends ConsumerWidget {
  const _FilterChips({required this.filter, required this.categories});
  final JobsFilter filter;
  final List<EquipmentCategory> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void setCategory(String? code) {
      ref.read(jobsFilterProvider.notifier).update(
            (f) => f.copyWith(category: f.category == code ? null : code),
          );
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 7, 16, 4),
        children: [
          // 지역/전체 선택 칩(.chip.sel, 드롭다운 셰브런). 카테고리 null=전체.
          _Chip(
            label: '서울 전체',
            selected: filter.category == null,
            trailingChevron: true,
            onTap: () => setCategory(null),
          ),
          for (final c in categories) ...[
            const SizedBox(width: 7),
            _Chip(
              label: c.label,
              selected: filter.category == c.code,
              onTap: () => setCategory(c.code),
            ),
          ],
          const SizedBox(width: 7),
          // +필터(.chip.add, 점선). 추가 필터 진입(추후) — 현재 시각 일관성용.
          const _Chip(label: '+필터', dashed: true),
        ],
      ),
    );
  }
}

/// .chip 변형: sel(navy 채움) / out(흰+1.5px line) / add(점선 보더).
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    this.selected = false,
    this.dashed = false,
    this.trailingChevron = false,
    this.onTap,
  });
  final String label;
  final bool selected;
  final bool dashed;
  final bool trailingChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg = dashed
        ? AppColors.ink2
        : (selected ? Colors.white : AppColors.ink);
    final child = Container(
      height: 34,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: selected && !dashed ? AppColors.navy : AppColors.card,
        borderRadius: BorderRadius.circular(999),
        border: selected && !dashed
            ? null
            : Border.all(
                color: dashed ? AppColors.dashBorder : AppColors.line,
                width: 1.5,
              ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          if (trailingChevron) ...[
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, size: 15, color: fg),
          ],
        ],
      ),
    );
    return onTap == null ? child : GestureDetector(onTap: onTap, child: child);
  }
}

/// .fab.navy: 56x56, radius 19, navy 그라데이션 + shadow-lift, 아이콘 26.
class _AddFab extends StatelessWidget {
  const _AddFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A4AA6), AppColors.navy],
          ),
          borderRadius: BorderRadius.circular(19),
          boxShadow: AppShadows.lift,
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 26),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.inbox_outlined, size: 48, color: AppColors.ink3),
          SizedBox(height: 12),
          Text(
            '조건에 맞는 일감이 없습니다.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.red),
            const SizedBox(height: 12),
            const Text(
              '일감을 불러오지 못했습니다.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.ink2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.ink3),
            ),
          ],
        ),
      ),
    );
  }
}
