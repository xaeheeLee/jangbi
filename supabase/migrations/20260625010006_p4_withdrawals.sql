-- ============================================================================
-- 전중배 P4 — 06. withdrawals (인출/환급 신청)
-- 근거: docs/01_dev_plan_v3.0.md §2.1 withdrawals, §2.4 RLS, CLAUDE.md R1.
-- 의존: profiles.
-- R1: 충전금 포함 전 잔액(단일 point_balance) 인출. 본인 명의 계좌 한정 + 관리자 승인 게이트.
-- bank_account 는 신청 시점 스냅샷. 신청/승인/지급은 SECURITY DEFINER RPC(다음 단계).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.withdrawals (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES public.profiles(id),
  amount       int NOT NULL,                  -- 인출 포인트
  status       text NOT NULL DEFAULT 'requested'
                 CHECK (status IN ('requested','approved','paid','rejected')),
  bank_account text,                          -- 지급 계좌(신청 시점 스냅샷, 본인 명의)
  processed_by uuid REFERENCES public.profiles(id),  -- 처리 관리자
  created_at   timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz
);

COMMENT ON TABLE public.withdrawals IS '인출 신청. 본인 명의 계좌 한정 + 관리자 승인 게이트 + 원장 기록(R1).';

-- ----------------------------------------------------------------------------
-- RLS (docs §2.4): 본인 인출내역 조회만. 신청/승인/지급은 SECURITY DEFINER RPC.
-- ----------------------------------------------------------------------------
ALTER TABLE public.withdrawals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "본인 인출내역 조회" ON public.withdrawals
  FOR SELECT USING (user_id = auth.uid());
