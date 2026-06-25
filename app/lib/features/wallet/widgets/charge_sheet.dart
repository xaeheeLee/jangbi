import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../../jobs/job_format.dart';
import '../wallet_models.dart';
import '../wallet_providers.dart';

/// 충전 시트(목업 ⑩ 충전 · 가상계좌).
/// 금액 프리셋/직접입력 → app_settings(vat_rate/pg_fee) 기준 내역 계산 → 가상계좌 발급(스텁).
class ChargeSheet extends ConsumerStatefulWidget {
  const ChargeSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ChargeSheet(),
    );
  }

  @override
  ConsumerState<ChargeSheet> createState() => _ChargeSheetState();
}

class _ChargeSheetState extends ConsumerState<ChargeSheet> {
  final _controller = TextEditingController(text: '100000');
  static const _presets = [30000, 50000, 100000, 300000];

  int get _amount => int.tryParse(_controller.text.trim()) ?? 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setAmount(int v) {
    _controller.text = '$v';
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    setState(() {});
  }

  void _issueVAccount() {
    // ⚠️ 토스페이먼츠 PG 실연동은 계약 블로커(P4 선행). 실제 가상계좌 발급은 미구현.
    //
    // 구현 시 흐름(구조만 잡아둠):
    //   1) charges INSERT(point_amount, vat, pg_fee, total_deposit, status='pending')
    //      → 가상계좌 발급은 발급 RPC/Edge Function(서버)에서 토스 API 호출.
    //   2) 사용자 입금 → 토스 웹훅이 confirm_charge(p_charge_id) RPC 호출
    //      → 원금 발급(+) 후 PG수수료 차감(-) 2건 원장 기록.
    //   ※ confirm_charge 는 웹훅이 호출하는 SECURITY DEFINER RPC 라 클라이언트에서 직접 호출하지 않는다.
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('가상계좌 발급 준비 중'),
        content: const Text(
          '토스페이먼츠 가상계좌 발급은 PG 계약 완료 후 활성화됩니다.\n'
          '계약 완료 시 입금만으로 충전이 자동 반영됩니다.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(walletSettingsProvider).value ?? WalletSettings.fallback;
    final balance = ref.watch(pointBalanceProvider);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final breakdown = ChargeBreakdown.of(_amount, settings);
    final valid = _amount > 0;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetHandle(title: '충전'),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 현재 보유 포인트.
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBg,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: const Color(0xFFDCE8FB)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('현재 보유 포인트',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink2)),
                            Text('${JobFormat.amount(balance)}P',
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navy,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ])),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _FieldLabel('충전 금액 · 직접 입력'),
                      const SizedBox(height: 7),
                      TextField(
                        controller: _controller,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            fontFeatures: [FontFeature.tabularFigures()]),
                        decoration: const InputDecoration(
                          suffixText: 'P',
                          suffixStyle: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink2),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final p in _presets)
                            _AmountChip(
                              label: '+${JobFormat.amount(p)}',
                              onTap: () => _setAmount(_amount + p),
                            ),
                          _AmountChip(
                            label: '직접',
                            onTap: () => _setAmount(0),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _BreakdownCard(breakdown: breakdown),
                      const SizedBox(height: 14),
                      const _InfoNote(
                        '토스페이먼츠 가상계좌로 입금하면 충전 완료. '
                        'PG 수수료는 약관에 따라 포인트에서 차감됩니다.',
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: PrimaryButton(
                  label: valid
                      ? '${JobFormat.amount(breakdown.totalDeposit)}원 가상계좌 발급'
                      : '가상계좌 발급',
                  enabled: valid,
                  onPressed: _issueVAccount,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.breakdown});
  final ChargeBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final b = breakdown;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          _SumRow('충전 포인트', '${JobFormat.amount(b.pointAmount)}P'),
          _SumRow('부가세 (VAT)', '${JobFormat.amount(b.vat)}원'),
          _SumRow(
            '입금 금액',
            '${JobFormat.amount(b.totalDeposit)}원',
            strong: true,
            valueColor: AppColors.navy,
          ),
          _SumRow(
            'PG 수수료 · 포인트 차감',
            '-${JobFormat.amount(b.pgFee)}P',
            valueColor: AppColors.red,
          ),
          _SumRow(
            '사용 가능 포인트',
            '${JobFormat.amount(b.usablePoint)}P',
            strong: true,
            last: true,
          ),
        ],
      ),
    );
  }
}

class _SumRow extends StatelessWidget {
  const _SumRow(
    this.label,
    this.value, {
    this.strong = false,
    this.last = false,
    this.valueColor,
  });
  final String label;
  final String value;
  final bool strong;
  final bool last;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                  color: strong ? AppColors.ink : AppColors.ink2)),
          Text(value,
              style: TextStyle(
                  fontSize: strong ? 16 : 13.5,
                  fontWeight: FontWeight.w800,
                  color: valueColor ?? AppColors.ink,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  const _AmountChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.line),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink2)),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink2));
}

class _InfoNote extends StatelessWidget {
  const _InfoNote(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.primaryBg,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined,
              size: 17, color: AppColors.blueInk),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink2,
                    height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.ink3,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 12),
        Text(title,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.ink)),
        const SizedBox(height: 8),
      ],
    );
  }
}
