import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/supabase/supabase_service.dart';
import '../auth/auth_providers.dart';
import 'wallet_models.dart';

/// 표시할 원장 최근 건수(간단 페이지네이션 대용).
const kWalletTxLimit = 50;

/// app_settings 전용 provider. vat_rate / pg_fee / daily_fee 를 한 번에 읽어 캐시.
/// 정책 수치는 절대 하드코딩하지 않는다(CLAUDE.md §3).
final walletSettingsProvider = FutureProvider<WalletSettings>((ref) async {
  if (!Env.isSupabaseConfigured) return WalletSettings.fallback;
  final rows = await SupabaseService.client
      .from('app_settings')
      .select('key, value')
      .inFilter('key', ['vat_rate', 'pg_fee', 'daily_fee']);

  final map = <String, String>{
    for (final r in rows) r['key'] as String: r['value'] as String,
  };
  double parseD(String k, double fb) => double.tryParse(map[k] ?? '') ?? fb;
  int parseI(String k, int fb) => int.tryParse(map[k] ?? '') ?? fb;

  return WalletSettings(
    vatRate: parseD('vat_rate', WalletSettings.fallback.vatRate),
    pgFee: parseI('pg_fee', WalletSettings.fallback.pgFee),
    dailyFee: parseI('daily_fee', WalletSettings.fallback.dailyFee),
  );
});

/// 현재 포인트 잔액(profiles.point_balance). profileProvider 재사용.
final pointBalanceProvider = Provider<int>((ref) {
  final profile = ref.watch(profileProvider).value;
  return (profile?['point_balance'] as num?)?.toInt() ?? 0;
});

/// 본인 명의 인출 계좌(profiles.bank_account). 없으면 null.
final bankAccountProvider = Provider<String?>((ref) {
  final profile = ref.watch(profileProvider).value;
  final v = profile?['bank_account'] as String?;
  return (v == null || v.isEmpty) ? null : v;
});

/// 내 포인트 원장 실시간 스트림(user_id=내 uid, 최신순). RLS 가 본인 행만 노출.
final _pointTxStreamProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  final session = ref.watch(sessionProvider);
  if (!Env.isSupabaseConfigured || session == null) {
    return Stream.value(const <Map<String, dynamic>>[]);
  }
  return SupabaseService.client
      .from('point_transactions')
      .stream(primaryKey: ['id'])
      .eq('user_id', session.user.id)
      .order('created_at', ascending: false)
      .limit(kWalletTxLimit);
});

/// 내 포인트 원장(파싱본, 최신순).
final pointTransactionsProvider =
    Provider<AsyncValue<List<PointTransaction>>>((ref) {
  return ref.watch(_pointTxStreamProvider).whenData(
        (rows) => rows.map(PointTransaction.fromMap).toList(),
      );
});

/// 내 인출 신청 내역 실시간 스트림(최신순).
final _withdrawalsStreamProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  final session = ref.watch(sessionProvider);
  if (!Env.isSupabaseConfigured || session == null) {
    return Stream.value(const <Map<String, dynamic>>[]);
  }
  return SupabaseService.client
      .from('withdrawals')
      .stream(primaryKey: ['id'])
      .eq('user_id', session.user.id)
      .order('created_at', ascending: false);
});

/// 내 인출 내역(파싱본).
final withdrawalsProvider = Provider<AsyncValue<List<Withdrawal>>>((ref) {
  return ref.watch(_withdrawalsStreamProvider).whenData(
        (rows) => rows.map(Withdrawal.fromMap).toList(),
      );
});

/// 인출 신청. request_withdraw(p_amount int) SECURITY DEFINER RPC 호출.
/// 성공 시 profiles 잔액이 즉시 차감되므로 profileProvider 를 무효화한다.
Future<void> requestWithdraw(WidgetRef ref, int amount) async {
  await SupabaseService.client.rpc(
    'request_withdraw',
    params: {'p_amount': amount},
  );
  ref.invalidate(profileProvider);
}
