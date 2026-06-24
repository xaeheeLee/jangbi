-- ============================================================================
-- 전중배 P4 — 14. 포인트 RPC (충전확정 / 멤버십복구 / 평점조정 / 사진인증)
-- 근거: docs/01_dev_plan_v3.0.md §2.5.9, §2.5.8(평점), §2.5.9(사진).
-- 모든 함수 SECURITY DEFINER + SET search_path = public, pg_temp.
-- 모든 포인트 증감은 같은 트랜잭션에서 point_transactions(balance_after) INSERT.
-- 모든 수치는 app_settings 에서 읽는다(daily_fee / photo_* / ticket_expiry_days 등).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 2.5.9 충전 입금 확정 — confirm_charge
--   가상계좌 입금통보(webhook/관리자) → 원금 발급 후 PG 수수료 차감(2건 기록).
--   락 순서: charges(FOR UPDATE) → profiles(가산/차감) → point_transactions(원장).
--   입금액 total_deposit = 원금 + VAT. 발급은 원금(point_amount), 이후 pg_fee 차감.
--   예: 30,000p 충전(입금 33,000) → +30,000p 후 -440p → 실 +29,560p.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.confirm_charge(p_charge_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  c     public.charges;
  v_bal int;
BEGIN
  -- [charges] pending 충전 락(중복 확정 방지).
  SELECT * INTO c FROM public.charges
  WHERE id = p_charge_id AND status = 'pending' FOR UPDATE;
  IF c.id IS NULL THEN
    RETURN jsonb_build_object('status', 'noop');  -- 이미 처리/없음(멱등)
  END IF;

  UPDATE public.charges SET status = 'paid', paid_at = now() WHERE id = p_charge_id;

  -- 1) [profiles] 충전 원금 발급 → [point_transactions] charge.
  UPDATE public.profiles SET point_balance = point_balance + c.point_amount
  WHERE id = c.user_id RETURNING point_balance INTO v_bal;
  INSERT INTO public.point_transactions(user_id, type, amount, balance_after, ref_charge_id)
  VALUES (c.user_id, 'charge', c.point_amount, v_bal, c.id);

  -- 2) [profiles] PG 수수료 차감(사용자 부담) → [point_transactions] pg_fee.
  IF c.pg_fee > 0 THEN
    UPDATE public.profiles SET point_balance = point_balance - c.pg_fee
    WHERE id = c.user_id RETURNING point_balance INTO v_bal;
    INSERT INTO public.point_transactions(user_id, type, amount, balance_after, ref_charge_id)
    VALUES (c.user_id, 'pg_fee', -c.pg_fee, v_bal, c.id);
  END IF;

  -- [notifications] 충전 완료 알림.
  INSERT INTO public.notifications(recipient_id, type, title, body, data)
  VALUES (c.user_id, 'charge_paid', '충전이 완료되었습니다',
          c.point_amount || 'p 충전 (PG수수료 ' || c.pg_fee || 'p 차감)',
          jsonb_build_object('charge_id', c.id, 'balance', v_bal));

  RETURN jsonb_build_object('status', 'paid', 'balance', v_bal);
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

