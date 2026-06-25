-- ============================================================================
-- RLS 상호재귀 해결 + 차단 양방향 검사 보정
-- 문제1: jobs 정책이 job_applications 를, job_applications 정책이 jobs 를 서로
--        서브쿼리로 참조 → "infinite recursion detected in policy"(jobs 조회 전체 실패).
-- 문제2: jobs 정책의 차단 검사가 user_blocks 를 직접 서브쿼리하는데, user_blocks
--        RLS(blocker 본인만)가 '내가 차단당한 행'을 가려 양방향 비노출이 깨짐.
-- 해법: 교차참조를 SECURITY DEFINER 헬퍼(대상 테이블 RLS 우회)로 감싸 고리 차단.
-- ============================================================================

-- 내가 그 일감에 지원했는가 (job_applications RLS 우회)
CREATE OR REPLACE FUNCTION public.uid_applied_to_job(p_job_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.job_applications
    WHERE job_id = p_job_id AND applicant_id = auth.uid()
  );
$$;

-- 내가 그 일감의 발주자인가 (jobs RLS 우회)
CREATE OR REPLACE FUNCTION public.uid_owns_job(p_job_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.jobs
    WHERE id = p_job_id AND poster_id = auth.uid()
  );
$$;

-- 나와 상대가 (어느 방향이든) 차단 관계인가 (user_blocks RLS 우회, 양방향)
CREATE OR REPLACE FUNCTION public.uid_blocked_with(p_other uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_blocks
    WHERE (blocker_id = auth.uid() AND blocked_id = p_other)
       OR (blocker_id = p_other  AND blocked_id = auth.uid())
  );
$$;

-- jobs 열람 정책 재작성 (재귀 제거 + 차단 양방향 보정)
DROP POLICY IF EXISTS "일감 열람" ON public.jobs;
CREATE POLICY "일감 열람" ON public.jobs
  FOR SELECT USING (
    poster_id = auth.uid()
    OR matched_worker_id = auth.uid()
    OR public.uid_applied_to_job(id)
    OR (
      status IN ('open', 'priority_window', 'designated_window')
      AND NOT public.uid_blocked_with(poster_id)
    )
  );

-- job_applications 조회 정책 재작성 (재귀 제거)
DROP POLICY IF EXISTS "지원 조회" ON public.job_applications;
CREATE POLICY "지원 조회" ON public.job_applications
  FOR SELECT USING (
    applicant_id = auth.uid()
    OR public.uid_owns_job(job_id)
  );
