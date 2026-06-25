import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// notifications.type 유형. 서버가 보내는 코드와 1:1.
/// 미지정 코드는 [AppNotificationType.unknown] 으로 폴백(중립 톤).
enum AppNotificationType {
  matchSuccess,
  ticketGranted,
  pointLow,
  membershipSuspended,
  jobApplication,
  jobExpired,
  unknown;

  static AppNotificationType parse(String? raw) => switch (raw) {
        'match_success' => AppNotificationType.matchSuccess,
        'ticket_granted' => AppNotificationType.ticketGranted,
        'point_low' => AppNotificationType.pointLow,
        'membership_suspended' => AppNotificationType.membershipSuspended,
        'job_application' => AppNotificationType.jobApplication,
        'job_expired' => AppNotificationType.jobExpired,
        _ => AppNotificationType.unknown,
      };

  /// 유형별 아이콘.
  IconData get icon => switch (this) {
        AppNotificationType.matchSuccess => Icons.check_circle,
        AppNotificationType.ticketGranted => Icons.confirmation_number_outlined,
        AppNotificationType.pointLow => Icons.account_balance_wallet_outlined,
        AppNotificationType.membershipSuspended => Icons.warning_amber_rounded,
        AppNotificationType.jobApplication => Icons.how_to_reg_outlined,
        AppNotificationType.jobExpired => Icons.history_toggle_off,
        AppNotificationType.unknown => Icons.notifications_none,
      };

  /// 아이콘 전경/배경색(토큰만 — CLAUDE.md §4).
  ({Color bg, Color fg}) get colors => switch (this) {
        AppNotificationType.matchSuccess => (bg: AppColors.okBg, fg: AppColors.okFg),
        AppNotificationType.ticketGranted => (
            bg: AppColors.tagBlueBg,
            fg: AppColors.blueInk
          ),
        AppNotificationType.pointLow => (bg: AppColors.revBg, fg: AppColors.revFg),
        AppNotificationType.membershipSuspended => (
            bg: AppColors.redBg,
            fg: AppColors.red
          ),
        AppNotificationType.jobApplication => (
            bg: AppColors.tagBlueBg,
            fg: AppColors.blueInk
          ),
        AppNotificationType.jobExpired => (
            bg: AppColors.tagGrayBg,
            fg: AppColors.tagGrayFg
          ),
        AppNotificationType.unknown => (
            bg: AppColors.tagGrayBg,
            fg: AppColors.tagGrayFg
          ),
      };
}

/// notifications 한 행. 컬럼명은 스키마와 정확히 일치한다.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.read,
    required this.createdAt,
  });

  final String id;
  final AppNotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool read;
  final DateTime createdAt;

  /// data 딥링크 대상 job id(있으면). data['job_id'] 우선.
  String? get jobId => data['job_id']?.toString();

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'].toString(),
        type: AppNotificationType.parse(m['type'] as String?),
        title: (m['title'] as String?) ?? '알림',
        body: (m['body'] as String?) ?? '',
        data: switch (m['data']) {
          final Map<String, dynamic> d => d,
          final Map d => d.map((k, v) => MapEntry(k.toString(), v)),
          _ => const <String, dynamic>{},
        },
        read: (m['read'] as bool?) ?? false,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

/// 상대 시각 표기("방금 / N분 전 / N시간 전 / 어제 / N일 전 / yyyy.MM.dd").
String relativeTime(DateTime t, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = ref.difference(t);
  if (diff.isNegative || diff.inMinutes < 1) return '방금';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  if (diff.inDays == 1) return '어제';
  if (diff.inDays < 7) return '${diff.inDays}일 전';
  final m = t.month.toString().padLeft(2, '0');
  final d = t.day.toString().padLeft(2, '0');
  return '${t.year}.$m.$d';
}
