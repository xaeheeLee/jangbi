import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
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
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.revBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.schedule,
                    color: AppColors.revFg,
                    size: 44,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                '서류를 심사하고 있어요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '보통 영업일 3일 이내 완료됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.ink2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.line),
                  boxShadow: AppShadows.sm,
                ),
                child: Column(
                  children: [
                    for (final type in DocType.values) ...[
                      _DocReviewRow(label: type.label, icon: type.icon),
                      if (type != DocType.values.last)
                        const Divider(height: 18, color: AppColors.line),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primaryBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified_outlined,
                        color: AppColors.blueInk, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '승인되면 자동으로 정회원으로 전환됩니다.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.blueInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: refreshing
                      ? null
                      : () => ref.invalidate(profileProvider),
                  icon: refreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: AppColors.navy,
                          ),
                        )
                      : const Icon(Icons.refresh, color: AppColors.navy),
                  label: const Text(
                    '심사 현황 새로고침',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.navy),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
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
    return Row(
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
    );
  }
}
