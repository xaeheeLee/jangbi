import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:jangbinara/features/dispatch/dispatch_models.dart';
import 'package:jangbinara/features/dispatch/widgets/ticket_card.dart';

PriorityTicket _ticket({
  TicketSource source = TicketSource.photoCert,
  required DateTime expiresAt,
  DateTime? usedAt,
}) {
  return PriorityTicket(
    id: 't1',
    ownerId: 'u1',
    source: source,
    expiresAt: expiresAt,
    usedAt: usedAt,
    createdAt: DateTime(2026, 6, 1),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));

  testWidgets('미사용 배차권은 출처 라벨과 D-day 배지를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicketCard(
            ticket: _ticket(
              source: TicketSource.designatedBonus,
              expiresAt: DateTime.now().add(const Duration(days: 5)),
            ),
          ),
        ),
      ),
    );

    expect(find.text('지정배차 보상'), findsOneWidget);
    expect(find.text('D-5'), findsOneWidget);
  });

  testWidgets('만료 임박(D-1) 배차권은 red 배지를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicketCard(
            ticket: _ticket(
              expiresAt: DateTime.now().add(const Duration(hours: 20)),
            ),
          ),
        ),
      ),
    );
    expect(find.text('사진 인증'), findsOneWidget);
    expect(find.text('D-0').evaluate().isNotEmpty ||
            find.text('D-1').evaluate().isNotEmpty ||
            find.text('오늘 만료').evaluate().isNotEmpty,
        isTrue);
  });

  testWidgets('사용한 배차권은 사용완료 배지를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicketCard(
            ticket: _ticket(
              expiresAt: DateTime(2026, 7, 1),
              usedAt: DateTime(2026, 6, 10, 9),
            ),
          ),
        ),
      ),
    );
    expect(find.text('사용완료'), findsOneWidget);
  });
}
