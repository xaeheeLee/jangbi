-- ============================================================================
-- 전중배 P2/P3 — 12. 일감 생성 트리거 (job_no 생성 + 지정/일반 분기 + 배차권 발급)
-- 근거: docs/01_dev_plan_v3.0.md §2.5.3.
-- BEFORE INSERT 단계: job_no(YYMMDD-NNNN) 생성 + status 분기 + 윈도우 만료시각 세팅.
-- 일반발주 등록자 배차권 발급은 NEW.id 가 필요하므로 AFTER INSERT 에서 수행.
-- 모든 수치(priority_window_seconds / designated_window_seconds / ticket_expiry_days)는
-- app_settings 에서 읽는다(하드코딩 금지).
--
-- 락 순서: 트리거는 INSERT 중인 NEW.jobs 행(이미 락) → priority_tickets INSERT 만 수행.
--   추가 SELECT(보유자 존재여부)는 잠금 없는 EXISTS 판정이므로 락 순서 위반 없음.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- BEFORE INSERT: job_no 생성 + 상태 분기 (티켓 발급 제외 — id 필요해 AFTER 에서)
--   job_no = YYMMDD-NNNN (날짜 + 랜덤 4자리 숫자, 순차 아님). UNIQUE 충돌 시 재시도.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.on_job_created_before()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_has_holder boolean;
  v_win        int;
  v_desig_win  int;
  v_prefix     text;
  v_candidate  text;
  v_try        int := 0;
BEGIN
  -- job_no 생성: YYMMDD-NNNN (랜덤 4자리). 충돌 시 최대 20회 재시도.
  IF NEW.job_no IS NULL OR NEW.job_no = '' THEN
    v_prefix := to_char(now(), 'YYMMDD');
    LOOP
      v_try := v_try + 1;
      v_candidate := v_prefix || '-' || lpad((floor(random() * 10000))::int::text, 4, '0');
      EXIT WHEN NOT EXISTS (SELECT 1 FROM public.jobs WHERE job_no = v_candidate);
      IF v_try >= 20 THEN
        RAISE EXCEPTION 'JOB_NO_GENERATION_FAILED';
      END IF;
    END LOOP;
    NEW.job_no := v_candidate;
  END IF;

  IF NEW.is_designated THEN
    -- 지정배차: 우선배차권 자동발급 없음. 지정 윈도우(designated_window_seconds, 기본 300초)
    -- 동안 지정자(비번/회원번호 일치)만 지원, 다른 유저는 열람만.
    -- 미수락 시 cron② 가 designate_window_expires < now → status=open 일반 선착순 전환.
    SELECT (value)::int INTO v_desig_win
      FROM public.app_settings WHERE key = 'designated_window_seconds';
    NEW.status := 'designated_window';
    NEW.designate_window_expires := now() + make_interval(secs => v_desig_win);
    RETURN NEW;
  END IF;

  -- 일반 발주: 조건 맞는 우선배차권 보유자 or 프리미엄 배차인 존재 여부 판정.
  --   매칭 가능 장비(대표 required_* + job_equipment_options OR) + active 회원 한정.
  --   본인 제외. (배차권은 미사용·미만료 보유 또는 is_premium)
  --   ⚠ BEFORE INSERT 시점: job_equipment_options 는 아직 미삽입(FK상 job INSERT 후 삽입).
  --     따라서 윈도우 개시 판정은 대표 required_* 기준이며, equipment_matches 의 추가옵션
  --     EXISTS 절은 이 시점엔 빈 집합이다(문서 §2.5.3 pseudocode 와 동일 동작).
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id <> NEW.poster_id
      AND p.membership_status = 'active'
      AND public.equipment_matches(
            NEW.id, NEW.required_category, NEW.required_model,
            p.equipment_category, p.equipment_model)
      AND NOT public.is_blocked_pair(p.id, NEW.poster_id)
      AND (
        p.is_premium = true
        OR EXISTS (
          SELECT 1 FROM public.priority_tickets pt
          WHERE pt.owner_id = p.id AND pt.used_at IS NULL AND pt.expires_at > now()
        )
      )
  ) INTO v_has_holder;

  IF v_has_holder THEN
    SELECT (value)::int INTO v_win
      FROM public.app_settings WHERE key = 'priority_window_seconds';
    NEW.status := 'priority_window';
    NEW.priority_window_ends_at := now() + make_interval(secs => v_win);
  ELSE
    NEW.status := 'open';
  END IF;

  RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- AFTER INSERT: 일반 발주 등록자에게 우선배차권 1장 발급(source='post').
--   NEW.id 가 확정된 뒤 발급해야 source_job_id 를 채울 수 있어 AFTER 단계.
--   지정배차는 발급 없음(매칭 성사 N건당 보상은 apply_designated 에서).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.on_job_created_after()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_expiry int;
BEGIN
  IF NOT NEW.is_designated THEN
    SELECT (value)::int INTO v_expiry
      FROM public.app_settings WHERE key = 'ticket_expiry_days';
    INSERT INTO public.priority_tickets(owner_id, source, source_job_id, expires_at)
    VALUES (NEW.poster_id, 'post', NEW.id, now() + make_interval(days => v_expiry));
  END IF;
  RETURN NULL;  -- AFTER 트리거 반환값 무시
END;
$$;

-- 멱등: 재실행 시 기존 트리거 제거 후 재생성.
DROP TRIGGER IF EXISTS trg_job_created_before ON public.jobs;
CREATE TRIGGER trg_job_created_before
  BEFORE INSERT ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION public.on_job_created_before();

DROP TRIGGER IF EXISTS trg_job_created_after ON public.jobs;
CREATE TRIGGER trg_job_created_after
  AFTER INSERT ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION public.on_job_created_after();
