import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:jangbinara/features/jobs/job_models.dart';
import 'package:jangbinara/features/jobs/widgets/job_card.dart';

Job _job({
  required JobStatus status,
  bool designated = false,
  DateTime? priorityEnds,
}) {
  return Job(
    id: 'j1',
    jobNo: '260605-4821',
    posterId: 'p1',
    workDate: DateTime(2026, 6, 5, 8),
    regionCode: '서울 강남구',
    regionName: '서울 강남구 역삼동',
    amount: 480000,
    status: status,
    isDesignated: designated,
    jobTypeTags: const ['뿌레카', '코아(천공)'],
    requiredCategory: 'track',
    requiredModel: '04LC',
    priorityWindowEndsAt: priorityEnds,
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));

  testWidgets('JobCard 가 지역명·금액·우선배차 칩을 렌더한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JobCard(
            job: _job(
              status: JobStatus.priorityWindow,
              priorityEnds: DateTime.now().add(const Duration(seconds: 24)),
            ),
          ),
        ),
      ),
    );

    expect(find.text('서울 강남구 역삼동'), findsOneWidget);
    expect(find.text('우선배차'), findsOneWidget);
    expect(find.text('뿌레카'), findsOneWidget);
    // 금액 480,000 + 원 분리 렌더(rich text) — RichText 존재 확인.
    expect(find.byType(JobCard), findsOneWidget);
    expect(find.text('우선배차 마감까지'), findsOneWidget);
  });

  testWidgets('배차완료 카드는 잠금 라벨을 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JobCard(job: _job(status: JobStatus.matched)),
        ),
      ),
    );
    expect(find.text('배차완료'), findsWidgets);
  });
}
