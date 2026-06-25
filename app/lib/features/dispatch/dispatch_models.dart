import 'package:flutter/foundation.dart';

import '../jobs/job_models.dart';

/// 우선배차권 발급 출처(priority_tickets.source —
/// supabase/migrations/20260625010002_p3_priority_tickets.sql CHECK).
enum TicketSource {
  post,
  designatedBonus,
  photoCert,
  admin,
  unknown;

  static TicketSource parse(String? raw) {
    switch (raw) {
      case 'post':
        return TicketSource.post;
      case 'designated_bonus':
        return TicketSource.designatedBonus;
      case 'photo_cert':
        return TicketSource.photoCert;
      case 'admin':
        return TicketSource.admin;
      default:
        return TicketSource.unknown;
    }
  }

  /// 발급 출처 한국어 라벨.
  String get label {
    switch (this) {
      case TicketSource.post:
        return '발주 발급';
      case TicketSource.designatedBonus:
        return '지정배차 보상';
      case TicketSource.photoCert:
        return '사진 인증';
      case TicketSource.admin:
        return '관리자 지급';
      case TicketSource.unknown:
        return '배차권';
    }
  }
}

/// priority_tickets 한 행. 컬럼명은 스키마와 정확히 일치한다.
@immutable
class PriorityTicket {
  const PriorityTicket({
    required this.id,
    required this.ownerId,
    required this.source,
    required this.expiresAt,
    this.sourceJobId,
    this.usedAt,
    required this.createdAt,
  });

  final String id;
  final String ownerId;
  final TicketSource source;
  final String? sourceJobId;
  final DateTime expiresAt;
  final DateTime? usedAt;
  final DateTime createdAt;

  bool get isUsed => usedAt != null;
  bool get isExpired => !isUsed && expiresAt.isBefore(DateTime.now());
  bool get isAvailable => !isUsed && !isExpired;

  /// 만료까지 남은 일수(D-day). 0=오늘 만료, 음수=만료됨.
  int get daysLeft {
    final now = DateTime.now();
    final end = DateTime(expiresAt.year, expiresAt.month, expiresAt.day);
    final today = DateTime(now.year, now.month, now.day);
    return end.difference(today).inDays;
  }

  factory PriorityTicket.fromMap(Map<String, dynamic> m) => PriorityTicket(
        id: m['id'] as String,
        ownerId: m['owner_id'] as String,
        source: TicketSource.parse(m['source'] as String?),
        sourceJobId: m['source_job_id'] as String?,
        expiresAt: DateTime.parse(m['expires_at'] as String).toLocal(),
        usedAt: m['used_at'] == null
            ? null
            : DateTime.parse(m['used_at'] as String).toLocal(),
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

/// job_applications.status(supabase/migrations/20260625010003 CHECK).
enum ApplicationStatus {
  pending,
  accepted,
  rejected,
  unknown;

  static ApplicationStatus parse(String? raw) {
    switch (raw) {
      case 'pending':
        return ApplicationStatus.pending;
      case 'accepted':
        return ApplicationStatus.accepted;
      case 'rejected':
        return ApplicationStatus.rejected;
      default:
        return ApplicationStatus.unknown;
    }
  }
}

/// 지원 + 조인된 일감. 화면용 상태칩 판정을 [phase] 로 노출한다.
@immutable
class JobApplication {
  const JobApplication({
    required this.id,
    required this.jobId,
    required this.applicantId,
    required this.status,
    required this.isPriority,
    required this.createdAt,
    this.ticketId,
    this.effectiveRating,
    this.equipmentMismatch = false,
    this.job,
  });

  final String id;
  final String jobId;
  final String applicantId;
  final ApplicationStatus status;
  final bool isPriority;
  final DateTime createdAt;
  final String? ticketId;
  final double? effectiveRating;
  final bool equipmentMismatch;

  /// 조인된 일감 요약(없을 수 있음 — RLS/삭제).
  final Job? job;

  factory JobApplication.fromMap(Map<String, dynamic> m, {Job? job}) =>
      JobApplication(
        id: m['id'] as String,
        jobId: m['job_id'] as String,
        applicantId: m['applicant_id'] as String,
        status: ApplicationStatus.parse(m['status'] as String?),
        isPriority: (m['is_priority'] as bool?) ?? false,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        ticketId: m['ticket_id'] as String?,
        effectiveRating: (m['effective_rating'] as num?)?.toDouble(),
        equipmentMismatch: (m['equipment_mismatch'] as bool?) ?? false,
        job: job,
      );

  JobApplication withJob(Job? j) => JobApplication(
        id: id,
        jobId: jobId,
        applicantId: applicantId,
        status: status,
        isPriority: isPriority,
        createdAt: createdAt,
        ticketId: ticketId,
        effectiveRating: effectiveRating,
        equipmentMismatch: equipmentMismatch,
        job: j,
      );

  /// 화면 표시 단계. job_applications.status 와 jobs.status/matched_worker_id 를
  /// 합성하여 결정한다(스키마 단일 컬럼으로는 '내가 채택됐는지' 판정 불가).
  ApplicationPhase get phase {
    // 본인이 채택된 지원.
    if (status == ApplicationStatus.accepted) return ApplicationPhase.matched;
    if (status == ApplicationStatus.rejected) return ApplicationPhase.rejected;

    final j = job;
    if (j != null) {
      // 일감이 다른 기사로 매칭/완료되었으면 내 지원은 미선정.
      if (j.matchedWorkerId != null && j.matchedWorkerId != applicantId) {
        return ApplicationPhase.rejected;
      }
      if (j.status == JobStatus.matched &&
          j.matchedWorkerId == applicantId) {
        return ApplicationPhase.matched;
      }
      if (j.status == JobStatus.completed) {
        return j.matchedWorkerId == applicantId
            ? ApplicationPhase.matched
            : ApplicationPhase.rejected;
      }
      if (j.status == JobStatus.expired ||
          j.status == JobStatus.cancelledByPoster ||
          j.status == JobStatus.cancelledByWorker) {
        return ApplicationPhase.rejected;
      }
      // 우선/지정 윈도우가 열려 있는 동안은 대기.
      if (j.status == JobStatus.priorityWindow ||
          j.status == JobStatus.designatedWindow) {
        return ApplicationPhase.waiting;
      }
    }
    // 기본: 결과 대기.
    return ApplicationPhase.waiting;
  }
}

/// 지원 현황 화면 상태칩.
enum ApplicationPhase {
  /// 우선배차/결과 대기.
  waiting,

  /// 내가 배차 성사.
  matched,

  /// 미선정(반려/다른 기사 매칭/만료).
  rejected,
}
