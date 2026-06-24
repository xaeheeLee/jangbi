-- ============================================================================
-- 전중배 — 18. app_settings 추가: ticket_refund_min_days (배차권 환불 최소 보장일)
-- 근거: 적대적 리뷰 S-2 — finalize/expire_old_jobs 의 '7일' 하드코딩 제거.
-- ⚠ P1 마이그레이션(001601 app_settings 시드)은 이미 클라우드 적용 → 수정 금지.
--   신규 설정값은 본 신규 마이그레이션으로 INSERT(멱등, ON CONFLICT DO NOTHING).
-- 사용처: finalize_priority_match / expire_old_jobs 의 배차권 환불 시 만료 최소 보장.
-- ============================================================================

INSERT INTO public.app_settings (key, value, description) VALUES
  ('ticket_refund_min_days', '7', '배차권 환불 시 최소 보장 유효일(매칭 불발·탈락 환불)')
ON CONFLICT (key) DO NOTHING;
