import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';

/// 현장 사진 인증 단계.
enum JobPhotoPhase {
  arrival('arrival', '현장 도착', Icons.location_on_outlined),
  work('work', '작업 중', Icons.engineering_outlined),
  done('done', '작업 종료', Icons.task_alt_outlined);

  const JobPhotoPhase(this.code, this.label, this.icon);
  final String code;
  final String label;
  final IconData icon;
}

/// 본인이 업로드한 해당 일감의 사진(phase → storage_path).
/// 배차받은 기사 본인(uploader_id == uid) 기준 조회.
final myJobPhotosProvider =
    FutureProvider.family<Map<String, String>, String>((ref, jobId) async {
  final uid = SupabaseService.client.auth.currentUser?.id;
  if (uid == null) return const {};
  final rows = await SupabaseService.client
      .from('job_photos')
      .select('phase, storage_path')
      .eq('job_id', jobId)
      .eq('uploader_id', uid);
  final map = <String, String>{};
  for (final r in rows) {
    map[r['phase'] as String] = r['storage_path'] as String;
  }
  return map;
});

/// 현장 사진 인증 섹션. 배차받은 기사(matched_worker_id == 본인)에게만 노출.
class JobPhotoSection extends ConsumerStatefulWidget {
  const JobPhotoSection({super.key, required this.jobId});
  final String jobId;

  @override
  ConsumerState<JobPhotoSection> createState() => _JobPhotoSectionState();
}

class _JobPhotoSectionState extends ConsumerState<JobPhotoSection> {
  String? _uploadingPhase;

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(myJobPhotosProvider(widget.jobId));
    final photos = photosAsync.value ?? const <String, String>{};

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.photo_camera_outlined,
                  size: 18, color: AppColors.navy),
              const SizedBox(width: 8),
              const Text(
                '현장 사진 인증',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              Text(
                '${photos.length} / ${JobPhotoPhase.values.length}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '단계별 사진을 등록하면 포인트가 적립되고, 누적 시 우선배차권이 지급됩니다.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.ink2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          for (final phase in JobPhotoPhase.values) ...[
            _PhaseRow(
              phase: phase,
              storagePath: photos[phase.code],
              uploading: _uploadingPhase == phase.code,
              onAdd: () => _add(phase),
              onView: () => _view(photos[phase.code]!),
            ),
            if (phase != JobPhotoPhase.values.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Future<void> _add(JobPhotoPhase phase) async {
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
    final file =
        await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (file == null) return;

    setState(() => _uploadingPhase = phase.code);
    try {
      final client = SupabaseService.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) throw Exception('로그인이 필요합니다.');

      // 계약: 경로 첫 폴더 = 본인 uid (Storage RLS), 파일명에 job/phase/타임스탬프.
      final ms = DateTime.now().millisecondsSinceEpoch;
      final path = '$uid/${widget.jobId}_${phase.code}_$ms.jpg';

      await client.storage.from('job-photos').upload(
            path,
            File(file.path),
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      final res = (await client.rpc('register_job_photo', params: {
        'p_job_id': widget.jobId,
        'p_phase': phase.code,
        'p_storage_path': path,
      })) as Map<String, dynamic>;

      final points = (res['job_points'] as num?)?.toInt() ?? 0;
      final tickets = (res['tickets_granted'] as num?)?.toInt() ?? 0;
      ref.invalidate(myJobPhotosProvider(widget.jobId));

      final ticketMsg = tickets > 0 ? ', 우선배차권 $tickets장 지급' : '';
      _snack('${phase.label} 사진 등록 완료 · 누적 $points점$ticketMsg');
    } catch (e) {
      _snack(_mapError(e));
    } finally {
      if (mounted) setState(() => _uploadingPhase = null);
    }
  }

  Future<void> _view(String storagePath) async {
    try {
      final url = await SupabaseService.client.storage
          .from('job-photos')
          .createSignedUrl(storagePath, 60 * 5);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Container(
                  height: 200,
                  color: AppColors.mapBg,
                  alignment: Alignment.center,
                  child: const Text('이미지를 불러올 수 없습니다.'),
                ),
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      _snack(_mapError(e));
    }
  }

  String _mapError(Object e) {
    final msg = e.toString();
    if (msg.contains('NOT_MATCHED_WORKER') || msg.contains('row-level')) {
      return '배차받은 기사만 사진을 등록할 수 있습니다.';
    }
    return '사진 등록에 실패했습니다. 잠시 후 다시 시도하세요.';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _PhaseRow extends StatelessWidget {
  const _PhaseRow({
    required this.phase,
    required this.storagePath,
    required this.uploading,
    required this.onAdd,
    required this.onView,
  });

  final JobPhotoPhase phase;
  final String? storagePath;
  final bool uploading;
  final VoidCallback onAdd;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final done = storagePath != null;
    return InkWell(
      onTap: uploading ? null : (done ? onView : onAdd),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: done ? AppColors.okBg : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: done ? AppColors.okFg : AppColors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done ? AppColors.card : AppColors.primaryBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(phase.icon,
                  size: 19, color: done ? AppColors.okFg : AppColors.navy),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    phase.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    done ? '등록 완료 · 탭하여 보기' : '사진을 추가하세요',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: done ? AppColors.okFg : AppColors.ink2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _trailing(done),
          ],
        ),
      ),
    );
  }

  Widget _trailing(bool done) {
    if (uploading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (done) {
      return const Icon(Icons.check_circle, size: 22, color: AppColors.okFg);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        '사진 추가',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
        ),
      ),
    );
  }
}
