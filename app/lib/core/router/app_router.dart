import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/home_screen.dart';

/// 앱 라우터. go_router 사용 (CLAUDE.md Flutter 규칙).
/// P1에서 splash/auth/signup/approval-pending 등 라우트를 추가한다.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  );
});
