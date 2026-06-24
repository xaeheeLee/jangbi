-- ============================================================================
-- 전중배 — 09. job_photos (현장 사진 인증) + admin_score_log (평점 변경 감사)
-- 근거: docs/01_dev_plan_v3.0.md §2.1 job_photos / admin_score_log.
-- 의존: jobs, profiles.
-- 사진 적립·40점 배차권 지급은 register_job_photo RPC, 점수조정은 RPC(다음 단계). 여기선 테이블·RLS만.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- job_photos — 일감 사진 인증(현장도착/작업/작업종료)
--   비공개 버킷 + 서명URL. 점수: phase당 1 + 3종완비 보너스 1, 40점당 배차권 1장.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.job_photos (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id       uuid NOT NULL REFERENCES public.jobs(id),
  uploader_id  uuid NOT NULL REFERENCES public.profiles(id),  -- 배차받은 기사
  phase        text NOT NULL CHECK (phase IN ('arrival','work','done')),  -- 도착/작업/종료
  storage_path text NOT NULL,                  -- 비공개 버킷 경로(서명URL)
  taken_at     timestamptz NOT NULL DEFAULT now(),  -- 촬영/업로드 시각
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_job_photos_job      ON public.job_photos(job_id);
CREATE INDEX IF NOT EXISTS idx_job_photos_uploader ON public.job_photos(uploader_id);

-- RLS: 업로더 본인 + 해당 일감 발주자만 조회(원본 비공개·서명URL 은 RPC). 등록은 RPC.
ALTER TABLE public.job_photos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "현장사진 조회" ON public.job_photos
  FOR SELECT USING (
    uploader_id = auth.uid()
    OR job_id IN (SELECT id FROM public.jobs WHERE poster_id = auth.uid())
  );

-- ----------------------------------------------------------------------------
-- admin_score_log — 평점(관리자 점수) 변경 이력(감사)
--   평점은 비공개 우선순위 레버(±1). 변경 이력으로 분쟁·감사 대비.
--   본인 점수 이력도 비공개(우선순위 노출 방지) → 일반 사용자 SELECT 정책 없음.
--   관리자 조회/기록은 SECURITY DEFINER RPC·관리자웹(service_role)로만.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_score_log (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES public.profiles(id),  -- 대상 회원
  admin_id    uuid REFERENCES public.profiles(id),            -- 변경한 관리자
  delta       int NOT NULL,                  -- 증감(+1/-1)
  score_after int NOT NULL,                  -- 변경 후 평점
  reason      text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_score_log_user ON public.admin_score_log(user_id, created_at DESC);

-- RLS: enable 만(SELECT 정책 없음 → 일반 사용자 접근 차단). 기록·열람은 RPC/관리자 전용.
ALTER TABLE public.admin_score_log ENABLE ROW LEVEL SECURITY;
