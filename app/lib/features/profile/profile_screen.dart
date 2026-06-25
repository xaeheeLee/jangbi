import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_providers.dart';
import '../jobs/job_format.dart';

/// MY 탭 본문(정본 §7 "프로필 카드 + 메뉴 리스트").
/// 프로필 카드(이름·회원번호·별점/배차수·정회원 배지) + 자격 검증 신뢰배지 +
/// 메뉴 리스트(내 장비·서류·차단·알림·약관) + 로그아웃.
/// 기능/Provider/RPC 변경 없음 — profileProvider 데이터만 사용, 비주얼만.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const _SignedOut();

    final profile = ref.watch(profileProvider).value;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(profileProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _ProfileCard(profile: profile),
          const SizedBox(height: 10),
          const _TrustCard(),
          const SizedBox(height: 18),
          const _SectionLabel('내 정보'),
          _MenuCard(items: [
            _MenuItem(
              icon: Icons.precision_manufacturing_outlined,
              label: '내 장비 관리',
              onTap: () => _todo(context, '내 장비 관리'),
            ),
            _MenuItem(
              icon: Icons.description_outlined,
              label: '서류 관리',
              onTap: () => _todo(context, '서류 관리'),
            ),
          ]),
          const SizedBox(height: 18),
          const _SectionLabel('설정'),
          _MenuCard(items: [
            _MenuItem(
              icon: Icons.block_outlined,
              label: '차단 목록',
              onTap: () => _todo(context, '차단 목록'),
            ),
            _MenuItem(
              icon: Icons.notifications_none,
              label: '알림 설정',
              onTap: () => _todo(context, '알림 설정'),
            ),
            _MenuItem(
              icon: Icons.article_outlined,
              label: '이용약관 · 개인정보처리방침',
              onTap: () => _todo(context, '이용약관'),
            ),
          ]),
          const SizedBox(height: 18),
          _MenuCard(items: [
            _MenuItem(
              icon: Icons.logout,
              label: '로그아웃',
              danger: true,
              showChevron: false,
              onTap: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
            ),
          ]),
        ],
      ),
    );
  }

  static void _todo(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label은 준비 중입니다.')),
    );
  }
}

/// 프로필 카드: 아바타 + 이름/회원번호 + 정회원 배지 + 별점·배차수 통계.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});
  final Map<String, dynamic>? profile;

  String get _name => (profile?['name'] as String?) ?? '회원';
  String get _memberNo {
    final v = profile?['member_no'] as String?;
    return (v == null || v.isEmpty) ? '------' : v;
  }

  String get _membershipLabel => switch (profile?['membership_status']) {
        'active' => '정회원',
        'suspended' => '준회원',
        'pending' => '승인 대기',
        _ => '회원',
      };

  bool get _isPremium => (profile?['is_premium'] as bool?) ?? false;

  double? get _rating {
    final sum = (profile?['rating_sum'] as num?)?.toInt() ?? 0;
    final count = (profile?['rating_count'] as num?)?.toInt() ?? 0;
    if (count == 0) return null;
    return sum / count;
  }

  int get _completed => (profile?['completed_as_worker'] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final rating = _rating;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        children: [
          Row(
            children: [
              // 아바타(연블루 원형 + 이니셜).
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.tagBlueBg,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _name.characters.first,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.blueInk,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              letterSpacing: -0.36,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _MembershipBadge(
                          label: _membershipLabel,
                          premium: _isPremium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '회원번호 $_memberNo',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink3,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.line2),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  icon: Icons.star_rounded,
                  iconColor: AppColors.orange,
                  value: rating == null ? '-' : rating.toStringAsFixed(1),
                  label: '평균 별점',
                ),
              ),
              Container(width: 1, height: 30, color: AppColors.line2),
              Expanded(
                child: _Stat(
                  icon: Icons.local_shipping_outlined,
                  iconColor: AppColors.navy,
                  value: JobFormat.amount(_completed),
                  label: '완료 배차',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MembershipBadge extends StatelessWidget {
  const _MembershipBadge({required this.label, required this.premium});
  final String label;
  final bool premium;

  @override
  Widget build(BuildContext context) {
    final bg = premium ? AppColors.navy : AppColors.tagBlueBg;
    final fg = premium ? Colors.white : AppColors.blueInk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (premium) ...[
            Icon(Icons.workspace_premium, size: 12, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            premium ? '프리미엄' : label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.ink3,
          ),
        ),
      ],
    );
  }
}

/// 자격 검증 신뢰배지(정본 §7 "자격배지 신뢰요소"). 서류 5종 인증 완료 안내.
class _TrustCard extends StatelessWidget {
  const _TrustCard();

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
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.tagBlueBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_user,
                size: 20, color: AppColors.blueInk),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '자격 검증 완료',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.blueInk,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '서류 5종 인증을 마친 정회원이에요.',
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

class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.showChevron = true,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final bool showChevron;
}

/// 메뉴 리스트 카드(정본 설정화면 .setrow 패턴). 흰카드 + shadow-sm + 행 구분선.
class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.items});
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i != 0) const Divider(height: 1, color: AppColors.line2),
            _MenuRow(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item});
  final _MenuItem item;

  @override
  Widget build(BuildContext context) {
    final fg = item.danger ? AppColors.red : AppColors.ink;
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        child: Row(
          children: [
            Icon(item.icon,
                size: 20,
                color: item.danger ? AppColors.red : AppColors.ink2),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
            if (item.showChevron)
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 44, color: AppColors.ink3),
          SizedBox(height: 12),
          Text(
            '로그인 후 내 정보를 확인할 수 있습니다.',
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