-- ----------------------------------------------------------------------------
-- 2.5.8 평점(관리자 점수) 조정 — admin_adjust_score (매칭 2순위 레버)
--   관리자 전용(호출자 검증은 관리자웹 service_role / 래퍼). admin_score ±조정 + 이력.
--   락 순서: profiles(UPDATE) → admin_score_log(INSERT). 포인트 무관.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_adjust_score(
  p_user_id uuid, p_delta int, p_reason text DEFAULT NULL
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_after int;
BEGIN
  -- [profiles] 평점 조정.
  UPDATE public.profiles SET admin_score = admin_score + p_delta
  WHERE id = p_user_id RETURNING admin_score INTO v_after;
  IF v_after IS NULL THEN RAISE EXCEPTION 'USER_NOT_FOUND'; END IF;

  -- [admin_score_log] 변경 이력(감사).
  INSERT INTO public.admin_score_log(user_id, admin_id, delta, score_after, reason)
  VALUES (p_user_id, auth.uid(), p_delta, v_after, p_reason);

  RETURN v_after;
END;
$$;

-- ----------------------------------------------------------------------------
-- 2.5.9 사진 인증 등록 — register_job_photo (적립 + 40점 시 우선배차권)
--   락 순서: jobs(FOR UPDATE) → profiles(cert_points 가산) → priority_tickets(INSERT)
--           → notifications. 포인트 원장 무관(별점/배차권 적립).
--   점수: phase당 photo_point_per_phase, 3종완비 photo_complete_bonus. 중복적립 방지.
--   누적 photo_points_per_ticket(40)마다 우선배차권 1장.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_job_photo(
  p_job_id uuid, p_phase text, p_storage_path text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job     public.jobs;
  v_ppp     int;
  v_bonus   int;
  v_per     int;
  v_expiry  int;
  v_phases  int;
  v_newpts  int;
  v_delta   int;
  v_after   int;
  v_granted int := 0;
BEGIN
  IF p_phase NOT IN ('arrival', 'work', 'done') THEN
    RAISE EXCEPTION 'INVALID_PHASE';
  END IF;

  -- [jobs] 본인이 배차받은 일감만 인증 가능.
  SELECT * INTO v_job FROM public.jobs WHERE id = p_job_id FOR UPDATE;
  IF v_job.id IS NULL OR v_job.matched_worker_id <> auth.uid() THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  INSERT INTO public.job_photos(job_id, uploader_id, phase, storage_path)
  VALUES (p_job_id, auth.uid(), p_phase, p_storage_path);

  SELECT (value)::int INTO v_ppp    FROM public.app_settings WHERE key = 'photo_point_per_phase';
  SELECT (value)::int INTO v_bonus  FROM public.app_settings WHERE key = 'photo_complete_bonus';
  SELECT (value)::int INTO v_per    FROM public.app_settings WHERE key = 'photo_points_per_ticket';
  SELECT (value)::int INTO v_expiry FROM public.app_settings WHERE key = 'ticket_expiry_days';

  -- 이 일감 점수 재계산(중복 적립 방지) — 고유 phase 수 기준.
  SELECT count(DISTINCT phase) INTO v_phases FROM public.job_photos WHERE job_id = p_job_id;
  v_newpts := v_phases * v_ppp + CASE WHEN v_phases >= 3 THEN v_bonus ELSE 0 END;
  v_delta  := v_newpts - v_job.photo_points;

  IF v_delta > 0 THEN
    -- [jobs] 이 일감 누적점수 갱신.
    UPDATE public.jobs SET photo_points = v_newpts WHERE id = p_job_id;

    -- [profiles] 기사 누적 인증점수 가산.
    UPDATE public.profiles SET cert_points = cert_points + v_delta
    WHERE id = auth.uid() RETURNING cert_points INTO v_after;

    -- [priority_tickets] 40점마다 배차권 1장 발급(잔여점수 보존).
    WHILE v_after >= v_per LOOP
      INSERT INTO public.priority_tickets(owner_id, source, source_job_id, expires_at)
      VALUES (auth.uid(), 'photo_cert', p_job_id, now() + make_interval(days => v_expiry));
      v_after := v_after - v_per;
      v_granted := v_granted + 1;
    END LOOP;

    IF v_granted > 0 THEN
      UPDATE public.profiles SET cert_points = v_after WHERE id = auth.uid();
      -- [notifications] 배차권 지급 알림.
      INSERT INTO public.notifications(recipient_id, type, title, body, data)
      VALUES (auth.uid(), 'ticket_granted', '우선배차권이 지급되었습니다',
              '사진 인증 ' || v_granted || '장 발급',
              jsonb_build_object('job_id', p_job_id, 'granted', v_granted));
    END IF;
  END IF;

  RETURN jsonb_build_object('job_points', v_newpts, 'tickets_granted', v_granted);
END;
$$;
