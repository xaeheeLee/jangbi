import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jangbinara/features/notifications/notification_models.dart';
import 'package:jangbinara/features/notifications/notifications_screen.dart';

void main() {
  group('relativeTime', () {
    final now = DateTime(2026, 6, 25, 12, 0, 0);

    test('1분 미만은 "방금"', () {
      expect(relativeTime(now.subtract(const Duration(seconds: 30)), now: now),
          '방금');
    });

    test('분 단위', () {
      expect(relativeTime(now.subtract(const Duration(minutes: 5)), now: now),
          '5분 전');
    });

    test('시간 단위', () {
      expect(relativeTime(now.subtract(const Duration(hours: 3)), now: now),
          '3시간 전');
    });

    test('하루 전은 "어제"', () {
      expect(relativeTime(now.subtract(const Duration(days: 1)), now: now),
          '어제');
    });

    test('7일 이상은 날짜', () {
      final old = DateTime(2026, 5, 1, 9, 0, 0);
      expect(relativeTime(old, now: now), '2026.05.01');
    });
  });

  group('AppNotification.fromMap', () {
    test('type/딥링크 파싱', () {
      final n = AppNotification.fromMap({
        'id': 'abc',
        'type': 'match_success',
        'title': '배차 확정',
        'body': '서울 현장 배차가 확정되었습니다.',
        'data': {'job_id': 'job-1'},
        'read': false,
        'created_at': '2026-06-25T03:00:00.000Z',
      });
      expect(n.type, AppNotificationType.matchSuccess);
      expect(n.jobId, 'job-1');
      expect(n.read, isFalse);
    });

    test('미지정 type 은 unknown 폴백', () {
      final n = AppNotification.fromMap({
        'id': '1',
        'type': 'something_else',
        'title': '알림',
        'body': '',
        'data': null,
        'read': true,
        'created_at': '2026-06-25T03:00:00.000Z',
      });
      expect(n.type, AppNotificationType.unknown);
      expect(n.jobId, isNull);
    });
  });

  testWidgets('미설정 환경에서 빈 상태 문구를 보여준다', (tester) async {
    // Supabase 미설정 → 스트림이 빈 목록 → "새 알림이 없어요." 노출.
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: NotificationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('새 알림이 없어요.'), findsOneWidget);
  });
}
