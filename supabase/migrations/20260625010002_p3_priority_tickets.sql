-- ============================================================================
-- 전중배 P3 — 02. priority_tickets (우선 배차권)
-- 근거: docs/01_dev_plan_v3.0.md §2.1 priority_tickets, §2.3 인덱스, §2.4(v2.1 패턴).
-- 의존: profiles, jobs.
-- 발급/차감(used_at)·발행은 SECURITY DEFINER RPC·트리거(다음 단계). 여기선 테이블·RLS(SELECT)만.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.priority_tickets (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id      uuid NOT NULL REFERENCES public.profiles(id),
  -- 발급 출처: post(발주이력 보상) / designated_bonus(지정배차 N건) /
  --            photo_cert(사진인증 40점) / admin(관리자 지급)
  source        text NOT NULL CHECK (source IN ('post','designated_bonus','photo_cert','admin')),
  source_job_id uuid REFERENCES public.jobs(id),  -- 발행 근거 일감(있을 때)
  expires_at    timestamptz NOT NULL,             -- 생성 후 N일(app_settings.ticket_expiry_days)
  used_at       timestamptz,                      -- 사용 시각(NULL=미사용)
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- 인덱스 (docs §2.3): 미사용 배차권 보유자 조회(만료 정렬).
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_tickets_owner_unused
  ON public.priority_tickets(owner_id, expires_at) WHERE used_at IS NULL;

-- ----------------------------------------------------------------------------
-- RLS (docs §2.4, v2.1 패턴 유지): 본인 보유 배차권만 조회. 차감/발급은 RPC.
-- ----------------------------------------------------------------------------
ALTER TABLE public.priority_tickets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "본인 배차권 조회" ON public.priority_tickets
  FOR SELECT USING (owner_id = auth.uid());
