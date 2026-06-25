import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/brand_logo.dart';
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
      // 히어로(네이비)가 화면 전체를 채우고, 흰 시트가 아래에서 올라오는 구조.
      backgroundColor: AppColors.navy,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          // .hero-navy: linear-gradient(170deg, navy 0%, #01285A 60%, #01224d 100%)
          gradient: LinearGradient(
            begin: Alignment(-0.17, -1),
            end: Alignment(0.17, 1),
            colors: [AppColors.navy, AppColors.heroLoginEnd, AppColors.heroEnd],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        // 히어로는 남는 공간을 채워 시트를 화면 하단으로 민다.
                        Expanded(child: _header(context)),
                        _sheet(context, loading),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 46, 28, 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // .logo-badge: 132x132, radius 30, 흰배경 + 그림자 + inset white.
          const LogoBadge(size: 132, radius: 30),
          const SizedBox(height: 22),
          // 워드마크 2줄(26/400 + 26/700, 자간 타이트).
          const Text(
            '전국 중장비',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w400,
              height: 1.26,
              letterSpacing: -1.17, // -.045em
            ),
          ),
          const Text(
            '배차의 시작',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.26,
              letterSpacing: -1.17,
            ),
          ),
          const SizedBox(height: 11),
          Text(
            '믿을 수 있는 기사와 일감을 한 번에.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 아래에서 올라오는 흰 시트(.sheet: 상단 radius 26).
  Widget _sheet(BuildContext context, bool loading) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(color: Color(0x1F000000), blurRadius: 30, offset: Offset(0, -10)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(24, 26, 24, 22 + bottomPad),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              label: '휴대폰 번호',
              controller: _phoneCtrl,
              hintText: '010-0000-0000',
              filled: true,
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
              filled: true,
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
                GestureDetector(
                  onTap: _onForgotPassword,
                  child: const Text(
                    '비밀번호 찾기',
                    style: TextStyle(
                      color: AppColors.blueInk,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: '로그인',
              loading: loading,
              onPressed: _submit,
            ),
            const SizedBox(height: 16),
            Center(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    '전중배가 처음이세요? ',
                    style: TextStyle(
                      color: AppColors.ink2,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.push('/signup'),
                    child: const Text(
                      '회원가입',
                      style: TextStyle(
                        color: AppColors.blueInk,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _trustChips(),
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

  // 하단 신뢰배지 3종(자격 검증·빠른 배차·안전 거래). 상단 line-2 구분선 위 인라인.
  Widget _trustChips() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line2)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TrustChip(icon: Icons.verified_user_outlined, label: '자격 검증'),
          SizedBox(width: 18),
          _TrustChip(icon: Icons.schedule, label: '빠른 배차'),
          SizedBox(width: 18),
          _TrustChip(icon: Icons.check_circle_outline, label: '안전 거래'),
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
  const _TrustChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    // .spec: 인라인 아이콘(navy 15px) + 라벨(12.5/600 ink-2).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.navy),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.ink2,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }
}
