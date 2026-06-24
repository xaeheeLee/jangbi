-- ============================================================================
-- 전중배 P3/P4 — 11. 헬퍼 함수 (베이지안 별점 / 발주이력 / 장비매칭 / 차단)
-- 근거: docs/01_dev_plan_v3.0.md §2.5.1, §2.5.2, §2.2.
-- 모든 정책 수치는 app_settings 에서 읽는다(하드코딩 금지). 거리/GPS 사용 금지.
-- 이 파일은 락을 잡지 않는 순수 계산/판정 헬퍼만 정의한다.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 2.5.1 유효별점(베이지안) — (sum + c*m)/(count + m). 거리 폐지.
--   bayes_c(사전평균), bayes_m(가중치)는 app_settings 에서 읽는다.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.effective_rating(p_sum int, p_count int)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  c numeric;
  m numeric;
BEGIN
  SELECT (value)::numeric INTO c FROM public.app_settings WHERE key = 'bayes_c';
  SELECT (value)::numeric INTO m FROM public.app_settings WHERE key = 'bayes_m';
  -- count+m 은 m>0 이므로 0 나눗셈 불가. 소수 4자리 반올림.
  RETURN ROUND(((p_sum + c * m) / (p_count + m))::numeric, 4);
END;
$$;

COMMENT ON FUNCTION public.effective_rating(int, int)
  IS '베이지안 유효별점 (sum + c*m)/(count + m). c/m 은 app_settings. 매칭 점수 100%.';

-- ----------------------------------------------------------------------------
-- 2.5.2 발주 이력 카운트 — 직전 3개 캘린더월, 매칭성사 일반발주(지정 제외).
--   당월 제외(date_trunc month). 우선순위 3순위(일감횟수) 스냅샷에 사용.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.poster_recent_post_count(p_user_id uuid)
RETURNS int
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT count(*)::int FROM public.jobs
  WHERE poster_id = p_user_id
    AND is_designated = false
    AND status IN ('matched', 'completed')
    AND matched_at >= date_trunc('month', now()) - interval '3 months'
    AND matched_at <  date_trunc('month', now());   -- 당월 제외, 직전 3개월
$$;

COMMENT ON FUNCTION public.poster_recent_post_count(uuid)
  IS '직전 3개 캘린더월 매칭성사 일반발주 수(지정 제외). 매칭 3순위 일감횟수.';

-- ----------------------------------------------------------------------------
-- 장비 매칭 판정 — 기사 보유 장비가 일감의 허용 옵션(대표 required_* +
--   job_equipment_options) 중 하나라도 (카테고리 일치 + 모델 ≥ min_model)이면 일치.
--   equipment_model_rank(=sort_order) 로 '이상(≥)' 판정. 다중 옵션은 OR.
--   ⚠ 불일치는 차단 아님 — apply RPC 에서 equipment_mismatch 플래그로만 기록.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.equipment_matches(
  p_job_id      uuid,
  p_req_cat     text,
  p_req_model   text,
  p_emp_cat     text,
  p_emp_model   text
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  -- ★ C-1 NULL 전파 차단: 기사 장비(p_emp_cat/p_emp_model) 또는 rank 가 NULL 이면
  --   비교가 NULL 이 되어 OR 체인이 의도와 다르게 새는 것을 방지한다.
  --   각 옵션의 '모델 ≥' 비교는 COALESCE(..., false) 로 명시적 false 처리.
  --   p_emp_cat 미설정(NULL)이면 카테고리 일치 자체가 불가 → 전 옵션 불일치.
  SELECT
    -- 대표 옵션(jobs.required_*) 일치
    (
      p_req_cat IS NULL
      OR (
        p_emp_cat IS NOT NULL
        AND p_emp_cat = p_req_cat
        AND (
          p_req_model IS NULL
          OR COALESCE(
               public.equipment_model_rank(p_emp_cat, p_emp_model)
               >= public.equipment_model_rank(p_req_cat, p_req_model),
               false)
        )
      )
    )
    -- 추가 옵션(job_equipment_options) 중 하나라도 일치 (OR)
    OR (
      p_emp_cat IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.job_equipment_options o
        WHERE o.job_id = p_job_id
          AND o.category = p_emp_cat
          AND (
            o.min_model IS NULL
            OR COALESCE(
                 public.equipment_model_rank(p_emp_cat, p_emp_model)
                 >= public.equipment_model_rank(o.category, o.min_model),
                 false)
          )
      )
    );
$$;

COMMENT ON FUNCTION public.equipment_matches(uuid, text, text, text, text)
  IS '장비 일치 판정(대표 required_* + job_equipment_options OR, 모델 ≥). 불일치는 차단 아님.';

-- ----------------------------------------------------------------------------
-- 차단 관계 판정(양방향) — user_blocks 는 단방향 저장이나 효과는 양방향.
--   둘 중 누가 차단했든 true. 매칭/지원 가드 및 finalize 후보 제외에 사용.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_blocked_pair(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_blocks
    WHERE (blocker_id = p_a AND blocked_id = p_b)
       OR (blocker_id = p_b AND blocked_id = p_a)
  );
$$;

COMMENT ON FUNCTION public.is_blocked_pair(uuid, uuid)
  IS '양방향 차단 판정(단방향 저장·양방향 효과). 지원 가드/ finalize 후보 제외.';
