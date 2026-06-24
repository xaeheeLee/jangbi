-- ============================================================================
-- 전중배 P4 — 17. 인출(환급) RPC — request / approve / reject
-- 근거: docs/01_dev_plan_v3.0.md §2.1 withdrawals, docs/12_기능명세서_v1.1.md R1.
-- R1: 충전금 포함 전 잔액 인출, 본인 명의 계좌 한정 + 관리자 승인 게이트 + 원장 기록.
-- 모든 함수 SECURITY DEFINER + SET search_path = public, pg_temp.
-- 모든 포인트 증감은 같은 트랜잭션에서 point_transactions(balance_after) 기록.
--
-- ★ 락 순서(인출은 jobs/priority_tickets 무관):
--     withdrawals → profiles → point_transactions → notifications.
--   (전역 원칙 jobs → priority_tickets → job_applications → profiles → point_transactions
--    → notifications 의 부분집합 — 앞 단계는 인출에 해당 없음.)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- request_withdraw — 인출 신청(즉시 차감 + 신청 레코드 생성)
--   active 회원만. 잔액 검증/차감(원자적 가드) 후 원장(withdraw) 기록.
--   bank_account 는 신청 시점 profiles.bank_account 스냅샷(본인 명의 전제).
--   잔액부족 INSUFFICIENT_POINT. 신청 단계에서 차감하여 이중인출/부족 방지.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.request_withdraw(p_amount int)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_p       public.profiles;
  v_bal     int;
  v_wd      uuid;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'WITHDRAW_INVALID';
  END IF;

  SELECT * INTO v_p FROM public.profiles WHERE id = v_uid;
  IF v_p.id IS NULL THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF v_p.membership_status <> 'active' THEN RAISE EXCEPTION 'MEMBERSHIP_SUSPENDED'; END IF;
  IF v_p.bank_account IS NULL OR v_p.bank_account = '' THEN
    RAISE EXCEPTION 'WITHDRAW_INVALID';  -- 본인 명의 계좌 미등록
  END IF;

  -- [profiles] 잔액 충분 한정 차감(원자적 가드).
  UPDATE public.profiles SET point_balance = point_balance - p_amount
  WHERE id = v_uid AND point_balance >= p_amount
  RETURNING point_balance INTO v_bal;
  IF v_bal IS NULL THEN RAISE EXCEPTION 'INSUFFICIENT_POINT'; END IF;

  -- [withdrawals] 신청 레코드(계좌 스냅샷). ref 연결용 id 확보.
  INSERT INTO public.withdrawals(user_id, amount, status, bank_account)
  VALUES (v_uid, p_amount, 'requested', v_p.bank_account)
  RETURNING id INTO v_wd;

  -- [point_transactions] 인출 차감 원장(balance_after).
  INSERT INTO public.point_transactions(user_id, type, amount, balance_after, ref_charge_id, memo)
  VALUES (v_uid, 'withdraw', -p_amount, v_bal, v_wd, '인출 신청');

  RETURN jsonb_build_object('withdrawal_id', v_wd, 'status', 'requested', 'balance', v_bal);
END;
$$;

-- ----------------------------------------------------------------------------
-- approve_withdraw — 인출 승인/지급 처리(관리자 게이트)
--   ⚠ 호출자 관리자 검증은 관리자웹 service_role / 별도 래퍼에서 수행 전제.
--   requested → paid 전이만(이미 차감됨, 추가 포인트 변동 없음). 지급 사실 기록 + 알림.
--   락 순서: withdrawals → notifications (포인트 변동 없음).
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
-- reject_withdraw — 인출 거절(관리자 게이트) + 차감액 원장 환불
--   ⚠ 호출자 관리자 검증은 관리자웹 service_role / 별도 래퍼에서 수행 전제.
--   requested → rejected. 신청 시 차감한 금액을 profiles 복구 + 원장(admin_adjust)로 되돌림.
--   락 순서: withdrawals → profiles → point_transactions → notifications.
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
