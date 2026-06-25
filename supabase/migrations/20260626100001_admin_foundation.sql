-- ============================================================================
-- 전중배 P7 — 관리자 기반(Admin Foundation)
-- 근거: docs/01_dev_plan_v3.0.md §8(P7 관리자 웹), CLAUDE.md '§2 RLS·SECURITY DEFINER'.
-- 설계: 관리자 식별 = profiles.is_admin. 관리자 작업 RPC는 내부에서 is_admin 검증
--       (authenticated 호출 가능, service_role 키 불필요).
--
-- 구성:
--   1) profiles.is_admin 컬럼(자가설정 불가 — UPDATE 컬럼 GRANT 목록(030003)에 미포함)
--   2) is_admin_user() 헬퍼 + 관리자 전체조회 SELECT 정책(기존 본인한정 정책과 OR 동작)
--   3) 관리자 작업 RPC(기존 3개 + 가드, 신규 2개) — 전부 SECURITY DEFINER + 내부 가드
--   4) 개발용: 테스트 유저(010-9999-0001) 관리자 승격
--
-- 모든 함수 SECURITY DEFINER + SET search_path = public, pg_temp.
-- 기존 RPC 본문 로직은 가드 추가 외 변경 없음(20260625020007_fn_withdraw.sql,
-- 20260625020004_fn_points.sql 의 정의를 그대로 복제 + BEGIN 직후 가드만 삽입).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. is_admin 컬럼
--   ⚠ profiles UPDATE 컬럼 GRANT 목록(030003)에 is_admin 미포함 → 일반 사용자
--     자가설정 불가(안전). 여기서 GRANT 추가하지 않는다.
-- ----------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_admin boolean NOT NULL DEFAULT false;

-- ----------------------------------------------------------------------------
-- 2. is_admin_user() 헬퍼
--   SECURITY DEFINER 로 profiles 를 읽으므로 RLS 우회 → SELECT 정책 안에서
--   호출해도 정책 재평가가 일어나지 않아 무한재귀 없음(20260625090002 와 동일 패턴).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin_user()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT coalesce((SELECT is_admin FROM public.profiles WHERE id = auth.uid()), false)
$$;

-- ----------------------------------------------------------------------------
-- 2-1. 관리자 전체조회 SELECT 정책
--   기존 본인한정 정책은 유지 → 동일 명령(SELECT)에 정책이 여러 개면 OR 로 결합.
--   즉 본인 행 OR (관리자면 전체). 정책명은 기존과 충돌하지 않게 신규 명명.
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "관리자 전체 조회 profiles"           ON public.profiles;
DROP POLICY IF EXISTS "관리자 전체 조회 withdrawals"        ON public.withdrawals;
DROP POLICY IF EXISTS "관리자 전체 조회 member_documents"   ON public.member_documents;
DROP POLICY IF EXISTS "관리자 전체 조회 point_transactions" ON public.point_transactions;
DROP POLICY IF EXISTS "관리자 전체 조회 charges"            ON public.charges;
DROP POLICY IF EXISTS "관리자 전체 조회 jobs"               ON public.jobs;
DROP POLICY IF EXISTS "관리자 전체 조회 job_applications"   ON public.job_applications;
DROP POLICY IF EXISTS "관리자 전체 조회 priority_tickets"   ON public.priority_tickets;
DROP POLICY IF EXISTS "관리자 전체 조회 admin_score_log"    ON public.admin_score_log;
DROP POLICY IF EXISTS "관리자 전체 조회 job_photos"         ON public.job_photos;

CREATE POLICY "관리자 전체 조회 profiles"
  ON public.profiles           FOR SELECT USING (public.is_admin_user());
CREATE POLICY "관리자 전체 조회 withdrawals"
  ON public.withdrawals        FOR SELECT USING (public.is_admin_user());
CREATE POLICY "관리자 전체 조회 member_documents"
  ON public.member_documents   FOR SELECT USING (public.is_admin_user());
CREATE POLICY "관리자 전체 조회 point_transactions"
  ON public.point_transactions FOR SELECT USING (public.is_admin_user());
