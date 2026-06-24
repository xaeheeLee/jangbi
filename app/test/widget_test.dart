import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jangbinara/app.dart';

void main() {
  testWidgets('Supabase 미설정 시 홈 셸이 렌더되고 하단 탭이 보인다',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: JangbinaraApp()));
    await tester.pumpAndSettle();

    // 하단 5탭 라벨이 보인다.
    expect(find.text('일감'), findsWidgets);
    expect(find.text('지갑'), findsOneWidget);
    expect(find.text('MY'), findsOneWidget);
  });
}
