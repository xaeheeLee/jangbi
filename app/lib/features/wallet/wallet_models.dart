import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 포인트 원장 거래 유형(point_transactions.type CHECK —
/// supabase/migrations/20260625010004_p4_point_transactions.sql).
enum PointTxType {
  charge,
  vat,
  pgFee,
  dailyFee,
  referralIn,
  referralOut,
  platformFee,
  withdraw,
  adminAdjust,
  unknown;

  static PointTxType parse(String? raw) {
    switch (raw) {
      case 'charge':
        return PointTxType.charge;
      case 'vat':
        return PointTxType.vat;
      case 'pg_fee':
        return PointTxType.pgFee;
      case 'daily_fee':
        return PointTxType.dailyFee;
      case 'referral_in':
        return PointTxType.referralIn;
      case 'referral_out':
        return PointTxType.referralOut;
      case 'platform_fee':
        return PointTxType.platformFee;
      case 'withdraw':
        return PointTxType.withdraw;
      case 'admin_adjust':
        return PointTxType.adminAdjust;
      default:
        return PointTxType.unknown;
    }
  }

  /// 한국어 라벨(목업 ④ 포인트 지갑 기준).
  String get label {
    switch (this) {
      case PointTxType.charge:
        return '충전';
      case PointTxType.vat:
        return '부가세';
      case PointTxType.pgFee:
        return 'PG 수수료';
      case PointTxType.dailyFee:
        return '일일 차감';
      case PointTxType.referralIn:
        return '소개비 수령';
      case PointTxType.referralOut:
        return '소개비 지급';
      case PointTxType.platformFee:
        return '플랫폼 수수료';
      case PointTxType.withdraw:
        return '인출';
      case PointTxType.adminAdjust:
        return '관리자 조정';
      case PointTxType.unknown:
        return '거래';
    }
  }
}

/// point_transactions 한 행. 컬럼명은 스키마와 정확히 일치한다.
@immutable
class PointTransaction {
  const PointTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.refJobId,
    this.refChargeId,
    this.memo,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final PointTxType type;

  /// 증감(+/-). 차감은 음수로 저장된다.
  final int amount;
  final int balanceAfter;
  final String? refJobId;
  final String? refChargeId;
  final String? memo;
  final DateTime createdAt;

  bool get isCredit => amount >= 0;

  /// 부호 색: 수령(+) okFg, 차감(-) ink. (목업: 차감은 red 포인트도 사용)
  /// CLAUDE.md 토큰만 사용.
  factory PointTransaction.fromMap(Map<String, dynamic> m) => PointTransaction(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        type: PointTxType.parse(m['type'] as String?),
        amount: (m['amount'] as num).toInt(),
        balanceAfter: (m['balance_after'] as num).toInt(),
        refJobId: m['ref_job_id'] as String?,
        refChargeId: m['ref_charge_id'] as String?,
        memo: m['memo'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

/// charges.status(supabase/migrations/20260625010005_p4_charges.sql CHECK).
enum ChargeStatus {
  pending,
  paid,
  expired,
  cancelled,
  unknown;

  static ChargeStatus parse(String? raw) => switch (raw) {
        'pending' => ChargeStatus.pending,
        'paid' => ChargeStatus.paid,
        'expired' => ChargeStatus.expired,
        'cancelled' => ChargeStatus.cancelled,
        _ => ChargeStatus.unknown,
      };

  String get label => switch (this) {
        ChargeStatus.pending => '입금 대기',
        ChargeStatus.paid => '충전 완료',
        ChargeStatus.expired => '발급 만료',
        ChargeStatus.cancelled => '취소',
        ChargeStatus.unknown => '-',
      };
}

/// withdrawals.status(supabase/migrations/20260625010006_p4_withdrawals.sql CHECK).
enum WithdrawStatus {
  requested,
  approved,
  paid,
  rejected,
  unknown;

  static WithdrawStatus parse(String? raw) => switch (raw) {
        'requested' => WithdrawStatus.requested,
        'approved' => WithdrawStatus.approved,
        'paid' => WithdrawStatus.paid,
        'rejected' => WithdrawStatus.rejected,
        _ => WithdrawStatus.unknown,
      };

  String get label => switch (this) {
        WithdrawStatus.requested => '승인 대기',
        WithdrawStatus.approved => '승인됨',
        WithdrawStatus.paid => '지급 완료',
        WithdrawStatus.rejected => '거절됨',
        WithdrawStatus.unknown => '-',
      };

  /// 상태칩 색(토큰만).
  ({Color bg, Color fg}) get colors => switch (this) {
        WithdrawStatus.requested => (bg: AppColors.revBg, fg: AppColors.revFg),
        WithdrawStatus.approved => (bg: AppColors.primaryBg, fg: AppColors.blueInk),
        WithdrawStatus.paid => (bg: AppColors.okBg, fg: AppColors.okFg),
        WithdrawStatus.rejected => (
            bg: const Color(0xFFFEF1EC),
            fg: AppColors.red
          ),
        WithdrawStatus.unknown => (bg: AppColors.line, fg: AppColors.ink2),
      };
}

/// withdrawals 한 행.
@immutable
class Withdrawal {
  const Withdrawal({
    required this.id,
    required this.amount,
    required this.status,
    this.bankAccount,
    required this.createdAt,
    this.processedAt,
  });

  final String id;
  final int amount;
  final WithdrawStatus status;
  final String? bankAccount;
  final DateTime createdAt;
  final DateTime? processedAt;

  factory Withdrawal.fromMap(Map<String, dynamic> m) => Withdrawal(
        id: m['id'] as String,
        amount: (m['amount'] as num).toInt(),
        status: WithdrawStatus.parse(m['status'] as String?),
        bankAccount: m['bank_account'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        processedAt: m['processed_at'] == null
            ? null
            : DateTime.parse(m['processed_at'] as String).toLocal(),
      );
}

/// 결제 정책 상수(app_settings 에서 읽어 캐시). 하드코딩 금지(CLAUDE.md §3).
@immutable
class WalletSettings {
  const WalletSettings({
    required this.vatRate,
    required this.pgFee,
    required this.dailyFee,
  });

  /// vat_rate (예: 0.10).
  final double vatRate;

  /// pg_fee (예: 440). 입금 미포함, 발급 후 포인트에서 차감(R2).
  final int pgFee;

  /// daily_fee (예: 1000). 매일 자동 차감.
  final int dailyFee;

  /// 미설정/로딩 폴백(시드값과 동일). 실제 표시는 항상 app_settings 우선.
  static const fallback = WalletSettings(vatRate: 0.10, pgFee: 440, dailyFee: 1000);
}

/// 충전 금액 내역 계산(R2). 입금=원금+VAT, PG수수료는 발급 후 포인트에서 차감.
/// 모든 수치는 [WalletSettings](app_settings)에서 주입 — 하드코딩 금지.
@immutable
class ChargeBreakdown {
  const ChargeBreakdown({
    required this.pointAmount,
    required this.vat,
    required this.totalDeposit,
    required this.pgFee,
    required this.usablePoint,
  });

  /// 충전 원금(=발급 포인트, charges.point_amount).
  final int pointAmount;

  /// 부가세(charges.vat).
  final int vat;

  /// 입금 요청 총액 = 원금 + VAT (charges.total_deposit).
  final int totalDeposit;

  /// 발급 후 차감되는 PG 수수료(charges.pg_fee).
  final int pgFee;

  /// 충전 후 실제 사용 가능 포인트 = 원금 - PG수수료.
  final int usablePoint;

  factory ChargeBreakdown.of(int pointAmount, WalletSettings s) {
    final vat = (pointAmount * s.vatRate).round();
    return ChargeBreakdown(
      pointAmount: pointAmount,
      vat: vat,
      totalDeposit: pointAmount + vat,
      pgFee: s.pgFee,
      usablePoint: pointAmount - s.pgFee,
    );
  }
}
