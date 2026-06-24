-- ============================================================================
-- 전중배 P4 — 07. user_blocks (사용자 차단)
-- 근거: docs/01_dev_plan_v3.0.md §2.1 user_blocks, §2.4 RLS.
-- 의존: profiles.
-- 단방향(blocker→blocked) 저장, 효과는 양방향(목록 비노출 + 상호 매칭 차단).
-- 매칭 가드(양방향 검사)는 SECURITY DEFINER RPC 에서. jobs SELECT RLS 는 본 테이블 생성 후 별도 파일.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.user_blocks (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,  -- 차단을 건 사람
  blocked_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,  -- 차단당한 사람
  created_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_user_blocks UNIQUE (blocker_id, blocked_id),  -- 중복 차단 방지
  CONSTRAINT chk_user_blocks_not_self CHECK (blocker_id <> blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked ON public.user_blocks(blocked_id);

-- ----------------------------------------------------------------------------
-- RLS (docs §2.4): 본인이 건 차단만 조회/관리(FOR ALL).
--   문서 §2.4 는 user_blocks 에 한해 FOR ALL(본인 blocker) 을 명시 — 차단 추가/해제를
--   클라이언트가 직접 수행하도록 허용한 의도된 예외(blocker_id=auth.uid() 가드).
-- ----------------------------------------------------------------------------
ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "본인 차단목록 관리" ON public.user_blocks
  FOR ALL USING (blocker_id = auth.uid()) WITH CHECK (blocker_id = auth.uid());
