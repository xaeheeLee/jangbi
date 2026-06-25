import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:jangbinara/features/wallet/wallet_models.dart';
import 'package:jangbinara/features/wallet/widgets/point_tx_tile.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));

  group('ChargeBreakdown (app_settings 기반 계산 — R2)', () {
    test('30,000p 충전: 입금=원금+VAT, 사용가능=원금-PG수수료', () {
      const s = WalletSettings(vatRate: 0.10, pgFee: 440, dailyFee: 1000);
      final b = ChargeBreakdown.of(30000, s);
      expect(b.pointAmount, 30000);
      expect(b.vat, 3000); // 10%
      expect(b.totalDeposit, 33000); // 원금 + VAT
      expect(b.pgFee, 440);
      expect(b.usablePoint, 29560); // 30000 - 440
    });

    test('vat_rate/pg_fee 변경 시 계산이 따라간다(하드코딩 아님)', () {
      const s = WalletSettings(vatRate: 0.05, pgFee: 1000, dailyFee: 1000);
      final b = ChargeBreakdown.of(100000, s);
      expect(b.vat, 5000);
      expect(b.totalDeposit, 105000);
      expect(b.usablePoint, 99000);
    });
  });

  group('PointTxType 라벨/파싱', () {
    test('CHECK enum 값을 한국어 라벨로 매핑', () {
      expect(PointTxType.parse('charge').label, '충전');
      expect(PointTxType.parse('pg_fee').label, 'PG 수수료');
      expect(PointTxType.parse('daily_fee').label, '일일 차감');
      expect(PointTxType.parse('referral_in').label, '소개비 수령');
      expect(PointTxType.parse('withdraw').label, '인출');
      expect(PointTxType.parse('???'), PointTxType.unknown);
    });
  });

  testWidgets('원장 항목: 차감은 -금액, 수령은 +금액과 잔액을 표시', (tester) async {
    final credit = PointTransaction(
      id: 't1',
      userId: 'u1',
      type: PointTxType.charge,
      amount: 30000,
      balanceAfter: 134640,
      createdAt: DateTime(2026, 6, 12, 14, 20),
    );
    final debit = PointTransaction(
      id: 't2',
      userId: 'u1',
      type: PointTxType.pgFee,
      amount: -440,
      balanceAfter: 134200,
      createdAt: DateTime(2026, 6, 12, 14, 20),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              PointTxTile(tx: credit),
              PointTxTile(tx: debit),
            ],
          ),
        ),
      ),
    );

    expect(find.text('충전'), findsOneWidget);
    expect(find.text('+30,000P'), findsOneWidget);
    expect(find.text('잔액 134,640'), findsOneWidget);
    expect(find.text('PG 수수료'), findsOneWidget);
    expect(find.text('-440P'), findsOneWidget);
  });
}
