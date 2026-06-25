import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/step_indicator.dart';
import 'auth_controller.dart';
import 'member_document.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  int _step = 0;

  final _basicFormKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();
  bool _obscure = true;

  final Map<DocType, PickedDoc> _docs = {};

  static const _steps = ['기본정보', '서류 인증', '승인 요청'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 0) {
      if (!(_basicFormKey.currentState?.validate() ?? false)) return;
    }
    setState(() => _step = (_step + 1).clamp(0, 2));
  }

  void _back() {
    if (_step == 0) {
      context.pop();
      return;
    }
    setState(() => _step -= 1);
  }

  Future<void> _pick(DocType type) async {
    // 서류는 사진 촬영/갤러리로 첨부(모바일 가입 표준 UX).
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('카메라로 촬영'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final file = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    setState(() {
      _docs[type] = PickedDoc(path: file.path, fileName: file.name);
    });
  }

  Future<void> _submit() async {
    if (_docs.length < DocType.values.length) return;
    FocusScope.of(context).unfocus();
    await ref.read(authControllerProvider.notifier).signUp(
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          password: _pwCtrl.text,
          documents: Map.unmodifiable(_docs),
        );
    if (!mounted) return;
    final state = ref.read(authControllerProvider);
    if (state.hasError) {
      final msg =
          state.error.toString().replaceFirst('AuthException: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg.isEmpty ? '가입에 실패했습니다.' : msg)),
      );
      return;
    }
    // 성공: redirect 가 /approval 로 전환하지만, 명시적 이동도 보장.
    if (mounted) context.go('/approval');
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('회원가입'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: _back,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
              child: StepIndicator(steps: _steps, currentIndex: _step),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: switch (_step) {
                  0 => _basicInfo(),
                  1 => _docsStep(),
                  _ => _confirmStep(),
                },
              ),
            ),
            _bottomBar(loading),
          ],
        ),
      ),
    );
  }

  // ── Step 1: 기본정보 ─────────────────────────────────────────
  Widget _basicInfo() {
    return Form(
      key: _basicFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            label: '이름',
            controller: _nameCtrl,
            hintText: '실명을 입력하세요',
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? '이름을 입력하세요.' : null,
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: '휴대폰 번호',
            controller: _phoneCtrl,
            hintText: '01012345678',
            keyboardType: TextInputType.phone,
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
            hintText: '8자 이상',
            validator: (v) =>
                (v == null || v.length < 8) ? '비밀번호는 8자 이상이어야 합니다.' : null,
            suffix: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_off : Icons.visibility,
                color: AppColors.ink3,
                size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: '비밀번호 확인',
            controller: _pwConfirmCtrl,
            obscureText: _obscure,
            hintText: '비밀번호를 다시 입력하세요',
            validator: (v) =>
                (v != _pwCtrl.text) ? '비밀번호가 일치하지 않습니다.' : null,
          ),
        ],
      ),
    );
  }

  // ── Step 2: 서류 인증 ────────────────────────────────────────
  Widget _docsStep() {
    final count = _docs.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '서류 인증',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const Spacer(),
            Text(
              '$count / ${DocType.values.length}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 정본 .infonote: 연블루 박스 + shield 아이콘(blue-ink) + 본문 ink-2.
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
                  color: AppColors.blueInk, size: 17),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '발주자에게는 마스킹본만 노출, 원본은 비공개로 보관됩니다.',
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
        const SizedBox(height: 14),
        for (final type in DocType.values) ...[
          _docRow(type),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _docRow(DocType type) {
    final picked = _docs[type];
    final done = picked != null;
    return InkWell(
      onTap: () => _pick(type),
      borderRadius: BorderRadius.circular(AppTheme.fieldRadius),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppTheme.fieldRadius),
          border: Border.all(color: done ? AppColors.okFg : AppColors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primaryBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(type.icon, color: AppColors.navy, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.label,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    done ? (picked.fileName) : type.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.ink2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusChip(
              label: done ? '완료' : '업로드',
              variant: done ? StatusChipVariant.ok : StatusChipVariant.need,
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 3: 승인 요청 ────────────────────────────────────────
  Widget _confirmStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '승인 요청',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '입력하신 정보와 서류 5종을 확인하고 제출하세요.\n관리자 심사 후 정회원으로 전환됩니다.',
          style: TextStyle(
            fontSize: 13.5,
            color: AppColors.ink2,
            fontWeight: FontWeight.w500,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        _summaryRow('이름', _nameCtrl.text.trim()),
        _summaryRow('휴대폰', _phoneCtrl.text.trim()),
        const SizedBox(height: 14),
        for (final type in DocType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  _docs.containsKey(type)
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: _docs.containsKey(type)
                      ? AppColors.okFg
                      : AppColors.ink3,
                ),
                const SizedBox(width: 8),
                Text(
                  type.label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.ink2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 하단 액션 바 ─────────────────────────────────────────────
  Widget _bottomBar(bool loading) {
    final remaining = DocType.values.length - _docs.length;
    final canSubmit = remaining == 0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: switch (_step) {
          0 => PrimaryButton(label: '다음', onPressed: _next),
          1 => PrimaryButton(
              label: canSubmit ? '다음' : '서류 $remaining종 남음',
              enabled: canSubmit,
              onPressed: _next,
            ),
          _ => PrimaryButton(
              label: canSubmit
                  ? '제출하고 승인 요청'
                  : '제출하고 승인 요청 · $remaining종 남음',
              enabled: canSubmit,
              loading: loading,
              onPressed: _submit,
            ),
        },
      ),
    );
  }
}
