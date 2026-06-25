import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'firebase_options.dart';

/// 백그라운드/종료 상태에서 도착한 FCM 데이터 메시지 핸들러.
/// 별도 isolate 에서 실행되므로 top-level + vm:entry-point 가 필수.
/// 시스템 트레이 표시는 OS 가 처리하며, 여기서는 추가 동기화가 필요할 때 사용.
@pragma('vm:entry-point')
Future<void> _fcmBgHandler(RemoteMessage message) async {
  // 현재는 별도 처리 없음(알림은 DB + 인앱센터로 노출). 향후 silent sync 용 훅.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // intl 한국 로케일(날짜·요일) 데이터 초기화.
  await initializeDateFormatting('ko_KR');

  // Firebase 초기화(웹 제외). 실패해도 앱 골격은 계속 실행.
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(_fcmBgHandler);
    } catch (e) {
      debugPrint('Firebase init skipped: $e');
    }
  }

  // Supabase 미설정 상태에서도 골격이 실행되도록 가드.
  // 설정 방법은 core/config/env.dart 참고.
  if (Env.isSupabaseConfigured) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
    );
  }

  runApp(const ProviderScope(child: JangbinaraApp()));
}
