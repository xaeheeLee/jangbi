import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/primary_button.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _autoLogin = true;
  bool _obscure = true;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await ref.read(authControllerProvider.notifier).signIn(
          phone: _phoneCtrl.text.trim(),
          password: _pwCtrl.text,
        );
    final state = ref.read(authControllerProvider);
    if (state.hasError && mounted) {
      _showError(state.error!);
    }
    // 성공 시 redirect 가 화면을 전환한다.
  }

  void _showError(Object error) {
    final msg = error.toString().replaceFirst('AuthException: ', '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg.isEmpty ? '로그인에 실패했습니다.' : msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _header(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: _card(loading),
              ),
              _trustChips(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, topPad + 48, 24, 40),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          transform: GradientRotation(170 * 3.1415926 / 180),
          colors: [AppColors.navy, AppColors.navyLight],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.construction, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 16),
          const Text(
            '전국중장비배차연합',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '믿을 수 있는 기사 간 배차 매칭',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(bool loading) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.line),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              label: '휴대폰 번호',
              controller: _phoneCtrl,
              hintText: '01012345678',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                if (digits.length < 10) return '휴대폰 번호를 정확히 입력하세요.';
                return null;
              },
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: '비밀번호',
              controller: _pwCtrl,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              validator: (v) =>
                  (v == null || v.isEmpty) ? '비밀번호를 입력하세요.' : null,
              suffix: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.ink3,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _AutoLoginCheck(
                  value: _autoLogin,
                  onChanged: (v) => setState(() => _autoLogin = v),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _onForgotPassword,
                  child: const Text(
                    '비밀번호 찾기',
                    style: TextStyle(
                      color: AppColors.ink2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            PrimaryButton(
              label: '로그인',
              loading: loading,
              onPressed: _submit,
            ),
            const SizedBox(height: 14),
            Center(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    '전중배가 처음이세요? ',
                    style: TextStyle(color: AppColors.ink2, fontSize: 14),
                  ),
                  GestureDetector(
                    onTap: () => context.push('/signup'),
                    child: const Text(
                      '회원가입',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onForgotPassword() {
    // 스텁: 비밀번호 찾기 플로우는 추후 구현.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('비밀번호 찾기는 준비 중입니다.')),
    );
  }

  Widget _trustChips() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TrustChip(emoji: '⚔', label: '빠른'),
          SizedBox(width: 10),
          _TrustChip(emoji: '🕐', label: '배차'),
          SizedBox(width: 10),
          _TrustChip(emoji: '✓', label: '안전'),
        ],
      ),
    );
  }
}

class _AutoLoginCheck extends StatelessWidget {
  const _AutoLoginCheck({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              color: value ? AppColors.navy : AppColors.ink3,
              size: 20,
            ),
            const SizedBox(width: 6),
            const Text(
              '자동 로그인',
              style: TextStyle(
                color: AppColors.ink2,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustChip extends StatelessWidget {
  const _TrustChip({required this.emoji, required this.label});

  final String emoji;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.ink2,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
