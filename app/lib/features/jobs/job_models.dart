import 'package:flutter/foundation.dart';

/// 일감 상태(jobs.status enum — supabase/migrations/20260625010001_p2_jobs.sql).
enum JobStatus {
  open,
  priorityWindow,
  designatedWindow,
  matched,
  completed,
  cancelledByPoster,
  cancelledByWorker,
  expired,
  unknown;

  static JobStatus parse(String? raw) {
    switch (raw) {
      case 'open':
        return JobStatus.open;
      case 'priority_window':
        return JobStatus.priorityWindow;
      case 'designated_window':
        return JobStatus.designatedWindow;
      case 'matched':
        return JobStatus.matched;
      case 'completed':
        return JobStatus.completed;
      case 'cancelled_by_poster':
        return JobStatus.cancelledByPoster;
      case 'cancelled_by_worker':
        return JobStatus.cancelledByWorker;
      case 'expired':
        return JobStatus.expired;
      default:
        return JobStatus.unknown;
    }
  }

  /// 배차 완료/종료 상태(카드 잠금 표시).
  bool get isClosed =>
      this == JobStatus.matched ||
      this == JobStatus.completed ||
      this == JobStatus.cancelledByPoster ||
      this == JobStatus.cancelledByWorker ||
      this == JobStatus.expired;
}

/// 일감 허용 장비 옵션(OR 매칭) — job_equipment_options 행.
@immutable
class JobEquipmentOption {
  const JobEquipmentOption({required this.category, this.minModel});

  final String category;
  final String? minModel;

  factory JobEquipmentOption.fromMap(Map<String, dynamic> m) =>
      JobEquipmentOption(
        category: m['category'] as String,
        minModel: m['min_model'] as String?,
      );
}

/// jobs 한 행 + 조인된 옵션. 컬럼명은 스키마와 정확히 일치한다.
@immutable
class Job {
  const Job({
    required this.id,
    required this.jobNo,
    required this.posterId,
    required this.workDate,
    required this.regionCode,
    required this.regionName,
    required this.amount,
    required this.status,
    required this.isDesignated,
    this.address,
    this.description,
    this.jobTypeTags = const [],
    this.requiredCategory,
    this.requiredModel,
    this.paymentMethod,
    this.memo,
    this.lat,
    this.lng,
    this.priorityWindowEndsAt,
    this.designateWindowExpires,
    this.matchedWorkerId,
    this.options = const [],
  });

  final String id;
  final String jobNo;
  final String posterId;
  final DateTime workDate;
  final String regionCode;
  final String regionName;
  final int amount;
  final JobStatus status;
  final bool isDesignated;
  final String? address;
  final String? description;
  final List<String> jobTypeTags;
  final String? requiredCategory;
  final String? requiredModel;
  final String? paymentMethod;
  final String? memo;
  final double? lat;
  final double? lng;
  final DateTime? priorityWindowEndsAt;
  final DateTime? designateWindowExpires;
  final String? matchedWorkerId;
  final List<JobEquipmentOption> options;

  factory Job.fromMap(Map<String, dynamic> m) {
    final rawOptions = (m['job_equipment_options'] as List?) ?? const [];
    return Job(
      id: m['id'] as String,
      jobNo: m['job_no'] as String,
      posterId: m['poster_id'] as String,
      workDate: DateTime.parse(m['work_date'] as String).toLocal(),
      regionCode: m['region_code'] as String,
      regionName: m['region_name'] as String,
      amount: (m['amount'] as num).toInt(),
      status: JobStatus.parse(m['status'] as String?),
      isDesignated: (m['is_designated'] as bool?) ?? false,
      address: m['address'] as String?,
      description: m['description'] as String?,
      jobTypeTags: ((m['job_type_tags'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      requiredCategory: m['required_category'] as String?,
      requiredModel: m['required_model'] as String?,
      paymentMethod: m['payment_method'] as String?,
      memo: m['memo'] as String?,
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
      priorityWindowEndsAt: _ts(m['priority_window_ends_at']),
      designateWindowExpires: _ts(m['designate_window_expires']),
      matchedWorkerId: m['matched_worker_id'] as String?,
      options: rawOptions
          .map((e) => JobEquipmentOption.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static DateTime? _ts(Object? v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();
}

/// 장비 카테고리(equipment_categories).
@immutable
class EquipmentCategory {
  const EquipmentCategory({required this.code, required this.label});
  final String code;
  final String label;
  factory EquipmentCategory.fromMap(Map<String, dynamic> m) =>
      EquipmentCategory(code: m['code'] as String, label: m['label'] as String);
}

/// 장비 모델(equipment_models).
@immutable
class EquipmentModel {
  const EquipmentModel({
    required this.categoryCode,
    required this.code,
    required this.label,
    required this.sortOrder,
  });
  final String categoryCode;
  final String code;
  final String label;
  final int sortOrder;
  factory EquipmentModel.fromMap(Map<String, dynamic> m) => EquipmentModel(
        categoryCode: m['category_code'] as String,
        code: m['code'] as String,
        label: m['label'] as String,
        sortOrder: (m['sort_order'] as num).toInt(),
      );
}
