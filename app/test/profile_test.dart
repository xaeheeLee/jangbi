import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jangbinara/features/profile/profile_screen.dart';

void main() {
  testWidgets('미로그인(세션 없음)이면 안내 문구를 보여준다', (tester) async {
    // Supabase 미설정 → sessionProvider 가 null → _SignedOut 노출.
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ProfileScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('로그인 후 내 정보를 확인할 수 있습니다.'), findsOneWidget);
  });
}
