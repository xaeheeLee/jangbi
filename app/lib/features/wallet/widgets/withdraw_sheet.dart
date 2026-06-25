import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_button.dart';
import '../../jobs/job_format.dart';
import '../wallet_providers.dart';

/// 인출 시트(목업 ⑪ 인출). 전 잔액까지 입력 → request_withdraw RPC.
/// 본인 명의 계좌(profiles.bank_account) 안내 + 관리자 승인 게이트 안내.
class WithdrawSheet extends ConsumerStatefulWidget {
  const WithdrawSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const WithdrawSheet(),
    );
  }

  @override
  ConsumerState<WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends ConsumerState<WithdrawSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  int get _amount => int.tryParse(_controller.text.trim()) ?? 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(int balance) async {
    final account = ref.read(bankAccountProvider);
    if (account == null) {
      setState(() => _error = '인출 계좌(본인 명의)가 등록되어 있지 않습니다. 통장 사본 인증 후 이용하세요.');
      return;
    }
    if (_amount <= 0 || _amount > balance) {
      setState(() => _error = '인출 금액을 1P 이상, 보유 잔액 이내로 입력하세요.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await requestWithdraw(ref, _amount);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('인출을 신청했습니다. 관리자 승인 후 지급됩니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = mapJobRpcError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(pointBalanceProvider);
    final account = ref.watch(bankAccountProvider);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final valid = _amount > 0 && _amount <= balance && account != null;

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
              const _Handle(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 인출 가능 포인트(네이비 카드).
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.navy, AppColors.navyLight],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('인출 가능 포인트',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white70)),
                            const SizedBox(height: 5),
                            Text('${JobFormat.amount(balance)}P',
                                style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ])),
                            const SizedBox(height: 3),
                            const Text('충전금 포함 전 잔액 · 1P = 1원',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white60)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('인출 금액',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink2)),
                      const SizedBox(height: 7),
                      TextField(
                        controller: _controller,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        onChanged: (_) => setState(() => _error = null),
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            fontFeatures: [FontFeature.tabularFigures()]),
                        decoration: InputDecoration(
                          suffixIcon: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: TextButton(
                              onPressed: () {
                                _controller.text = '$balance';
                                setState(() => _error = null);
                              },
                              child: const Text('전액'),
                            ),
                          ),
                          suffixIconConstraints:
                              const BoxConstraints(minWidth: 0, minHeight: 0),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('보유 잔액 한도 내에서 인출할 수 있습니다.',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink3)),
                      const SizedBox(height: 16),
                      _AccountCard(account: account),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(_error!,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.red)),
                      ],
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBg,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.verified_user_outlined,
                                size: 17, color: AppColors.blueInk),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '인출은 본인 명의 계좌로만 가능하며, 관리자 승인 후 영업일 기준 1~2일 내 입금됩니다.',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink2,
                                    height: 1.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: PrimaryButton(
                  label: valid
                      ? '${JobFormat.amount(_amount)}P 인출 신청'
                      : '인출 신청',
                  enabled: valid,
                  loading: _submitting,
                  onPressed: () => _submit(balance),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account});
  final String? account;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('입금 계좌',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink2)),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FE),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.account_balance,
                    size: 19, color: AppColors.blueInk),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: account != null
                    ? Text(account!,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink))
                    : const Text('본인 명의 계좌 미등록 · 통장 사본 인증 필요',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.red)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();
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
        const Text('인출',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.ink)),
        const SizedBox(height: 8),
      ],
    );
  }
}