CREATE POLICY "관리자 전체 조회 charges"
  ON public.charges            FOR SELECT USING (public.is_admin_user());
CREATE POLICY "관리자 전체 조회 jobs"
  ON public.jobs               FOR SELECT USING (public.is_admin_user());
CREATE POLICY "관리자 전체 조회 job_applications"
  ON public.job_applications   FOR SELECT USING (public.is_admin_user());
CREATE POLICY "관리자 전체 조회 priority_tickets"
  ON public.priority_tickets   FOR SELECT USING (public.is_admin_user());
CREATE POLICY "관리자 전체 조회 admin_score_log"
  ON public.admin_score_log    FOR SELECT USING (public.is_admin_user());
CREATE POLICY "관리자 전체 조회 job_photos"
  ON public.job_photos         FOR SELECT USING (public.is_admin_user());

-- ----------------------------------------------------------------------------
-- 2-2. notifications.type CHECK 에 'membership_approved' 추가
--   approve_member 알림용. 기존 type 모두 유지하고 1종만 확장(데이터 무해).
-- ----------------------------------------------------------------------------
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (
  'new_job','match_success','match_fail','priority_expired',
  'schedule_conflict','job_cancelled',
  'point_low','membership_suspended','charge_paid',
  'withdraw_processed','ticket_granted',
  'membership_approved'));

