-- ============================================================================
-- 전중배 P2 — 01. jobs (일감/발주) + job_equipment_options (다중 허용 장비 OR 매칭)
-- 근거: docs/01_dev_plan_v3.0.md §2.1 jobs/job_equipment_options, §2.3 인덱스, §2.4 RLS
-- 의존: profiles, equipment_categories, equipment_models, user_blocks(RLS 참조).
--   ⚠ user_blocks 는 P4(09)에서 생성되나 jobs RLS 정책이 user_blocks 를 참조하므로
--     본 파일에서는 jobs/job_equipment_options 테이블·인덱스만 만들고,
--     jobs SELECT RLS 정책은 user_blocks 생성 이후 별도 파일(20260625010010)에서 정의한다.
-- 거리/GPS/PostGIS 금지 — lat/lng 은 지도 표시용 double precision 만(매칭 미사용).
-- RPC/트리거(job_no 생성·상태분기·배차권 발급)는 다음 단계에서 작성.
-- ============================================================================

-- jobs.status enum (docs §2.1):
--   open / priority_window / designated_window / matched / completed
--   / cancelled_by_poster / cancelled_by_worker / expired
-- 문서가 text DEFAULT 'open' + CHECK enum 으로 기술 → 전용 enum 타입으로 구현(무결성·인덱스 효율).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'job_status') THEN
    CREATE TYPE public.job_status AS ENUM (
      'open',
      'priority_window',
      'designated_window',
      'matched',
      'completed',
      'cancelled_by_poster',
      'cancelled_by_worker',
      'expired'
    );
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.jobs (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- 표시용 일감번호 YYMMDD-NNNN (날짜 + 랜덤 4자리 숫자, 순차 아님). 생성은 트리거(다음 단계).
  job_no                    text UNIQUE NOT NULL,
  poster_id                 uuid NOT NULL REFERENCES public.profiles(id),
  work_date                 timestamptz NOT NULL,        -- 작업 일시
  region_code               text NOT NULL,               -- 지역 코드(필터용)
  region_name               text NOT NULL,               -- 지역명
  lat                       double precision,            -- 표시용 좌표(매칭 미사용)
  lng                       double precision,            -- 표시용 좌표(매칭 미사용)
  address                   text,
  description               text NOT NULL,               -- 작업 정보
  job_type_tags             text[],                      -- 작업 종류 태그(가위/뿌레카/코아 등)
  -- 대표(요약·인덱스) 옵션. 추가 허용 장비는 job_equipment_options(OR 매칭).
  required_category         text REFERENCES public.equipment_categories(code),
  required_model            text,                        -- 요구 최소 모델(NULL=카테고리 전체)
  amount                    int NOT NULL,                -- 일감 금액(소개비 10% 기준)
  payment_method            text,                        -- 직수/싸인지/직접청구/현금
  memo                      text,
  is_designated             boolean NOT NULL DEFAULT false,  -- 지정배차 여부
  designate_password        text,                        -- 지정배차 비밀번호(해시 저장, pgcrypto crypt)
  designate_window_expires  timestamptz,                 -- 지정 윈도우 만료(미수락 시 cron② open 전환)
  designate_target_id       uuid REFERENCES public.profiles(id),  -- 회원번호 지정 대상
  status                    public.job_status NOT NULL DEFAULT 'open',
  priority_window_ends_at   timestamptz,                 -- 우선배차 윈도우 마감
  matched_worker_id         uuid REFERENCES public.profiles(id),  -- 배차된 기사
  matched_at                timestamptz,                 -- 매칭 시각
  photo_points              int NOT NULL DEFAULT 0,      -- 사진 인증 누적 점수(중복 적립 방지)
  created_at                timestamptz NOT NULL DEFAULT now(),

  -- 대표 옵션 무결성: (카테고리, 모델) 조합이 equipment_models 에 존재해야 함.
  -- 모델 NULL 허용(카테고리 전체). 모델이 있으면 카테고리도 있어야 함.
  CONSTRAINT fk_jobs_required_equipment
    FOREIGN KEY (required_category, required_model)
    REFERENCES public.equipment_models(category_code, code)
);

