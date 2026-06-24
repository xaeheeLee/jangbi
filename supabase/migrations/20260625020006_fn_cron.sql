-- ============================================================================
-- 전중배 — 16. pg_cron 작업 함수 + 스케줄 등록
-- 근거: docs/01_dev_plan_v3.0.md §2.6.
-- 모든 함수 SECURITY DEFINER + SET search_path = public, pg_temp.
-- 모든 수치는 app_settings 에서 읽는다(daily_fee / ticket_expiry_days / photo_retention_days 등).
--
-- ★ B-5: cron 은 매 분 1회 실행되나 우선배차 윈도우는 30초.
--   따라서 '이미 마감시각(priority_window_ends_at)이 경과한' 모든 윈도우를 한 번에
--   처리한다(<= now()). 30초 윈도우라도 다음 분 실행에서 반드시 만료분이 잡힌다.
--   지정 윈도우(designate_window_expires)도 동일하게 경과분 일괄 처리.
--
-- ★ 락 순서: 각 함수 내 RPC 호출(finalize 등)은 자체적으로 jobs→… 락 순서 준수.
--   cron 함수 본체는 만료 대상 id 만 수집 후 RPC 를 건별 호출(행 단위 트랜잭션 효과).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ① deduct_daily_fee — 매일 정회원 일일차감(daily_fee), 부족 시 박탈(suspended).
--   락 순서: profiles(건별 차감/박탈) → point_transactions(원장) → notifications.
--   ★ suspended 상태는 차감 안 함(전체차단·부채누적 없음). active 만 대상.
--   잔액 >= fee → 차감, 미만 → suspended 전환(차감 없음) + 알림.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.deduct_daily_fee()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_fee       int;
  r           record;
  v_bal       int;
  v_deducted  int := 0;
  v_suspended int := 0;
BEGIN
  SELECT (value)::int INTO v_fee FROM public.app_settings WHERE key = 'daily_fee';

  FOR r IN
    SELECT id, point_balance FROM public.profiles
    WHERE membership_status = 'active'
    FOR UPDATE SKIP LOCKED
  LOOP
    IF r.point_balance >= v_fee THEN
      -- [profiles] 차감 → [point_transactions] 원장.
      UPDATE public.profiles SET point_balance = point_balance - v_fee
      WHERE id = r.id RETURNING point_balance INTO v_bal;
      INSERT INTO public.point_transactions(user_id, type, amount, balance_after)
      VALUES (r.id, 'daily_fee', -v_fee, v_bal);
      v_deducted := v_deducted + 1;

      -- S-1: 차감 후 잔액 < daily_fee 면 즉시 suspended(전체차단)로 전환.
      --   CLAUDE.md "suspended=잔액<1000=전체차단" 정의 일치. 다음날 추가차감 방지 효과.
      IF v_bal < v_fee THEN
        UPDATE public.profiles SET membership_status = 'suspended' WHERE id = r.id;
        INSERT INTO public.notifications(recipient_id, type, title, body)
        VALUES (r.id, 'membership_suspended', '정회원이 박탈되었습니다',
                '잔액 부족으로 준회원 전환. 충전 후 ' || v_fee || 'p 납부 시 복구됩니다.');
        v_suspended := v_suspended + 1;
      END IF;
    ELSE
      -- [profiles] 박탈(차감 없음) → [notifications] 박탈 알림.
      UPDATE public.profiles SET membership_status = 'suspended' WHERE id = r.id;
      INSERT INTO public.notifications(recipient_id, type, title, body)
      VALUES (r.id, 'membership_suspended', '정회원이 박탈되었습니다',
              '잔액 부족으로 준회원 전환. 충전 후 ' || v_fee || 'p 납부 시 복구됩니다.');
      v_suspended := v_suspended + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('deducted', v_deducted, 'suspended', v_suspended);
END;
$$;

-- ----------------------------------------------------------------------------
-- ② process_windows — 매 분: 우선배차 윈도우 만료→finalize, 지정 윈도우 만료→open.
--   B-5: priority_window_ends_at <= now() / designate_window_expires <= now() 경과분 일괄.
--   락 순서: 만료 id 수집(잠금 없는 SELECT) 후 finalize_priority_match(자체 락) 건별 호출.
--   지정 만료는 designated_window → open 전환(이후 일반 선착순 = 일반발주 처리).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.process_windows()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r            record;
  v_finalized  int := 0;
  v_opened     int := 0;
BEGIN
  -- 우선배차 윈도우 만료분 finalize(건별 트랜잭션 효과).
  FOR r IN
    SELECT id FROM public.jobs
    WHERE status = 'priority_window' AND priority_window_ends_at <= now()
  LOOP
    PERFORM public.finalize_priority_match(r.id);
    v_finalized := v_finalized + 1;
  END LOOP;

  -- 지정 윈도우 만료분 → open 전환(미수락 일반 선착순). [jobs] 건별 락.
  FOR r IN
    SELECT id FROM public.jobs
    WHERE status = 'designated_window' AND designate_window_expires <= now()
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.jobs
      SET status = 'open', designate_window_expires = NULL
    WHERE id = r.id AND status = 'designated_window';
    v_opened := v_opened + 1;
  END LOOP;

  RETURN jsonb_build_object('finalized', v_finalized, 'opened', v_opened);
