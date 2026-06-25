import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/notifications/fcm_service.dart';

class JangbinaraApp extends ConsumerWidget {
  const JangbinaraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // FCM 등록기 활성화: 앱 시작 + 로그인 세션 변화에 반응해 토큰 등록.
    ref.watch(fcmRegistrarProvider);
    return MaterialApp.router(
      title: '전중배',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
