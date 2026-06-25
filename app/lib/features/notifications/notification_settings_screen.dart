import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/supabase/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/widgets/primary_button.dart';
import '../auth/auth_providers.dart';
import '../jobs/job_models.dart';
import '../jobs/job_providers.dart';

/// 알림 받을 지역 후보(지역 마스터 미존재 — 간단 상수, CLAUDE.md 허용 범위).
const _kRegionOptions = <String>[
  '서울',
  '경기',
  '인천',
  '강원',
  '충북',
  '충남',
  '대전',
  '세종',
  '전북',
  '전남',
  '광주',
  '경북',
  '경남',
  '대구',
  '울산',
  '부산',
  '제주',
];

/// 알림 설정(`/notifications/settings`). 지역 필터 + 장비 필터.
/// 저장 → profiles.notify_regions(text[]) / notify_equipment(jsonb) 본인 UPDATE.
/// 기능/RPC 변경 없음 — 본인 컬럼 UPDATE만.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  late Set<String> _regions;
  late Set<String> _categories;
  bool _initialized = false;
  bool _saving = false;

  /// profileProvider 값에서 현재 설정을 1회 로드한다.
  void _initFrom(Map<String, dynamic>? profile) {
    if (_initialized) return;
    _initialized = true;
    final regions = profile?['notify_regions'];
    _regions = <String>{
      if (regions is List)
        for (final r in regions) r.toString(),
    };
    _categories = _parseCategories(profile?['notify_equipment']);
  }

  /// notify_equipment(jsonb) → 카테고리 코드 집합.
  /// 형태 허용: {"categories": [...]} 또는 단순 [...] (방어적 파싱).
  static Set<String> _parseCategories(Object? raw) {
    if (raw is Map && raw['categories'] is List) {
      return {for (final c in raw['categories'] as List) c.toString()};
    }
    if (raw is List) {
      return {for (final c in raw) c.toString()};
    }
    return <String>{};
  }

  Future<void> _save() async {
    final session = ref.read(sessionProvider);
    if (!Env.isSupabaseConfigured || session == null) {
      _toast('로그인 후 저장할 수 있습니다.');
      return;
    }
    setState(() => _saving = true);
    try {
      await SupabaseService.client.from('profiles').update({
        'notify_regions': _regions.toList(),
        'notify_equipment': {'categories': _categories.toList()},
      }).eq('id', session.user.id);
      ref.invalidate(profileProvider);
      if (!mounted) return;
      _toast('알림 조건을 저장했어요.');
    } catch (e) {
      if (!mounted) return;
      _toast('저장에 실패했습니다: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    _initFrom(profile);
    final categories = ref.watch(equipmentCategoriesProvider).value ?? const [];

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text('알림 설정'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: AppColors.line),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          const _InfoBanner(),
          const SizedBox(height: 18),
          const _SectionLabel('지역'),
          _Card(
            child: _ChipWrap(
              options: [for (final r in _kRegionOptions) (code: r, label: r)],
              selected: _regions,
              onToggle: (code) => setState(() {
                _regions.contains(code)
                    ? _regions.remove(code)
                    : _regions.add(code);
              }),
            ),
          ),
          const SizedBox(height: 18),
          const _SectionLabel('장비'),
          _Card(
            child: categories.isEmpty
                ? const _CategoriesEmpty()
                : _ChipWrap(
                    options: [
                      for (final EquipmentCategory c in categories)
                        (code: c.code, label: c.label),
                    ],
                    selected: _categories,
                    onToggle: (code) => setState(() {
                      _categories.contains(code)
                          ? _categories.remove(code)
                          : _categories.add(code);
                    }),
                  ),
          ),
          const SizedBox(height: 26),
          PrimaryButton(
            label: '저장',
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// "이 조건의 새 일감만 알림" 안내(정본 톤 연파랑 박스).
class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE8FB)),
      ),
      child: const Row(
        children: [
          Icon(Icons.tune, size: 20, color: AppColors.blueInk),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              '선택한 지역·장비 조건에 맞는 새 일감만 알림으로 받아요. '
              '아무것도 선택하지 않으면 전체 일감 알림을 받습니다.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink2,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: AppColors.ink3,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.sm,
      ),
      child: child,
    );
  }
}

/// 다중선택 칩 묶음(Wrap). 선택=navy 채움 / 미선택=흰+line.
class _ChipWrap extends StatelessWidget {
  const _ChipWrap({
    required this.options,
    required this.selected,
    required this.onToggle,
  });
  final List<({String code, String label})> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          _SelectChip(
            label: o.label,
            selected: selected.contains(o.code),
            onTap: () => onToggle(o.code),
          ),
      ],
    );
  }
}

class _SelectChip extends StatelessWidget {
  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.navy : AppColors.card,
          borderRadius: BorderRadius.circular(999),
          border: selected
              ? null
              : Border.all(color: AppColors.line, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 15, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoriesEmpty extends StatelessWidget {
  const _CategoriesEmpty();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Text(
        '장비 목록을 불러오는 중입니다.',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.ink3,
        ),
      ),
    );
  }
}
