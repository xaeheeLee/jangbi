import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/supabase/supabase_service.dart';

/// 인증 상태 스트림. Supabase auth 변화(로그인/로그아웃/토큰갱신)를 방출한다.
/// Supabase 미설정 시에는 빈 스트림 → 항상 미로그인으로 처리.
final authStateProvider = StreamProvider<AuthState?>((ref) {
  if (!Env.isSupabaseConfigured) {
    return const Stream.empty();
  }
  return SupabaseService.client.auth.onAuthStateChange;
});

/// 현재 세션(없으면 null).
final sessionProvider = Provider<Session?>((ref) {
  if (!Env.isSupabaseConfigured) return null;
  // authStateProvider 를 watch 하여 변화 시 재평가되도록 의존성 등록.
  ref.watch(authStateProvider);
  return SupabaseService.client.auth.currentSession;
});

/// 본인 프로필. 로그인 시 profiles 에서 membership_status 등을 조회한다.
/// 미로그인/미설정/없음 → null.
final profileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;

  final uid = session.user.id;
  final data = await SupabaseService.client
      .from('profiles')
      .select()
      .eq('id', uid)
      .maybeSingle();
  return data;
});

/// membership_status 편의 셀렉터: pending / active / suspended / null.
final membershipStatusProvider = Provider<String?>((ref) {
  final profile = ref.watch(profileProvider).value;
  return profile?['membership_status'] as String?;
});
