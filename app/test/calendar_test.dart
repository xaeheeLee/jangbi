import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:jangbinara/features/calendar/calendar_providers.dart';
import 'package:jangbinara/features/calendar/calendar_screen.dart';
import 'package:jangbinara/features/jobs/job_models.dart';

Job _job({
  required DateTime workDate,
  JobStatus status = JobStatus.matched,
}) {
  return Job(
    id: 'j-${workDate.day}-${status.name}',
    jobNo: '260615-0001',
    posterId: 'p1',
    workDate: workDate,
    regionCode: '서울 강남구',
    regionName: '역삼동',
    amount: 1200000,
    status: status,
    isDesignated: false,
    requiredCategory: 'track',
    requiredModel: '04LC',
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));

  test('CalendarEvent.day 는 시각을 버리고 자정 키로 그룹한다', () {
    final e = CalendarEvent(
      job: _job(workDate: DateTime(2026, 6, 15, 8, 30)),
      kind: CalendarMarkKind.dispatch,
    );
    expect(e.day, DateTime(2026, 6, 15));
  });

  testWidgets('오늘 일감이 있으면 선택일 카드(제목·금액)를 렌더한다', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 8);
    final byDay = {
      DateTime(today.year, today.month, today.day): [
        CalendarEvent(
          job: _job(workDate: today, status: JobStatus.matched),
          kind: CalendarMarkKind.dispatch,
        ),
      ],
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          calendarEventsByDayProvider.overrideWithValue(byDay),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CalendarScreen()),
        ),
      ),
    );
    await tester.pump();

    // 좌측 컬러바 카드의 제목 "역삼동 현장 · 04LC".
    expect(find.text('역삼동 현장 · 04LC'), findsOneWidget);
    // 상태 pill(배차 확정) + 범례.
    expect(find.text('배차 확정'), findsOneWidget);
    expect(find.text('배차'), findsOneWidget);
    expect(find.text('우선'), findsOneWidget);
  });
}
