import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/supabase/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/segmented_toggle.dart';
import 'job_format.dart';
import 'job_models.dart';
import 'job_providers.dart';

/// 일감 등록(발주) 화면(목업 ⑨). 일반/지정 토글 + 허용 장비 다중선택.
class JobCreateScreen extends ConsumerStatefulWidget {
  const JobCreateScreen({super.key});

  @override
  ConsumerState<JobCreateScreen> createState() => _JobCreateScreenState();
}

/// (카테고리, 모델코드 또는 null=전체) 허용 장비 선택 항목.
class _SelectedEquip {
  const _SelectedEquip(this.category, this.model);
  final String category;
  final String? model;
  @override
  bool operator ==(Object o) =>
      o is _SelectedEquip && o.category == category && o.model == model;
  @override
  int get hashCode => Object.hash(category, model);
}

class _JobCreateScreenState extends ConsumerState<JobCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _designated = false;

  final _regionNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  final _designateTargetCtrl = TextEditingController(); // 회원번호
  final _designatePwCtrl = TextEditingController();

  DateTime _workDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _workTime = const TimeOfDay(hour: 8, minute: 0);

  final _jobTypes = <String>[]; // 작업 종류 태그
  final _jobTypeInputCtrl = TextEditingController();
  final _equips = <_SelectedEquip>{}; // 허용 장비(OR)
  String? _paymentMethod;
  bool _submitting = false;

  static const _paymentMethods = ['직수', '싸인지', '직접청구', '현금'];

  @override
  void dispose() {
    _regionNameCtrl.dispose();
    _addressCtrl.dispose();
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _memoCtrl.dispose();
    _designateTargetCtrl.dispose();
    _designatePwCtrl.dispose();
    _jobTypeInputCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = int.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;
    final referral = (amount * 0.10).round();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('일감 등록')),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SegmentedToggle(
                    labels: const ['일반 발주', '지정 발주'],
                    selectedIndex: _designated ? 1 : 0,
                    onChanged: (i) => setState(() => _designated = i == 1),
                  ),
                  const SizedBox(height: 16),
                  if (_designated) ...[
                    AppTextField(
                      label: '지정 대상 회원번호 (선택)',
                      controller: _designateTargetCtrl,
                      hintText: '예) 204815',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      label: '지정 비밀번호 (선택)',
                      controller: _designatePwCtrl,
                      hintText: '지정 기사에게 전달할 비밀번호',
                    ),
                    const _InfoNote(
                      '지정 기사에게 5분 우선권, 미수락 시 일반 선착순 전환 · 지정배차 매칭 3건마다 우선배차권 1장',
                    ),
                    const SizedBox(height: 16),
                  ],
                  AppTextField(
                    label: '지역명',
                    controller: _regionNameCtrl,
                    hintText: '예) 서울 강남구 역삼동',
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: '상세 주소',
                    controller: _addressCtrl,
                    hintText: '예) 역삼동 123-45',
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        flex: 13,
                        child: _PickerField(
                          label: '작업일',
                          value: DateFormat('yyyy.MM.dd', 'ko_KR')
                              .format(_workDate),
                          onTap: _pickDate,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 10,
                        child: _PickerField(
                          label: '시간',
                          value: _workTime.format(context),
                          onTap: _pickTime,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionLabel('작업 종류 태그'),
                  _JobTypeEditor(
                    tags: _jobTypes,
                    controller: _jobTypeInputCtrl,
                    onAdd: _addJobType,
                    onRemove: (t) => setState(() => _jobTypes.remove(t)),
                  ),
                  const SizedBox(height: 16),
                  const _SectionLabel('허용 장비 · 여러 대 가능 · 아무거나 1대 매칭'),
                  _EquipmentPicker(
                    selected: _equips,
                    onAdd: (e) => setState(() => _equips.add(e)),
                    onRemove: (e) => setState(() => _equips.remove(e)),
                  ),
                  if (_equips.length > 1)
                    const _InfoNote('발주한 장비 중 아무거나 한 대만 와도 매칭됩니다.'),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: '대금 (원)',
                    controller: _amountCtrl,
                    hintText: '예) 1,200,000',
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n =
                          int.tryParse((v ?? '').replaceAll(',', ''));
                      if (n == null || n <= 0) return '금액을 입력하세요.';
                      return null;
                    },
                  ),
                  if (amount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _InfoNote(
                        '매칭 성사 시 소개비 10% (${JobFormat.amount(referral)}P) 를 수령합니다.',
                      ),
                    ),
                  const SizedBox(height: 16),
                  const _SectionLabel('결제 방식'),
                  _PaymentPicker(
                    methods: _paymentMethods,
                    selected: _paymentMethod,
                    onSelect: (m) => setState(() => _paymentMethod = m),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: '메모 (선택)',
                    controller: _memoCtrl,
                    hintText: '추가 안내 사항',
                  ),
                ],
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: AppColors.card,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              padding: EdgeInsets.fromLTRB(
                  16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
              child: SafeArea(
                top: false,
                child: PrimaryButton(
                  label: '일감 등록하기',
                  loading: _submitting,
                  onPressed: _submit,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? '필수 입력 항목입니다.' : null;

  void _addJobType() {
    final t = _jobTypeInputCtrl.text.trim();
    if (t.isEmpty || _jobTypes.contains(t)) return;
    setState(() {
      _jobTypes.add(t);
      _jobTypeInputCtrl.clear();
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _workDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _workDate = picked);
  }

  Future<void> _pickTime() async {
    final picked =
        await showTimePicker(context: context, initialTime: _workTime);
    if (picked != null) setState(() => _workTime = picked);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_equips.isEmpty) {
      _snack('허용 장비를 1개 이상 선택하세요.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final client = SupabaseService.client;
      final uid = client.auth.currentUser?.id;
      final amount =
          int.parse(_amountCtrl.text.replaceAll(',', '').trim());
      final workDateTime = DateTime(_workDate.year, _workDate.month,
          _workDate.day, _workTime.hour, _workTime.minute);

      // 대표 required_* = 선택 장비 중 첫 항목. 나머지는 job_equipment_options.
      final equipList = _equips.toList();
      final primary = equipList.first;

      // 회원번호 → profiles.id 조회(지정 대상 입력 시).
      String? designateTargetId;
      final memberNo = _designateTargetCtrl.text.trim();
      if (_designated && memberNo.isNotEmpty) {
        final row = await client
            .from('profiles')
            .select('id')
            .eq('member_no', memberNo)
            .maybeSingle();
        designateTargetId = row?['id'] as String?;
        if (designateTargetId == null) {
          throw Exception('회원번호 $memberNo 를 찾을 수 없습니다.');
        }
      }

      final pw = _designatePwCtrl.text.trim();

      // 주소 → 좌표(지오코딩). 서버 Edge Function(REST 키 시크릿)으로 변환.
      // 실패해도 등록은 진행(지도는 기본 위치 fallback). KAKAO_REST_KEY 미설정 시 무시.
      double? geoLat;
      double? geoLng;
      try {
        final query = [_regionNameCtrl.text.trim(), _addressCtrl.text.trim()]
            .where((s) => s.isNotEmpty)
            .join(' ');
        if (query.isNotEmpty) {
          final res = await client.functions
              .invoke('geocode', body: {'query': query});
          final data = res.data;
          if (data is Map && data['lat'] != null && data['lng'] != null) {
            geoLat = (data['lat'] as num).toDouble();
            geoLng = (data['lng'] as num).toDouble();
          }
        }
      } catch (_) {
        // 지오코딩 실패는 등록을 막지 않는다.
      }

      final insert = <String, dynamic>{
        // job_no 는 트리거가 생성하므로 넣지 않음.
        'poster_id': uid,
        'work_date': workDateTime.toUtc().toIso8601String(),
        // region_code 는 별도 지역 마스터가 없어 지역명을 코드로 함께 사용(필터용).
        'region_code': _regionNameCtrl.text.trim(),
        'region_name': _regionNameCtrl.text.trim(),
        'address': _addressCtrl.text.trim().isEmpty
            ? null
            : _addressCtrl.text.trim(),
        'lat': ?geoLat,
        'lng': ?geoLng,
        'description': _descCtrl.text.trim().isEmpty
            ? _regionNameCtrl.text.trim()
            : _descCtrl.text.trim(),
        'job_type_tags': _jobTypes,
        'required_category': primary.category,
        'required_model': primary.model,
        'amount': amount,
        'payment_method': _paymentMethod,
        'memo': _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
        'is_designated': _designated,
        if (_designated && designateTargetId != null)
          'designate_target_id': designateTargetId,
        // ⚠ designate_password 는 pgcrypto crypt() 해시로만 저장해야 한다(스키마 주석).
        //   apply_designated 가 crypt(p_password, designate_password) 로 검증하므로
        //   평문 INSERT 는 매칭을 깨뜨린다 → 발주 SECURITY DEFINER RPC 도입 시 해시 처리.
        //   현재 클라이언트는 회원번호 지정만 보낸다(비번 지정은 RPC 후속 작업).
      };
      // 비번 입력 시 회원번호 지정이 없으면 미지원 안내(평문 저장 금지 스텁).
      if (_designated && pw.isNotEmpty && designateTargetId == null) {
        throw Exception('비밀번호 지정은 준비 중입니다. 회원번호로 지정해 주세요.');
      }

      final created = await client
          .from('jobs')
          .insert(insert)
          .select('id')
          .single();
      final jobId = created['id'] as String;

      // 추가 허용 장비 옵션(대표 제외) INSERT.
      final extra = equipList.skip(1).toList();
      if (extra.isNotEmpty) {
        await client.from('job_equipment_options').insert([
          for (final e in extra)
            {'job_id': jobId, 'category': e.category, 'min_model': e.model},
        ]);
      }

      if (!mounted) return;
      ref.invalidate(jobsListProvider);
      _snack('일감이 등록되었습니다.');
      context.pop();
    } catch (e) {
      if (mounted) _snack(mapJobRpcError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField(
      {required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink2)),
        const SizedBox(height: 7),
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 50,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppColors.line),
            ),
            child: Text(value,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink)),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink2)),
    );
  }
}

