import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/approval_pending_screen.dart';
import '../../features/auth/auth_providers.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/jobs/job_create_screen.dart';
import '../../features/jobs/job_detail_screen.dart';
import '../../features/notifications/notification_settings_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../config/env.dart';

/// 빌드 시 주입되는 프리뷰 진입 경로(개발용 스크린샷). 비어 있으면 정상 동작.
/// 예: flutter run --dart-define=PREVIEW_ROUTE=/signup
const _previewRoute = String.fromEnvironment('PREVIEW_ROUTE');

/// 앱 라우터. go_router + redirect 로 인증/승인 상태에 따라 분기한다.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: _previewRoute.isNotEmpty ? _previewRoute : '/home',
    refreshListenable: refresh,
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
      GoRoute(
        path: '/approval',
        builder: (_, _) => const ApprovalPendingScreen(),
      ),
      GoRoute(path: '/home', builder: (_, _) => const HomeShell()),
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/job/create', builder: (_, _) => const JobCreateScreen()),
      GoRoute(
        path: '/job/:id',
        builder: (_, state) =>
            JobDetailScreen(jobId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
        routes: [
          GoRoute(
            path: 'settings',
            builder: (_, _) => const NotificationSettingsScreen(),
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      // 프리뷰 모드: 리다이렉트 우회(개발용 스크린샷).
      if (_previewRoute.isNotEmpty) return null;
      // Supabase 미설정이면 골격 확인을 위해 home 진입 허용.
      if (!Env.isSupabaseConfigured) {
        return state.matchedLocation == '/home' ? null : '/home';
      }

      final session = ref.read(sessionProvider);
      final loc = state.matchedLocation;

      // 미로그인: login/signup 만 허용.
      if (session == null) {
        if (loc == '/login' || loc == '/signup') return null;
        return '/login';
      }

      // 로그인됨: 프로필 로딩 상태 확인.
      final profileAsync = ref.read(profileProvider);
      if (profileAsync.isLoading) {
        return loc == '/splash' ? null : '/splash';
      }

      final status = profileAsync.value?['membership_status'] as String?;

      // pending → 승인대기.
      if (status == 'pending') {
        return loc == '/approval' ? null : '/approval';
      }

      // active / suspended → home (suspended 안내는 배너로 처리).
      if (loc == '/login' ||
          loc == '/signup' ||
          loc == '/approval' ||
          loc == '/splash') {
        return '/home';
      }
      return null;
    },
  );
});

/// auth/profile 변화 시 go_router redirect 를 재평가하도록 알린다.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    final sub1 = ref.listen(authStateProvider, (_, _) => notifyListeners());
    final sub2 = ref.listen(profileProvider, (_, _) => notifyListeners());
    _closers = [sub1.close, sub2.close];
  }

  late final List<VoidCallback> _closers;

  @override
  void dispose() {
    for (final close in _closers) {
      close();
    }
    super.dispose();
  }
}
