import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase 접근 헬퍼.
/// 인증 설계(B-17): 전화번호+비밀번호를 합성 이메일로 Supabase Auth에 매핑한다.
abstract final class SupabaseService {
  /// 전역 SupabaseClient. main.dart 에서 Supabase.initialize 가 선행되어야 한다.
  static SupabaseClient get client => Supabase.instance.client;

  /// 전화번호 → 합성 이메일 변환. 숫자만 추출 후 도메인 부착.
  /// 예) 010-1234-5678 → 01012345678@phone.jeonjungbae.app
  static String phoneToEmail(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return '$digits@phone.jeonjungbae.app';
  }
}