class _JobTypeEditor extends StatelessWidget {
  const _JobTypeEditor({
    required this.tags,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
  });
  final List<String> tags;
  final TextEditingController controller;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                onSubmitted: (_) => onAdd(),
                decoration: const InputDecoration(
                  hintText: '예) 뿌레카, 코아(천공)',
                  constraints: BoxConstraints(minHeight: 50),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: onAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBg,
                  foregroundColor: AppColors.blueInk,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13)),
                ),
                child: const Text('추가'),
              ),
            ),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in tags)
                _RemovableChip(label: t, onRemove: () => onRemove(t)),
            ],
          ),
        ],
      ],
    );
  }
}

class _EquipmentPicker extends ConsumerWidget {
  const _EquipmentPicker({
    required this.selected,
    required this.onAdd,
    required this.onRemove,
  });
  final Set<_SelectedEquip> selected;
  final ValueChanged<_SelectedEquip> onAdd;
  final ValueChanged<_SelectedEquip> onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(equipmentCategoriesProvider).value ?? const [];
    final models = ref.watch(equipmentModelsProvider).value ?? const [];

    String labelFor(_SelectedEquip e) {
      final cat = categories
          .firstWhere((c) => c.code == e.category,
              orElse: () => EquipmentCategory(code: e.category, label: e.category))
          .label;
      return e.model == null ? '$cat 전체' : '$cat ${e.model}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in selected)
              _RemovableChip(label: labelFor(e), onRemove: () => onRemove(e)),
            GestureDetector(
              onTap: () => _openPicker(context, categories, models),
              child: Container(
                height: 34,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: const Color(0xFFCFD6E0),
                      width: 1.5,
                      style: BorderStyle.solid),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: AppColors.ink2),
                    SizedBox(width: 4),
                    Text('장비 추가',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink2)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openPicker(BuildContext context, List<EquipmentCategory> categories,
      List<EquipmentModel> models) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('허용 장비 선택',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('카테고리 전체 또는 특정 모델 이상을 추가하세요.',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.ink3)),
                const SizedBox(height: 12),
                for (final c in categories) ...[
                  Text(c.label,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _addChip(ctx, '${c.label} 전체',
                          _SelectedEquip(c.code, null)),
                      for (final m in models.where(
                          (m) => m.categoryCode == c.code))
                        _addChip(ctx, '${m.label} 이상',
                            _SelectedEquip(c.code, m.code)),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _addChip(BuildContext context, String label, _SelectedEquip e) {
    final already = selected.contains(e);
    return GestureDetector(
      onTap: already
          ? null
          : () {
              onAdd(e);
              Navigator.pop(context);
            },
      child: Container(
        height: 34,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: already ? AppColors.line : AppColors.primaryBg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: already ? AppColors.ink3 : AppColors.blueInk)),
      ),
    );
  }
}

class _PaymentPicker extends StatelessWidget {
  const _PaymentPicker(
      {required this.methods, required this.selected, required this.onSelect});
  final List<String> methods;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in methods)
          GestureDetector(
            onTap: () => onSelect(m),
            child: Container(
              height: 38,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: selected == m ? AppColors.navy : AppColors.card,
                borderRadius: BorderRadius.circular(999),
                border: selected == m
                    ? null
                    : Border.all(color: AppColors.line, width: 1.5),
              ),
              child: Text(m,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected == m ? Colors.white : AppColors.ink)),
            ),
          ),
      ],
    );
  }
}

class _RemovableChip extends StatelessWidget {
  const _RemovableChip({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 13, right: 8),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 15, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 16, color: AppColors.blueInk),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.blueInk,
                    height: 1.4)),
          ),
        ],
      ),
    );
  }
}
