-- ============================================================================
-- 전중배 P3 — 03. job_applications (지원/배차 신청)
-- 근거: docs/01_dev_plan_v3.0.md §2.1 job_applications, §2.3 인덱스, §2.4(v2.1 패턴).
-- 의존: jobs, profiles, priority_tickets.
-- ⚠ v2.1 의 applicant_location/score(거리 포함) 제거 → effective_rating + poster_post_count.
-- 지원/매칭/우선순위 정렬은 SECURITY DEFINER RPC(다음 단계). 여기선 테이블·RLS(SELECT)만.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.job_applications (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id             uuid NOT NULL REFERENCES public.jobs(id),
  applicant_id       uuid NOT NULL REFERENCES public.profiles(id),
  ticket_id          uuid REFERENCES public.priority_tickets(id),  -- 사용 배차권(일반/지정 시 NULL)
  is_priority        boolean NOT NULL DEFAULT false,               -- 우선 지원 여부
  effective_rating   numeric(6,4),                                 -- 베이지안 유효별점(스냅샷)
  poster_post_count  int NOT NULL DEFAULT 0,                       -- 직전 3개월 발주이력(스냅샷, 우선순위)
  equipment_mismatch boolean NOT NULL DEFAULT false,               -- 인증 기종 불일치(차단X·기록만)
  status             text NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending','accepted','rejected')),
  created_at         timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_job_applications_job_applicant UNIQUE (job_id, applicant_id)  -- 중복 지원 방지
);

-- ----------------------------------------------------------------------------
-- 인덱스 (docs §2.3)
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_applications_job       ON public.job_applications(job_id);
CREATE INDEX IF NOT EXISTS idx_applications_applicant ON public.job_applications(applicant_id);

-- ----------------------------------------------------------------------------
-- RLS (docs §2.4, v2.1 패턴 유지): 본인 지원 + 본인 일감에 들어온 지원 조회.
-- 채택/거절(status 변경)은 SECURITY DEFINER RPC 로만.
-- ----------------------------------------------------------------------------
ALTER TABLE public.job_applications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "지원 조회" ON public.job_applications
  FOR SELECT USING (
    applicant_id = auth.uid()                                  -- 내가 한 지원
    OR job_id IN (SELECT id FROM public.jobs WHERE poster_id = auth.uid())  -- 내 일감의 지원
  );
