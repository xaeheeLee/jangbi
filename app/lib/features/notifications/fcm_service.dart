import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/supabase/supabase_service.dart';
import '../auth/auth_providers.dart';
import 'notification_providers.dart';

/// FCM 클라이언트 연동 서비스.
///
/// 책임:
/// - 알림 권한 요청
/// - FCM 토큰 획득/갱신 → Supabase `device_tokens` 등록(본인 RLS)
/// - foreground 메시지 수신 시 인앱 알림센터 새로고침
///
/// 토큰 등록은 "인증된 세션"이 있을 때만 수행한다. 웹/미설정/미로그인 시 안전 스킵.
class FcmService {
  FcmService(this._ref);

  final Ref _ref;

  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;

  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  /// 앱 시작 / 로그인 직후 호출. 여러 번 호출돼도 1회만 초기화하고,
  /// 매 호출마다 현재 세션 기준으로 토큰 재등록을 시도한다.
  Future<void> register() async {
    if (!_supported) return;

    try {
      if (!_initialized) {
        _initialized = true;

        // 알림 권한 요청(Android 13+/iOS).
        await _messaging.requestPermission();

        // foreground 메시지 → 인앱 알림센터 즉시 새로고침.
        _onMessageSub = FirebaseMessaging.onMessage.listen((_) {
          _ref.invalidate(notificationsProvider);
        });

        // 토큰 갱신 구독 → 세션 있으면 재등록.
        _tokenRefreshSub = _messaging.onTokenRefresh.listen(_persistToken);
      }

      // 현재 토큰 확보 후 등록 시도.
      final token = await _messaging.getToken();
      if (token != null) {
        await _persistToken(token);
      }
    } catch (e) {
      // 미설정/플러그인 미초기화/네트워크 등은 조용히 스킵(앱 골격 유지).
      debugPrint('FcmService.register skipped: $e');
    }
  }

  /// device_tokens 업서트. 인증 세션이 없으면 스킵.
  Future<void> _persistToken(String token) async {
    if (!_supported || !Env.isSupabaseConfigured) return;

    final session = SupabaseService.client.auth.currentSession;
    final uid = session?.user.id;
    if (uid == null) return;

    try {
      await SupabaseService.client.from('device_tokens').upsert(
        {
          'user_id': uid,
          'token': token,
          'platform': Platform.isAndroid ? 'android' : 'ios',
        },
        onConflict: 'user_id,token',
      );
    } catch (e) {
      debugPrint('FcmService.persistToken failed: $e');
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _onMessageSub?.cancel();
  }
}

/// FcmService 싱글턴 provider.
final fcmServiceProvider = Provider<FcmService>((ref) {
  final service = FcmService(ref);
  ref.onDispose(service.dispose);
  return service;
});

/// 인증 상태(세션)에 반응하여 FCM 토큰 등록을 자동 수행하는 등록기.
///
/// app.dart 등에서 `ref.watch(fcmRegistrarProvider)` 하면:
/// - 앱 시작 시 1회 register()
/// - 로그인/세션 변화 시 다시 register()(토큰 재등록)
final fcmRegistrarProvider = Provider<void>((ref) {
  // 세션 변화에 의존 → 로그인 시 재평가되어 토큰 재등록 트리거.
  final session = ref.watch(sessionProvider);
  final service = ref.read(fcmServiceProvider);

  // 미로그인 상태에서도 1회 호출(권한 요청/리스너 등록). 토큰 등록은 내부에서 세션 가드.
  unawaited(service.register());

  // 세션 존재 시 추가 보장(앱 시작-후-로그인 케이스에서 토큰 등록).
  if (session != null) {
    unawaited(service.register());
  }
});
