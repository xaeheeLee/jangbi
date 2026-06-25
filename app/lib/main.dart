import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/supabase/supabase_service.dart';

// 개발용 자동 로그인(스크린샷/프리뷰 전용). 비어 있으면 비활성.
// 예: --dart-define=DEV_AUTOLOGIN_PHONE=01099990001 --dart-define=DEV_AUTOLOGIN_PW=...
const _devPhone = String.fromEnvironment('DEV_AUTOLOGIN_PHONE');
const _devPw = String.fromEnvironment('DEV_AUTOLOGIN_PW');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // intl 한국 로케일(날짜·요일) 데이터 초기화.
  await initializeDateFormatting('ko_KR');

  // Supabase 미설정 상태에서도 골격이 실행되도록 가드.
  // 설정 방법은 core/config/env.dart 참고.
  if (Env.isSupabaseConfigured) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
    );

    // 개발용 자동 로그인 (정의된 경우에만).
    if (_devPhone.isNotEmpty && _devPw.isNotEmpty) {
      try {
        await SupabaseService.client.auth.signInWithPassword(
          email: SupabaseService.phoneToEmail(_devPhone),
          password: _devPw,
        );
      } catch (_) {
        // 실패해도 일반 로그인 플로우로 진행.
      }
    }
  }

  runApp(const ProviderScope(child: JangbinaraApp()));
}
