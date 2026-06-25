-- ============================================================================
-- 보안: profiles '본인 수정'을 안전 컬럼으로만 제한 (컬럼 단위 GRANT)
-- 문제: 기존 본인 UPDATE 정책(RLS)은 행만 제한하고 컬럼은 못 막아, 사용자가
--       membership_status·point_balance·admin_score·is_premium·cert_points·rating_*
--       를 직접 변경 가능(자가 승인·포인트 조작). RLS는 컬럼 제어 불가.
-- 해법: authenticated 의 테이블 UPDATE 권한을 회수하고, 사용자가 바꿔도 되는
--       프로필 필드에만 컬럼 UPDATE 권한 부여. 등급/포인트/평점/프리미엄 등은
--       SECURITY DEFINER RPC(소유자 권한)·관리자만 변경.
-- 본인 UPDATE RLS 정책(행 제한)은 그대로 유지 — 컬럼 GRANT와 함께 작동.
-- ============================================================================

REVOKE UPDATE ON public.profiles FROM authenticated;

GRANT UPDATE (
  name,
  phone,
  bank_account,
  business_email,
  business_info,
  license_type,
  equipment_category,
  equipment_model,
  notify_regions,
  notify_equipment
) ON public.profiles TO authenticated;
