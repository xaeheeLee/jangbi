import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/supabase/supabase_service.dart';
import 'auth_providers.dart';
import 'member_document.dart';

/// 인증 액션 컨트롤러. signIn / signUp(+서류 업로드) / signOut 을 담당하고
/// 로딩/에러 상태를 AsyncValue 로 노출한다.
class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    // 초기 상태는 idle.
  }

  SupabaseClient get _client => SupabaseService.client;

  void _ensureConfigured() {
    if (!Env.isSupabaseConfigured) {
      throw const AuthException('Supabase 설정이 필요합니다. 관리자에게 문의하세요.');
    }
  }

  /// 전화번호+비밀번호 로그인.
  Future<void> signIn({required String phone, required String password}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      _ensureConfigured();
      await _client.auth.signInWithPassword(
        email: SupabaseService.phoneToEmail(phone),
        password: password,
      );
      ref.invalidate(profileProvider);
    });
  }

  /// 회원가입 + 서류 5종 업로드.
  /// 1) auth.signUp (DB 트리거가 profiles(pending) 자동 생성 — 클라이언트는 INSERT 금지)
  /// 2) 세션 생성 시 각 파일을 member-docs Storage 에 업로드
  /// 3) member_documents 5건 INSERT
  Future<void> signUp({
    required String name,
    required String phone,
    required String password,
    required Map<DocType, PickedDoc> documents,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      _ensureConfigured();

      final res = await _client.auth.signUp(
        email: SupabaseService.phoneToEmail(phone),
        password: password,
        data: {'name': name, 'phone': phone},
      );

      final user = res.user;
      final session = res.session;
      if (user == null || session == null) {
        // 이메일 확인 등으로 세션이 즉시 생기지 않는 구성. 서류 업로드 불가.
        throw const AuthException('가입 직후 인증 세션을 생성하지 못했습니다. 잠시 후 다시 시도하세요.');
      }

      final uid = user.id;
      final storage = _client.storage.from('member-docs');

      for (final entry in documents.entries) {
        final docType = entry.key;
        final picked = entry.value;
        final path = '$uid/${docType.code}.${picked.ext}';

        await storage.upload(
          path,
          File(picked.path),
          fileOptions: const FileOptions(upsert: true),
        );

        await _client.from('member_documents').insert({
          'user_id': uid,
          'doc_type': docType.code,
          'original_path': path,
        });
      }

      ref.invalidate(profileProvider);
    });
  }

  /// 로그아웃.
  Future<void> signOut() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      _ensureConfigured();
      await _client.auth.signOut();
      ref.invalidate(profileProvider);
    });
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);
