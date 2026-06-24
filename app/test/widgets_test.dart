import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jangbinara/core/widgets/status_chip.dart';
import 'package:jangbinara/core/widgets/step_indicator.dart';
import 'package:jangbinara/core/supabase/supabase_service.dart';

void main() {
  testWidgets('StatusChip 가 라벨을 렌더한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusChip(label: '검토중', variant: StatusChipVariant.rev),
        ),
      ),
    );
    expect(find.text('검토중'), findsOneWidget);
  });

  testWidgets('StepIndicator 가 3단계 라벨을 렌더한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StepIndicator(
            steps: ['기본정보', '서류 인증', '승인 요청'],
            currentIndex: 1,
          ),
        ),
      ),
    );
    expect(find.text('기본정보'), findsOneWidget);
    expect(find.text('서류 인증'), findsOneWidget);
    expect(find.text('승인 요청'), findsOneWidget);
  });

  test('phoneToEmail 은 숫자만 추출해 합성 이메일을 만든다', () {
    expect(
      SupabaseService.phoneToEmail('010-1234-5678'),
      '01012345678@phone.jeonjungbae.app',
    );
  });
}
