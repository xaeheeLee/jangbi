-- ============================================================================
-- 전중배 보안 수정 — 호출자(auth.uid()) 일치 검증 가드 추가
-- 결함: 사용자 id를 파라미터로 받는 SECURITY DEFINER RPC가 호출자와 일치 검증을
--       하지 않아 "남의 id로 대신 행위" 가 가능했음.
-- 조치: apply_general / apply_with_priority / apply_designated / recover_membership
--       4개 함수를 현재 정의 그대로 CREATE OR REPLACE 하되, BEGIN 직후 최상단에
--       호출자 검증 가드 한 줄만 삽입. 기존 로직·시그니처·반환·SECURITY DEFINER·
--       search_path·주석은 일절 변경하지 않음. 가드는 멱등(반복 적용 무해).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 2.5.4 우선 지원 RPC — apply_with_priority
--   락 순서: jobs(FOR UPDATE) → priority_tickets(FOR UPDATE SKIP LOCKED 차감)
--           → job_applications(INSERT). profiles 는 잔액 사전검증 SELECT 만(차감 없음).
--   프리미엄은 티켓 미차감. 하루1건은 finalize 에서 최종검증(여기선 미적용).
--   소개비+수수료 사전 잔액 검증(부족 시 INSUFFICIENT_POINT).
--   장비 불일치는 차단 아님 → equipment_mismatch 기록만.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_with_priority(
  p_job_id uuid, p_applicant_id uuid, p_force_apply boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job        public.jobs;
  v_p          public.profiles;
  v_ticket     uuid;
  v_need       int;
  v_app        uuid;
  v_eq_mismatch boolean;
BEGIN
  IF p_applicant_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  -- [jobs] 대상 일감 락.
  SELECT * INTO v_job FROM public.jobs WHERE id = p_job_id FOR UPDATE;
  IF v_job.id IS NULL THEN RAISE EXCEPTION 'JOB_NOT_FOUND'; END IF;
  IF v_job.is_designated THEN RAISE EXCEPTION 'JOB_UNAVAILABLE'; END IF;
  IF v_job.poster_id = p_applicant_id THEN RAISE EXCEPTION 'SELF_APPLY'; END IF;
  IF v_job.status <> 'priority_window' THEN RAISE EXCEPTION 'JOB_UNAVAILABLE'; END IF;  -- N-1: 문서 §2.5.4 코드 통일

  -- 차단 양방향 가드.
  IF public.is_blocked_pair(p_applicant_id, v_job.poster_id) THEN
    RAISE EXCEPTION 'BLOCKED';
  END IF;

  -- 중복 지원 방지(UNIQUE 제약과 이중 가드).
  IF EXISTS (SELECT 1 FROM public.job_applications
             WHERE job_id = p_job_id AND applicant_id = p_applicant_id) THEN
    RAISE EXCEPTION 'DUPLICATE_APPLICATION';
  END IF;

  -- 신청자 프로필(잔액·등급·장비). 락 없는 SELECT.
  SELECT * INTO v_p FROM public.profiles WHERE id = p_applicant_id;
  IF v_p.membership_status <> 'active' THEN RAISE EXCEPTION 'MEMBERSHIP_SUSPENDED'; END IF;

  -- 장비 일치 판정(불일치=차단 아님, 기록만). p_force_apply 는 안내팝업 확인 의미.
  v_eq_mismatch := NOT public.equipment_matches(
      v_job.id, v_job.required_category, v_job.required_model,
      v_p.equipment_category, v_p.equipment_model);

  -- 소개비 + 플랫폼 수수료 사전 잔액 검증.
  v_need := ceil(v_job.amount * (SELECT (value)::numeric FROM public.app_settings WHERE key = 'referral_rate'))::int
            + (SELECT (value)::int FROM public.app_settings WHERE key = 'platform_fee');
  IF v_p.point_balance < v_need THEN RAISE EXCEPTION 'INSUFFICIENT_POINT'; END IF;

  -- [priority_tickets] 프리미엄이 아니면 우선배차권 1장 차감(만료 빠른 순).
  IF NOT v_p.is_premium THEN
    UPDATE public.priority_tickets SET used_at = now()
    WHERE id = (
      SELECT id FROM public.priority_tickets
      WHERE owner_id = p_applicant_id AND used_at IS NULL AND expires_at > now()
      ORDER BY expires_at ASC
      LIMIT 1 FOR UPDATE SKIP LOCKED
    )
    RETURNING id INTO v_ticket;
    IF v_ticket IS NULL THEN RAISE EXCEPTION 'NO_TICKET'; END IF;
  END IF;

  -- [job_applications] 우선지원 INSERT(별점·발주이력 스냅샷).
  INSERT INTO public.job_applications(
      job_id, applicant_id, ticket_id, is_priority,
      effective_rating, poster_post_count, equipment_mismatch, status)
  VALUES (
      p_job_id, p_applicant_id, v_ticket, true,
      public.effective_rating(v_p.rating_sum, v_p.rating_count),
      public.poster_recent_post_count(p_applicant_id), v_eq_mismatch, 'pending')
  RETURNING id INTO v_app;

  RETURN jsonb_build_object(
    'application_id', v_app,
    'ticket_used', v_ticket,
    'equipment_mismatch', v_eq_mismatch);
END;
$$;

-- ----------------------------------------------------------------------------
-- 2.5.5 일반 지원 RPC — apply_general (선착순 즉시 매칭 + 소개비 정산)
--   락 순서: jobs(FOR UPDATE SKIP LOCKED) → job_applications(INSERT)
--           → settle_referral(profiles → point_transactions). notifications 알림.
--   즉시 매칭(선착순). 하루1건(수락일) 검증 — 프리미엄 면제. 차단 양방향 가드.
--   장비 불일치는 차단 아님(기록만).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_general(
  p_job_id uuid, p_applicant_id uuid, p_force_apply boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job         public.jobs;
  v_p           public.profiles;
  v_need        int;
  v_app         uuid;
  v_eq_mismatch boolean;
BEGIN
  IF p_applicant_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  -- [jobs] open 상태 일감 락(동시 선착순 race 방지).
  --   status='open' 이면 일반발주 + (지정 윈도우 만료 후 cron② 가 open 전환한) 지정발주 모두 포함.
  --   지정발주가 미수락으로 open 전환되면 일반발주로 처리되므로 is_designated 필터를 두지 않는다.
  SELECT * INTO v_job FROM public.jobs
  WHERE id = p_job_id AND status = 'open'
  FOR UPDATE SKIP LOCKED;
  IF v_job.id IS NULL THEN RAISE EXCEPTION 'JOB_NOT_OPEN'; END IF;
  IF v_job.poster_id = p_applicant_id THEN RAISE EXCEPTION 'SELF_APPLY'; END IF;

  -- 차단 양방향 가드.
  IF public.is_blocked_pair(p_applicant_id, v_job.poster_id) THEN
    RAISE EXCEPTION 'BLOCKED';
  END IF;

  IF EXISTS (SELECT 1 FROM public.job_applications
             WHERE job_id = p_job_id AND applicant_id = p_applicant_id) THEN
    RAISE EXCEPTION 'DUPLICATE_APPLICATION';
  END IF;

  SELECT * INTO v_p FROM public.profiles WHERE id = p_applicant_id;
  IF v_p.membership_status <> 'active' THEN RAISE EXCEPTION 'MEMBERSHIP_SUSPENDED'; END IF;

  -- 하루 1건(수락일 기준) — 프리미엄 면제. 같은 날 이미 수락한 일감 있으면 차단.
  IF NOT v_p.is_premium AND EXISTS (
    SELECT 1 FROM public.jobs j2
    WHERE j2.matched_worker_id = p_applicant_id
      AND j2.status IN ('matched', 'completed')
      AND j2.matched_at::date = now()::date
  ) THEN
    RAISE EXCEPTION 'DAILY_LIMIT_EXCEEDED';
  END IF;

  -- 시간충돌(같은 날 동일 작업일시 이미 매칭) — B-6 동일 정책으로 일반지원도 방지.
  IF EXISTS (
    SELECT 1 FROM public.jobs j3
    WHERE j3.matched_worker_id = p_applicant_id
      AND j3.status IN ('matched', 'completed')
      AND j3.work_date = v_job.work_date
  ) THEN
    RAISE EXCEPTION 'SCHEDULE_CONFLICT';
  END IF;

  -- 장비 일치 판정(불일치=기록만).
  v_eq_mismatch := NOT public.equipment_matches(
      v_job.id, v_job.required_category, v_job.required_model,
      v_p.equipment_category, v_p.equipment_model);

  -- 소개비 + 수수료 사전 잔액 검증.
  v_need := ceil(v_job.amount * (SELECT (value)::numeric FROM public.app_settings WHERE key = 'referral_rate'))::int
            + (SELECT (value)::int FROM public.app_settings WHERE key = 'platform_fee');
  IF v_p.point_balance < v_need THEN RAISE EXCEPTION 'INSUFFICIENT_POINT'; END IF;

  -- [jobs] 즉시 매칭.
  UPDATE public.jobs
    SET status = 'matched', matched_worker_id = p_applicant_id, matched_at = now()
  WHERE id = p_job_id;

  -- [job_applications] 수락 지원 기록.
  INSERT INTO public.job_applications(
      job_id, applicant_id, is_priority,
      effective_rating, poster_post_count, equipment_mismatch, status)
  VALUES (
      p_job_id, p_applicant_id, false,
      public.effective_rating(v_p.rating_sum, v_p.rating_count),
      public.poster_recent_post_count(p_applicant_id), v_eq_mismatch, 'accepted')
  RETURNING id INTO v_app;

  -- 소개비/수수료 정산(profiles → point_transactions).
  PERFORM public.settle_referral(p_job_id, p_applicant_id, v_job.poster_id);

  -- [notifications] 매칭 성사 알림(발주자·기사). 락 없음.
  INSERT INTO public.notifications(recipient_id, type, title, body, data)
  VALUES
    (v_job.poster_id, 'match_success', '배차가 성사되었습니다',
     '일감 ' || v_job.job_no || ' 매칭 완료',
     jsonb_build_object('job_id', p_job_id)),
    (p_applicant_id, 'match_success', '배차를 받았습니다',
     '일감 ' || v_job.job_no || ' 배차 완료',
     jsonb_build_object('job_id', p_job_id));

  RETURN jsonb_build_object(
    'status', 'matched', 'job_id', p_job_id,
    'application_id', v_app, 'poster_id', v_job.poster_id,
    'equipment_mismatch', v_eq_mismatch);
END;
$$;

-- ----------------------------------------------------------------------------
-- 2.5.8 지정배차 지원 RPC — apply_designated (비밀번호/회원번호)
--   락 순서: jobs(FOR UPDATE SKIP LOCKED) → job_applications(INSERT)
--           → settle_referral(profiles→ledger) → priority_tickets(보상 INSERT)
--           → notifications.
--   지정배차는 하루1건/우선배차권 미적용. 소개비는 동일 적용. 차단 양방향 가드.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_designated(
  p_job_id uuid, p_applicant_id uuid, p_password text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job     public.jobs;
  v_p       public.profiles;
  v_cnt     int;
  v_per     int;
  v_expiry  int;
  v_app     uuid;
BEGIN
  IF p_applicant_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  -- [jobs] 지정배차 윈도우(designated_window) 일감 락.
  --   문서 pseudocode 는 status='open' 이나 v3.0(2026-06-16) 지정 윈도우 신설로
  --   지정자는 윈도우(designated_window) 동안 지원 → status='designated_window' 가 정상.
  --   윈도우 만료 후 cron② 가 open 으로 전환하면 그 건은 일반발주(apply_general)로 처리.
  SELECT * INTO v_job FROM public.jobs
  WHERE id = p_job_id AND status = 'designated_window' AND is_designated = true
  FOR UPDATE SKIP LOCKED;
  IF v_job.id IS NULL THEN RAISE EXCEPTION 'JOB_NOT_OPEN'; END IF;

  IF v_job.poster_id = p_applicant_id THEN RAISE EXCEPTION 'SELF_APPLY'; END IF;

  -- 차단 양방향 가드.
  IF public.is_blocked_pair(p_applicant_id, v_job.poster_id) THEN
    RAISE EXCEPTION 'BLOCKED';
  END IF;

  -- 지정 검증: 회원번호(designate_target_id) 매칭 또는 비밀번호 해시 일치.
  IF NOT (
    (v_job.designate_target_id IS NOT NULL AND v_job.designate_target_id = p_applicant_id)
    OR (v_job.designate_password IS NOT NULL AND p_password IS NOT NULL
        AND crypt(p_password, v_job.designate_password) = v_job.designate_password)
  ) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT * INTO v_p FROM public.profiles WHERE id = p_applicant_id;
  IF v_p.membership_status <> 'active' THEN RAISE EXCEPTION 'MEMBERSHIP_SUSPENDED'; END IF;
  -- 지정배차: 하루1건/우선배차권 미적용.

  -- [jobs] 매칭 확정.
  UPDATE public.jobs
    SET status = 'matched', matched_worker_id = p_applicant_id, matched_at = now()
  WHERE id = p_job_id;

  -- [job_applications] 수락 기록.
  INSERT INTO public.job_applications(job_id, applicant_id, is_priority, status)
  VALUES (p_job_id, p_applicant_id, false, 'accepted')
  RETURNING id INTO v_app;

  -- 소개비/수수료 정산(기사 → 발주자) — 지정배차도 동일.
  PERFORM public.settle_referral(p_job_id, p_applicant_id, v_job.poster_id);

  -- [priority_tickets] 발주자 보상: 매칭성사 지정배차 누적 N건당 1장.
  SELECT count(*) INTO v_cnt FROM public.jobs
  WHERE poster_id = v_job.poster_id AND is_designated = true
    AND status IN ('matched', 'completed');
  SELECT (value)::int INTO v_per
    FROM public.app_settings WHERE key = 'designated_bonus_per';
  IF v_per > 0 AND v_cnt % v_per = 0 THEN
    SELECT (value)::int INTO v_expiry
      FROM public.app_settings WHERE key = 'ticket_expiry_days';
    INSERT INTO public.priority_tickets(owner_id, source, source_job_id, expires_at)
    VALUES (v_job.poster_id, 'designated_bonus', p_job_id,
            now() + make_interval(days => v_expiry));
  END IF;

  -- [notifications] 매칭 알림.
  INSERT INTO public.notifications(recipient_id, type, title, body, data)
  VALUES
    (v_job.poster_id, 'match_success', '지정배차가 성사되었습니다',
     '일감 ' || v_job.job_no || ' 매칭 완료',
     jsonb_build_object('job_id', p_job_id)),
    (p_applicant_id, 'match_success', '지정배차를 받았습니다',
     '일감 ' || v_job.job_no || ' 배차 완료',
     jsonb_build_object('job_id', p_job_id));

  RETURN jsonb_build_object(
    'status', 'matched', 'job_id', p_job_id, 'poster_id', v_job.poster_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- 멤버십 복구 — recover_membership
--   suspended → active 전환(충전 후 1000p 납부). 락 순서: profiles → point_transactions.
--   잔액 가드(>= daily_fee). 부족 시 INSUFFICIENT_POINT.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recover_membership(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_fee int;
  v_bal int;
BEGIN
  IF p_user_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  SELECT (value)::int INTO v_fee FROM public.app_settings WHERE key = 'daily_fee';

  -- [profiles] suspended + 잔액충분 한정 차감 + active 전환(원자적 가드).
  UPDATE public.profiles
    SET point_balance = point_balance - v_fee, membership_status = 'active'
  WHERE id = p_user_id AND membership_status = 'suspended' AND point_balance >= v_fee
  RETURNING point_balance INTO v_bal;
  IF v_bal IS NULL THEN RAISE EXCEPTION 'INSUFFICIENT_POINT'; END IF;

  -- [point_transactions] 그날치 일일차감 1건 기록.
  INSERT INTO public.point_transactions(user_id, type, amount, balance_after)
  VALUES (p_user_id, 'daily_fee', -v_fee, v_bal);

  RETURN jsonb_build_object('status', 'active', 'balance', v_bal);
END;
$$;
