-- ============================================================================
-- 전중배 P4 — 05. charges (충전 — 가상계좌)
-- 근거: docs/01_dev_plan_v3.0.md §2.1 charges, §2.4 RLS, CLAUDE.md R2.
-- 의존: profiles.
-- R2: 입금=원금(point_amount)+부가세(vat). PG수수료(pg_fee, 기본 440)는 입금 미포함,
--     발급 후 포인트에서 차감. total_deposit = point_amount + vat.
-- 입금확정(confirm)은 SECURITY DEFINER RPC(다음 단계). 여기선 테이블·RLS(SELECT)만.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.charges (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.profiles(id),
  point_amount  int NOT NULL,                 -- 발급 포인트(=충전 원금)
  vat           int NOT NULL,                 -- 부가세(app_settings.vat_rate 적용)
  pg_fee        int NOT NULL,                 -- PG 수수료(app_settings.pg_fee, 입금 미포함·발급 후 차감)
  total_deposit int NOT NULL,                 -- 입금 요청 총액 = point_amount + vat (수수료 제외)
  vaccount_no   text,                         -- 발급된 가상계좌
  status        text NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','paid','expired','cancelled')),
  paid_at       timestamptz,                  -- 입금통보 시각
  created_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.charges IS '가상계좌 충전. 입금=원금+VAT, PG수수료는 발급 후 포인트에서 차감(R2).';

-- ----------------------------------------------------------------------------
-- RLS (docs §2.4): 본인 충전내역 조회만. 발급/확정은 SECURITY DEFINER RPC.
-- ----------------------------------------------------------------------------
ALTER TABLE public.charges ENABLE ROW LEVEL SECURITY;

CREATE POLICY "본인 충전내역 조회" ON public.charges
  FOR SELECT USING (user_id = auth.uid());
