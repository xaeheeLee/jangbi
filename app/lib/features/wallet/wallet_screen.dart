import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../auth/auth_providers.dart';
import '../jobs/job_format.dart';
import 'wallet_models.dart';
import 'wallet_providers.dart';
import 'widgets/charge_sheet.dart';
import 'widgets/point_tx_tile.dart';
import 'widgets/withdraw_sheet.dart';

/// 지갑 탭 본문(목업 ④ 포인트 지갑). 4영역:
/// ① 잔액 카드(충전/인출) ② 인출 내역 ③ 포인트 원장.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return const _SignedOut();

    final balance = ref.watch(pointBalanceProvider);
    final membership = ref.watch(membershipStatusProvider);
    final settings =
        ref.watch(walletSettingsProvider).value ?? WalletSettings.fallback;
    final txs = ref.watch(pointTransactionsProvider);
    final withdrawals = ref.watch(withdrawalsProvider);
    final suspended = membership == 'suspended';

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(profileProvider);
        ref.invalidate(walletSettingsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _BalanceCard(
            balance: balance,
            membership: membership,
            dailyFee: settings.dailyFee,
            onCharge: () => ChargeSheet.show(context),
            onWithdraw: () => WithdrawSheet.show(context),
          ),
          if (suspended) ...[
            const SizedBox(height: 10),
            _SuspendedNotice(dailyFee: settings.dailyFee),
          ],
          const SizedBox(height: 18),

          // ② 인출 내역.
          ...withdrawals.maybeWhen(
            data: (list) => list.isEmpty
                ? const <Widget>[]
                : [
                    const _SectionHead(
                        title: '인출 내역',
                        icon: Icons.account_balance_wallet_outlined),
                    _WithdrawalList(items: list),
                    const SizedBox(height: 18),
                  ],
            orElse: () => const <Widget>[],
          ),

          // ③ 포인트 원장.
          const _SectionHead(
              title: '포인트 내역', icon: Icons.receipt_long_outlined),
          txs.when(
            loading: () => const _LoadingBox(),
            error: (e, _) => _ErrorBox(message: mapJobRpcError(e)),
            data: (list) {
              if (list.isEmpty) {
                return const _EmptyBox(
                  icon: Icons.receipt_long_outlined,
                  text: '아직 포인트 거래 내역이 없습니다.\n충전하면 여기에서 이력을 볼 수 있어요.',
                );
              }
              // 정본 ⑬ 원장 카드: 흰카드 radius 18 + shadow-sm + 패딩 4·14.
              return Container(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.line),
                  boxShadow: AppShadows.sm,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < list.length; i++)
                      PointTxTile(
                        tx: list[i],
                        last: i == list.length - 1,
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.balance,
    required this.membership,
    required this.dailyFee,
    required this.onCharge,
    required this.onWithdraw,
  });

  final int balance;
  final String? membership;
  final int dailyFee;
  final VoidCallback onCharge;
  final VoidCallback onWithdraw;

  String get _membershipLabel => switch (membership) {
        'active' => '정회원',
        'suspended' => '준회원',
        'pending' => '승인 대기',
        _ => '회원',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navy, AppColors.navyHi],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.lift,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('보유 포인트',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(_membershipLabel,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: JobFormat.amount(balance)),
              const TextSpan(
                text: ' P',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ]),
            style: const TextStyle(
                fontSize: 33,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.825, // -.025em (정본 잔액 카드)
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: 4),
          Text('1P = 1원 · 매일 ${JobFormat.amount(dailyFee)}p 자동 차감',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white60)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _CardButton(
                  label: '충전',
                  filled: true,
                  onTap: onCharge,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _CardButton(
                  label: '인출',
                  filled: false,
                  onTap: onWithdraw,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: filled
          ? DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                boxShadow: AppShadows.whiteBtn,
              ),
              child: FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.navy,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13)),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800),
                ),
                child: Text(label),
              ),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.14),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13)),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800),
              ),
              child: Text(label),
            ),
    );
  }
}

class _SuspendedNotice extends StatelessWidget {
  const _SuspendedNotice({required this.dailyFee});
  final int dailyFee;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.revBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1D9A8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 18, color: AppColors.revFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '준회원 상태입니다(잔액 ${JobFormat.amount(dailyFee)}p 미만). '
              '충전하면 정회원 기능이 복구됩니다.',
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.revFg,
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _WithdrawalList extends StatelessWidget {
  const _WithdrawalList({required this.items});
  final List<Withdrawal> items;

  static final _dt = DateFormat('M/d(E) HH:mm', 'ko_KR');

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
              decoration: BoxDecoration(
                border: i == items.length - 1
                    ? null
                    : const Border(
                        bottom: BorderSide(color: AppColors.line2)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${JobFormat.amount(items[i].amount)}P 인출',
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink)),
                        const SizedBox(height: 2),
                        Text(_dt.format(items[i].createdAt),
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink3)),
                      ],
                    ),
                  ),
                  _StatusChip(status: items[i].status),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final WithdrawStatus status;

  @override
  Widget build(BuildContext context) {
    final c = status.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(status.label,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w800, color: c.fg)),
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.navy),
          const SizedBox(width: 7),
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
        ],
      ),
    );
  }
}

class _LoadingBox extends StatelessWidget {
  const _LoadingBox();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: AppColors.ink3),
          const SizedBox(height: 10),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink2,
                  height: 1.5)),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 30, color: AppColors.red),
          const SizedBox(height: 8),
          const Text('불러오지 못했습니다.',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink2)),
          const SizedBox(height: 4),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: AppColors.ink3)),
        ],
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
          Text('로그인 후 지갑을 확인할 수 있습니다.',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink2)),
        ],
      ),
    );
  }
}