-- ============================================================================
-- 3. 관리자 작업 RPC — 내부 is_admin 가드 + SECURITY DEFINER, authenticated 실행
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3-1. approve_withdraw — (20260625020007 본문 복제 + 가드)
--   requested → paid. 신청 시 이미 차감 → 포인트 변동 없음. 락: withdrawals → notifications.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_withdraw(p_withdrawal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_wd public.withdrawals;
BEGIN
  IF NOT public.is_admin_user() THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  -- [withdrawals] requested 건 락.
  SELECT * INTO v_wd FROM public.withdrawals
  WHERE id = p_withdrawal_id AND status = 'requested' FOR UPDATE;
  IF v_wd.id IS NULL THEN RAISE EXCEPTION 'WITHDRAW_INVALID'; END IF;

  -- 신청 시 이미 차감 완료 → 지급 처리(paid)만. 별도 포인트 변동 없음.
  UPDATE public.withdrawals
    SET status = 'paid', processed_by = auth.uid(), processed_at = now()
  WHERE id = p_withdrawal_id;

  -- [notifications] 인출 처리 완료 알림.
  INSERT INTO public.notifications(recipient_id, type, title, body, data)
  VALUES (v_wd.user_id, 'withdraw_processed', '인출이 완료되었습니다',
          v_wd.amount || 'p 인출 지급 완료',
          jsonb_build_object('withdrawal_id', v_wd.id, 'status', 'paid'));

  RETURN jsonb_build_object('withdrawal_id', v_wd.id, 'status', 'paid');
END;
$$;

-- ----------------------------------------------------------------------------
-- 3-2. reject_withdraw — (20260625020007 본문 복제 + 가드)
--   requested → rejected + 차감액 환불. 락: withdrawals → profiles → point_transactions → notifications.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reject_withdraw(
  p_withdrawal_id uuid, p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_wd  public.withdrawals;
  v_bal int;
BEGIN
  IF NOT public.is_admin_user() THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  -- [withdrawals] requested 건 락.
  SELECT * INTO v_wd FROM public.withdrawals
  WHERE id = p_withdrawal_id AND status = 'requested' FOR UPDATE;
  IF v_wd.id IS NULL THEN RAISE EXCEPTION 'WITHDRAW_INVALID'; END IF;

  UPDATE public.withdrawals
    SET status = 'rejected', processed_by = auth.uid(), processed_at = now()
  WHERE id = p_withdrawal_id;

  -- [profiles] 차감액 복구(환불).
  UPDATE public.profiles SET point_balance = point_balance + v_wd.amount
  WHERE id = v_wd.user_id RETURNING point_balance INTO v_bal;

  -- [point_transactions] 환불 원장(balance_after). 인출 취소 → +amount 기록.
  --   type 은 원장 enum 범위 내 admin_adjust 사용(인출 반환 보정).
  INSERT INTO public.point_transactions(user_id, type, amount, balance_after, ref_charge_id, memo)
  VALUES (v_wd.user_id, 'admin_adjust', v_wd.amount, v_bal, v_wd.id,
          '인출 거절 환불' || COALESCE(' - ' || p_reason, ''));

  -- [notifications] 인출 거절 알림.
  INSERT INTO public.notifications(recipient_id, type, title, body, data)
  VALUES (v_wd.user_id, 'withdraw_processed', '인출이 거절되었습니다',
          COALESCE(p_reason, '인출 신청이 거절되어 ' || v_wd.amount || 'p 환불되었습니다.'),
          jsonb_build_object('withdrawal_id', v_wd.id, 'status', 'rejected', 'refunded', v_wd.amount));

  RETURN jsonb_build_object('withdrawal_id', v_wd.id, 'status', 'rejected', 'balance', v_bal);
END;
$$;

-- ----------------------------------------------------------------------------
-- 3-3. admin_adjust_score — (20260625020004 본문 복제 + 가드)
--   admin_score ±조정 + 이력. 락: profiles(UPDATE) → admin_score_log(INSERT).
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
  IF NOT public.is_admin_user() THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

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
-- 3-4. approve_member — 회원 승인(pending → active)
--   is_admin 확인 → 대상이 pending 이면 active 전환 + 승인 알림.
--   락: profiles(원자적 가드: pending 한정 UPDATE) → notifications.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_member(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_status public.membership_status;
BEGIN
  IF NOT public.is_admin_user() THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  -- [profiles] pending 한정 active 전환(원자적 가드). 이미 active/suspended 면 noop.
  UPDATE public.profiles SET membership_status = 'active'
  WHERE id = p_user_id AND membership_status = 'pending'
  RETURNING membership_status INTO v_status;

  IF v_status IS NULL THEN
    -- 대상이 없거나 이미 pending 아님 → 멱등 noop.
    RETURN jsonb_build_object('status', 'noop');
  END IF;

  -- [notifications] 가입 승인 알림.
  INSERT INTO public.notifications(recipient_id, type, title, body, data)
  VALUES (p_user_id, 'membership_approved', '가입이 승인되었습니다',
          '정회원으로 전환되었습니다. 일감 매칭을 이용하실 수 있습니다.',
          jsonb_build_object('status', 'active'));

  RETURN jsonb_build_object('status', 'active');
END;
$$;

-- ----------------------------------------------------------------------------
-- 3-5. set_premium — 프리미엄 명단 토글
--   is_admin 확인 → profiles.is_premium = p_on. 락: profiles.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_premium(p_user_id uuid, p_on boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_premium boolean;
BEGIN
  IF NOT public.is_admin_user() THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  UPDATE public.profiles SET is_premium = p_on
  WHERE id = p_user_id RETURNING is_premium INTO v_premium;
  IF v_premium IS NULL THEN RAISE EXCEPTION 'USER_NOT_FOUND'; END IF;

  RETURN jsonb_build_object('user_id', p_user_id, 'is_premium', v_premium);
END;
$$;

-- ----------------------------------------------------------------------------
-- 3-6. EXECUTE 권한
--   090008 에서 service_role 한정으로 회수했던 3개를 authenticated 에 재허용.
--   이제 함수 본문의 is_admin 가드가 보호(비관리자 호출 시 NOT_AUTHORIZED).
--   신규 2개도 authenticated 실행 허용.
-- ----------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.approve_withdraw(uuid)               TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_withdraw(uuid, text)          TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_adjust_score(uuid, int, text)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_member(uuid)                 TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_premium(uuid, boolean)           TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. 개발용: 테스트 유저(검증기사)를 관리자로
--   대상 없으면 0행(운영 무해·멱등). 운영 배포 전 검토.
-- ----------------------------------------------------------------------------
UPDATE public.profiles SET is_admin = true WHERE phone = '010-9999-0001';