END;
$$;

-- ----------------------------------------------------------------------------
-- ③ expire_old_jobs — 매일 자정: 작업일 지난 미매칭 일감 expired 처리.
--   ★ S-3: priority_window 건은 곧장 expired 하지 않고 먼저 finalize 시도하여
--     유효 지원자가 있으면 매칭 기회를 보존한다(매칭 없이 폐기 방지).
--     finalize 후에도 매칭 안 된(open 전환·후보 없음) 건만 expired.
--   대상: open / designated_window / (finalize 후 open 남은) priority_window.
--   ★ 우선지원 배차권은 환불(매칭 불발). 락 순서: jobs → priority_tickets.
--   S-2: 환불 보장일은 app_settings.ticket_refund_min_days.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_old_jobs()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r             record;
  v_count       int := 0;
  v_refund_days int;
BEGIN
  SELECT COALESCE((value)::int, 7) INTO v_refund_days
    FROM public.app_settings WHERE key = 'ticket_refund_min_days';
  IF v_refund_days IS NULL THEN v_refund_days := 7; END IF;  -- 시드 부재 방어

  -- 1) 작업일 지난 priority_window 건은 먼저 finalize(매칭 기회 보존).
  --    finalize 가 자체 락(jobs→…) 순서로 매칭/ open 전환을 처리한다.
  FOR r IN
    SELECT id FROM public.jobs
    WHERE status = 'priority_window' AND work_date < now()
  LOOP
    PERFORM public.finalize_priority_match(r.id);
  END LOOP;

  -- 2) 여전히 미매칭(open/designated_window)인 작업일 경과 건만 expired.
  FOR r IN
    SELECT id FROM public.jobs
    WHERE status IN ('open', 'designated_window')
      AND work_date < now()
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.jobs
      SET status = 'expired', priority_window_ends_at = NULL,
          designate_window_expires = NULL
    WHERE id = r.id;

    -- [priority_tickets] 미매칭 우선지원자 배차권 환불(만료 최소 보장).
    UPDATE public.priority_tickets pt SET used_at = NULL,
      expires_at = GREATEST(pt.expires_at, now() + make_interval(days => v_refund_days))
    WHERE pt.id IN (
      SELECT ticket_id FROM public.job_applications
      WHERE job_id = r.id AND ticket_id IS NOT NULL AND status = 'pending');

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('expired', v_count);
END;
$$;

-- ----------------------------------------------------------------------------
-- ④ auto_complete_jobs — 매일 새벽 1시: 작업일 지난 matched → completed.
--   작업이 끝났다고 보고 자동 완료(정산은 매칭 시점에 이미 끝남).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.auto_complete_jobs()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count int;
BEGIN
  WITH upd AS (
    UPDATE public.jobs SET status = 'completed'
    WHERE status = 'matched' AND work_date < now()
    RETURNING id
  )
  SELECT count(*) INTO v_count FROM upd;
  RETURN jsonb_build_object('completed', v_count);
END;
$$;

-- ----------------------------------------------------------------------------
-- ⑤ notify_expiring_tickets — 매일 09시: 배차권 만료 임박(3일 이내) 알림.
--   미사용·미만료·3일 내 만료 배차권 보유자에게 1회 알림.
--   ★ S-5: 같은 수신자에게 오늘 동일 type 알림이 이미 있으면 스킵(중복 방지).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_expiring_tickets()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count int;
BEGIN
  WITH owners AS (
    SELECT owner_id, count(*) AS cnt, min(expires_at) AS soonest
    FROM public.priority_tickets
    WHERE used_at IS NULL
      AND expires_at > now()
      AND expires_at <= now() + interval '3 days'
    GROUP BY owner_id
  ), ins AS (
    INSERT INTO public.notifications(recipient_id, type, title, body, data)
    SELECT o.owner_id, 'ticket_granted', '우선배차권 만료 임박',
           o.cnt || '장이 곧 만료됩니다.',
           jsonb_build_object('count', o.cnt, 'soonest', o.soonest)
    FROM owners o
    WHERE NOT EXISTS (  -- S-5: 오늘 같은 수신자+type 알림 이미 있으면 스킵
      SELECT 1 FROM public.notifications n
      WHERE n.recipient_id = o.owner_id
        AND n.type = 'ticket_granted'
        AND n.created_at::date = now()::date
    )
    RETURNING id
  )
  SELECT count(*) INTO v_count FROM ins;
  RETURN jsonb_build_object('notified', v_count);
END;
$$;

