-- ============================================================================
-- 전중배 — 10. jobs SELECT RLS 정책 (user_blocks 의존 → 마지막에 정의)
-- 근거: docs/01_dev_plan_v3.0.md §2.4 "일감 열람" 정책 그대로.
-- 의존: jobs(010001), job_applications(010003), user_blocks(010007).
--   jobs 테이블·RLS ENABLE 은 010001 에서 수행. 본 파일은 SELECT 정책만 추가
--   (차단 양방향 비노출을 위해 user_blocks 가 먼저 존재해야 하므로 분리).
-- 쓰기(발주 생성/취소/매칭)는 전부 SECURITY DEFINER RPC — RLS 쓰기 정책 없음.
-- ============================================================================

-- 멱등성: 재실행 시 기존 정책 제거 후 재생성.
DROP POLICY IF EXISTS "일감 열람" ON public.jobs;

CREATE POLICY "일감 열람"
  ON public.jobs FOR SELECT
  USING (
    poster_id = auth.uid()                       -- 내 일감
    OR matched_worker_id = auth.uid()            -- 내가 배차받은 일감
    OR id IN (                                   -- 내가 지원한 일감
      SELECT job_id FROM public.job_applications WHERE applicant_id = auth.uid()
    )
    OR (
      status IN ('open','priority_window')       -- 공개 일감(지정배차 포함, 지원만 RPC 에서 제한)
      AND poster_id NOT IN (                      -- 차단 양방향 비노출
        SELECT blocked_id FROM public.user_blocks WHERE blocker_id = auth.uid()
        UNION
        SELECT blocker_id FROM public.user_blocks WHERE blocked_id = auth.uid()
      )
    )
  );
