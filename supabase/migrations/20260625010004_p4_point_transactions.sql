-- ============================================================================
-- 전중배 P4 — 04. point_transactions (포인트 원장 — 세무·정산·감사 핵심)
-- 근거: docs/01_dev_plan_v3.0.md §2.1 point_transactions, §2.3 인덱스, §2.4 RLS.
-- 의존: profiles, jobs.  (ref_charge_id 는 charges/withdrawals 공용 → FK 미설정, 문서 'uuid NULL')
-- 모든 포인트 증감은 이 원장에 balance_after 까지 기록. INSERT/UPDATE 는 RPC 로만(쓰기 RLS 없음).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.point_transactions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.profiles(id),
  -- 거래 유형 (docs §2.1):
  --   charge(충전 원금) / vat(부가세) / pg_fee(PG수수료) / daily_fee(일일차감)
  --   referral_in(소개비 수령) / referral_out(소개비 지급) / platform_fee(플랫폼 수수료)
  --   withdraw(인출) / admin_adjust(관리자 조정)
  type          text NOT NULL CHECK (type IN (
                  'charge','vat','pg_fee','daily_fee',
                  'referral_in','referral_out','platform_fee',
                  'withdraw','admin_adjust')),
  amount        int NOT NULL,                 -- 증감(+/-)
  balance_after int NOT NULL,                 -- 거래 후 잔액(감사 추적, 필수)
  ref_job_id    uuid REFERENCES public.jobs(id),  -- 관련 일감
  ref_charge_id uuid,                         -- 관련 충전/인출 id(charges/withdrawals 공용, FK 미설정)
  memo          text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON COLUMN public.point_transactions.balance_after IS '거래 후 잔액. profiles.point_balance 와 동일 트랜잭션에서 기록(세무·정산·감사).';
COMMENT ON COLUMN public.point_transactions.ref_charge_id IS 'charges.id 또는 withdrawals.id 참조(공용). 타입별 의미는 type 으로 구분.';

-- ----------------------------------------------------------------------------
-- 인덱스 (docs §2.3): 본인 내역 최신순.
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_point_tx_user
  ON public.point_transactions(user_id, created_at DESC);

-- ----------------------------------------------------------------------------
-- RLS (docs §2.4): 본인 조회만. 변경은 SECURITY DEFINER RPC 로만(쓰기 정책 없음).
-- ----------------------------------------------------------------------------
ALTER TABLE public.point_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "본인 포인트내역 조회" ON public.point_transactions
  FOR SELECT USING (user_id = auth.uid());
