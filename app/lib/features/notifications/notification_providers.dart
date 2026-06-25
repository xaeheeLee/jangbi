import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/supabase/supabase_service.dart';
import '../auth/auth_providers.dart';
import 'notification_models.dart';

/// 표시할 알림 최근 건수(간단 상한).
const kNotificationLimit = 100;

/// 내 알림 실시간 스트림(recipient_id=내 uid, 최신순). RLS 가 본인 행만 노출.
final _notificationsStreamProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  final session = ref.watch(sessionProvider);
  if (!Env.isSupabaseConfigured || session == null) {
    return Stream.value(const <Map<String, dynamic>>[]);
  }
  return SupabaseService.client
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('recipient_id', session.user.id)
      .order('created_at', ascending: false)
      .limit(kNotificationLimit);
});

/// 내 알림(파싱본, 최신순).
final notificationsProvider =
    Provider<AsyncValue<List<AppNotification>>>((ref) {
  return ref.watch(_notificationsStreamProvider).whenData(
        (rows) => rows.map(AppNotification.fromMap).toList(),
      );
});

/// 미읽음 알림 수(앱바 벨 빨강 점 판정용). 로딩/에러/미설정 시 0.
final unreadCountProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).value ?? const [];
  return list.where((n) => !n.read).length;
});

/// 단일 알림 읽음 처리(본인 UPDATE RLS 허용). 이미 읽음이면 호출하지 않아도 무방.
Future<void> markNotificationRead(String id) async {
  if (!Env.isSupabaseConfigured) return;
  await SupabaseService.client
      .from('notifications')
      .update({'read': true}).eq('id', id);
}

/// 내 미읽음 전부 읽음 처리("모두 읽음"). recipient_id=본인 + read=false 만 갱신.
Future<void> markAllNotificationsRead() async {
  final session = SupabaseService.client.auth.currentSession;
  if (!Env.isSupabaseConfigured || session == null) return;
  await SupabaseService.client
      .from('notifications')
      .update({'read': true})
      .eq('recipient_id', session.user.id)
      .eq('read', false);
}
