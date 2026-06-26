/// 빌드 시 주입되는 환경값. 비밀키는 코드/깃에 넣지 않는다.
///
/// 실행 예:
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx
///
/// 반복 입력을 줄이려면 app/dart_define.json 사용:
///   flutter run --dart-define-from-file=dart_define.json
/// (dart_define.json 은 .gitignore 로 제외되어 있다)
///
/// 키는 Supabase 대시보드 → Project Settings → API Keys 의
/// Publishable key (sb_publishable_...) 를 사용한다. (구 anon key 대체)
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// 카카오맵 JavaScript 키(앱 키 → JavaScript 키).
  /// 발급 전에는 비어 있으며, 그 경우 지도는 placeholder 로 대체된다.
  /// 카카오 개발자센터 → 내 애플리케이션 → 앱 키 → JavaScript 키.
  static const kakaoJsKey = String.fromEnvironment('KAKAO_JS_KEY');

  static bool get hasKakaoKey => kakaoJsKey.isNotEmpty;
}