COMMENT ON COLUMN public.jobs.job_no IS '표시용 일감번호 YYMMDD-NNNN(랜덤 4자리 숫자). 트리거에서 생성(다음 단계).';
COMMENT ON COLUMN public.jobs.designate_password IS '지정배차 비밀번호. pgcrypto crypt() 해시로만 저장(평문 금지).';
COMMENT ON COLUMN public.jobs.lat IS '지도 표시용 위도. 매칭/거리 계산에 사용 금지(별점 100% 베이지안).';

-- ----------------------------------------------------------------------------
-- job_equipment_options — 일감 허용 장비(다중·OR 매칭) (docs §2.1)
-- PK (job_id, category, COALESCE(min_model,'')) — min_model NULL 도 유일성 보장.
-- min_model NULL → '' 정규화 생성열(min_model_key)로 PK 구성.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.job_equipment_options (
  job_id        uuid NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
  category      text NOT NULL REFERENCES public.equipment_categories(code),
  min_model     text,   -- 허용 최소 모델코드(이상 매칭). NULL=카테고리 전체.
  -- min_model NULL 을 빈문자로 정규화한 PK 구성용 생성열.
  min_model_key text GENERATED ALWAYS AS (COALESCE(min_model, '')) STORED,

  -- (category, min_model) 무결성: min_model 이 있으면 equipment_models 에 존재해야 함.
  CONSTRAINT fk_job_options_equipment
    FOREIGN KEY (category, min_model)
    REFERENCES public.equipment_models(category_code, code),
  -- PK: 같은 일감에 (카테고리, 최소모델) 중복 옵션 방지.
  CONSTRAINT pk_job_equipment_options
    PRIMARY KEY (job_id, category, min_model_key)
);

-- ----------------------------------------------------------------------------
-- 인덱스 (docs §2.3)
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_jobs_status        ON public.jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_work_date      ON public.jobs(work_date);
CREATE INDEX IF NOT EXISTS idx_jobs_region         ON public.jobs(region_code);
CREATE INDEX IF NOT EXISTS idx_jobs_required       ON public.jobs(required_category, required_model);
CREATE INDEX IF NOT EXISTS idx_jobs_poster         ON public.jobs(poster_id);
CREATE INDEX IF NOT EXISTS idx_jobs_worker         ON public.jobs(matched_worker_id);

-- 발주이력 카운트(직전 3개월 매칭성사 일반발주, 지정배차 제외)
CREATE INDEX IF NOT EXISTS idx_jobs_poster_matched ON public.jobs(poster_id, matched_at)
  WHERE status IN ('matched','completed') AND is_designated = false;

-- 시간충돌 검사용(매칭된 기사의 작업일)
CREATE INDEX IF NOT EXISTS idx_jobs_worker_date    ON public.jobs(matched_worker_id, work_date)
  WHERE status IN ('matched','completed');
CREATE INDEX IF NOT EXISTS idx_jobs_poster_date    ON public.jobs(poster_id, work_date);

CREATE INDEX IF NOT EXISTS idx_job_options_job     ON public.job_equipment_options(job_id);

-- ----------------------------------------------------------------------------
-- RLS: 쓰기는 SECURITY DEFINER RPC(다음 단계). 여기서는 ENABLE 만 하고,
-- jobs SELECT 정책은 user_blocks 생성 후 별도 파일(20260625010010)에서 정의.
-- job_equipment_options SELECT 는 부모 jobs 가시성에 종속(아래).
-- ----------------------------------------------------------------------------
ALTER TABLE public.jobs                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_equipment_options ENABLE ROW LEVEL SECURITY;

-- 옵션 조회: 열람 가능한 일감(jobs RLS 통과)의 옵션만 노출.
CREATE POLICY "일감 옵션 조회" ON public.job_equipment_options
  FOR SELECT USING (
    job_id IN (SELECT id FROM public.jobs)
  );
