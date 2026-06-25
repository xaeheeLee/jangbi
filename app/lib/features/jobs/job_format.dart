import 'package:intl/intl.dart';

/// 일감 표시 포맷 유틸. 원화/한국 로케일(intl).
abstract final class JobFormat {
  static final _won = NumberFormat.decimalPattern('ko_KR');
  static final _date = DateFormat('M/d(E) HH:mm', 'ko_KR');
  static final _dateLong = DateFormat('yyyy.MM.dd(E) HH:mm', 'ko_KR');

  /// 480000 → "480,000".
  static String amount(int v) => _won.format(v);

  /// 6/5(목) 08:00.
  static String workDate(DateTime d) => _date.format(d);

  /// 2026.06.05(목) 08:00.
  static String workDateLong(DateTime d) => _dateLong.format(d);

  /// 장비 카테고리 코드 → 표시 라벨(정본 톤). DB는 track/tire/mini 코드.
  /// 매핑 외 코드는 원문 그대로(서버 라벨 폴백).
  static String categoryLabel(String code) {
    switch (code) {
      case 'track':
        return '궤도형';
      case 'tire':
        return '바퀴형';
      case 'mini':
        return '미니굴삭기';
      default:
        return code;
    }
  }

  /// "궤도형 · 06LC"(모델 있을 때) / "궤도형"(없을 때).
  static String equipmentLabel(String category, String? model) {
    final cat = categoryLabel(category);
    return (model == null || model.isEmpty) ? cat : '$cat · $model';
  }
}

/// RPC 에러 코드 → 사용자 메시지(계획서 §7.1). 미지정 코드는 원문 폴백.
String mapJobRpcError(Object error) {
  final raw = error.toString();
  const table = <String, String>{
    'INSUFFICIENT_POINT': '포인트 잔액이 부족합니다. 충전 후 다시 시도하세요.',
    'BLOCKED': '차단 관계로 지원할 수 없는 일감입니다.',
    'JOB_UNAVAILABLE': '이미 마감되었거나 지원할 수 없는 일감입니다.',
    'JOB_NOT_OPEN': '이미 마감되었거나 지원할 수 없는 일감입니다.',
    'JOB_NOT_FOUND': '일감을 찾을 수 없습니다.',
    'NO_TICKET': '우선배차권이 없습니다.',
    'DUPLICATE_APPLICATION': '이미 지원한 일감입니다.',
    'SELF_APPLY': '본인 일감에는 지원할 수 없습니다.',
    'MEMBERSHIP_SUSPENDED': '준회원 상태에서는 지원할 수 없습니다. 포인트를 충전하세요.',
    'DAILY_LIMIT_EXCEEDED': '오늘은 이미 배차를 수락했습니다(하루 1건).',
    'SCHEDULE_CONFLICT': '같은 시간에 이미 배차된 일감이 있습니다.',
    'NOT_AUTHORIZED': '지정 비밀번호 또는 회원번호가 일치하지 않습니다.',
  };
  for (final entry in table.entries) {
    if (raw.contains(entry.key)) return entry.value;
  }
  return raw.replaceFirst('PostgrestException: ', '').replaceFirst('Exception: ', '');
}
