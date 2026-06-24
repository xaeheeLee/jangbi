import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jangbinara/app.dart';

void main() {
  testWidgets('앱 골격이 렌더되고 타이틀이 보인다', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: JangbinaraApp()));
    await tester.pumpAndSettle();

    expect(find.text('전국중장비배차'), findsOneWidget);
  });
}
