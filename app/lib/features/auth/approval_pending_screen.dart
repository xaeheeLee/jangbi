import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/status_chip.dart';
import 'auth_controller.dart';
import 'auth_providers.dart';
import 'member_document.dart';

class ApprovalPendingScreen extends ConsumerWidget {
  const ApprovalPendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refreshing = ref.watch(profileProvider).isLoading;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 정본 ⑫: 네이비 시계 아이콘 + 연블루 원형(#EFF6FF) + #DCE8FB 보더.
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFDCE8FB)),
                  ),
                  child: const Icon(
                    Icons.schedule,
                    color: AppColors.navy,
                    size: 42,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '서류를 심사하고 있어요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '제출하신 서류 5종을 확인 중이에요.\n보통 영업일 3일 이내 완료됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppColors.ink2,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              // 정본 ⑫: 서류 5종을 흰카드 한 장에 .upl 행 + line-2 구분선 + 검토중 칩.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                  boxShadow: AppShadows.sm,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < DocType.values.length; i++) ...[
                      if (i != 0)
                        const Divider(height: 1, color: AppColors.line2),
                      _DocReviewRow(
                        label: DocType.values[i].label,
                        icon: DocType.values[i].icon,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primaryBg,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.verified_user_outlined,
                        color: AppColors.blueInk, size: 17),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '승인되면 정회원으로 전환되어 일감 지원·발주가 가능해집니다. '
                        '결과는 알림으로 알려드려요.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink2,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // 정본 .flow-foot: btn-ghost(보조 행동) 새로고침.
              PrimaryButton(
                label: '심사 현황 새로고침',
                variant: PrimaryButtonVariant.ghost,
                icon: Icons.refresh,
                loading: refreshing,
                onPressed: () => ref.invalidate(profileProvider),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).signOut(),
                child: const Text(
                  '로그아웃',
                  style: TextStyle(
                    color: AppColors.ink2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocReviewRow extends StatelessWidget {
  const _DocReviewRow({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.ink2),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          const StatusChip(label: '검토중', variant: StatusChipVariant.rev),
        ],
      ),
    );
  }
}