-- ----------------------------------------------------------------------------
-- ⑥ notify_point_low — 매일 09시: 포인트 잔액 임박(3일치 미만) 경고.
--   active 회원 중 잔액 < daily_fee*3 → 경고 알림. (suspended 는 이미 박탈 통지됨)
--   ★ S-6: 같은 수신자에게 오늘 동일 type 알림이 이미 있으면 스킵(중복 방지).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_point_low()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_fee   int;
  v_count int;
BEGIN
  SELECT (value)::int INTO v_fee FROM public.app_settings WHERE key = 'daily_fee';

  WITH ins AS (
    INSERT INTO public.notifications(recipient_id, type, title, body, data)
    SELECT p.id, 'point_low', '포인트 잔액이 부족합니다',
           '잔액 ' || p.point_balance || 'p. 충전하지 않으면 곧 박탈됩니다.',
           jsonb_build_object('balance', p.point_balance)
    FROM public.profiles p
    WHERE p.membership_status = 'active'
      AND p.point_balance < v_fee * 3
      AND NOT EXISTS (  -- S-6: 오늘 같은 수신자+type 알림 이미 있으면 스킵
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = p.id
          AND n.type = 'point_low'
          AND n.created_at::date = now()::date
      )
    RETURNING id
  )
  SELECT count(*) INTO v_count FROM ins;
  RETURN jsonb_build_object('notified', v_count);
END;
$$;

-- ----------------------------------------------------------------------------
-- ⑦ purge_old_photos — 매일 새벽: 사진 보관 만료(photo_retention_days) 경과분 정리.
--   ★ 원본 Storage 객체 정리는 SQL 범위 밖(Edge/배치). 여기서는 만료 레코드의
--   storage_path 를 백업 큐(notifications data 로 관리자에 통지)로 넘기는 개념만 구현.
--   실제 객체 삭제·장기보관 백업은 관리자 배치가 storage_path 기준 수행(원본 비공개 유지).
--   여기서는 DB 행 자체는 보존(감사)하고, 보관만료 표시는 별도 컬럼 없이 조회로 대체 가능.
--   → 1차 구현: 만료 대상 건수만 집계하여 반환(파괴적 삭제는 배치로 위임, 데이터 손실 방지).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purge_old_photos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_days  int;
  v_count int;
BEGIN
  SELECT (value)::int INTO v_days FROM public.app_settings WHERE key = 'photo_retention_days';
  SELECT count(*) INTO v_count FROM public.job_photos
  WHERE taken_at < now() - make_interval(days => v_days);
  -- 파괴적 삭제/백업은 관리자 배치(Edge)가 storage_path 기준 수행. 여기선 집계만.
  RETURN jsonb_build_object('expired_photos', v_count);
END;
$$;

-- ============================================================================
-- pg_cron 스케줄 등록 (docs §2.6)
--   ⚠ Supabase 대시보드 Database > Extensions 에서 pg_cron 확장을 먼저 활성화해야 함.
--   ⚠ cron.schedule 은 슈퍼유저/postgres 권한 필요 — Supabase SQL Editor(서비스 롤)에서 실행.
--   멱등: 동일 jobname 재등록 시 cron.unschedule 후 재등록.
-- ============================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- 기존 동일 job 제거(멱등). cron.jobname 기준.
    PERFORM cron.unschedule(jobid)
      FROM cron.job
      WHERE jobname IN (
        'deduct-daily-fee','process-windows','expire-old-jobs',
        'auto-complete-jobs','notify-expiring-tickets','notify-point-low',
        'purge-old-photos');

    -- ① 매일 00:05 일일차감
    PERFORM cron.schedule('deduct-daily-fee', '5 0 * * *',
      'SELECT public.deduct_daily_fee();');
    -- ② 매 분 윈도우 처리(우선배차 finalize + 지정 만료 open)
    PERFORM cron.schedule('process-windows', '* * * * *',
      'SELECT public.process_windows();');
    -- ③ 매일 자정 지난 일감 expired
    PERFORM cron.schedule('expire-old-jobs', '0 0 * * *',
      'SELECT public.expire_old_jobs();');
    -- ④ 매일 01:00 matched → completed
    PERFORM cron.schedule('auto-complete-jobs', '0 1 * * *',
      'SELECT public.auto_complete_jobs();');
    -- ⑤ 매일 09:00 배차권 만료 임박 알림
    PERFORM cron.schedule('notify-expiring-tickets', '0 9 * * *',
      'SELECT public.notify_expiring_tickets();');
    -- ⑥ 매일 09:00 포인트 잔액 임박 경고
    PERFORM cron.schedule('notify-point-low', '0 9 * * *',
      'SELECT public.notify_point_low();');
    -- ⑦ 매일 02:00 사진 보관 만료 정리(집계/백업 위임)
    PERFORM cron.schedule('purge-old-photos', '0 2 * * *',
      'SELECT public.purge_old_photos();');
  ELSE
    RAISE NOTICE 'pg_cron 확장이 비활성 — 스케줄 미등록. Supabase 대시보드에서 활성화 후 본 DO 블록 재실행.';
  END IF;
END $$;
