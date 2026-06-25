-- ⚠️ 개발 전용: 우선배차 검증용 기사C 활성화 + 잔액 + 배차권 1장. 운영 no-op.
DO $$
DECLARE v_uid uuid; v_exp int;
BEGIN
  SELECT id INTO v_uid FROM public.profiles WHERE phone = '010-7777-0001';
  IF v_uid IS NULL THEN RAISE NOTICE '[dev] 기사C 없음'; RETURN; END IF;
  UPDATE public.profiles
    SET membership_status='active', point_balance=100000, bank_account='신한 111-222-333'
    WHERE id=v_uid;
  IF NOT EXISTS (SELECT 1 FROM public.point_transactions WHERE user_id=v_uid AND memo='기사C 시드충전') THEN
    INSERT INTO public.point_transactions(user_id,type,amount,balance_after,memo)
    VALUES (v_uid,'charge',100000,100000,'기사C 시드충전');
  END IF;
  -- 배차권 1장(미사용)
  SELECT (value)::int INTO v_exp FROM public.app_settings WHERE key='ticket_expiry_days';
  IF NOT EXISTS (SELECT 1 FROM public.priority_tickets WHERE owner_id=v_uid AND used_at IS NULL) THEN
    INSERT INTO public.priority_tickets(owner_id, source, expires_at)
    VALUES (v_uid, 'admin', now() + make_interval(days => v_exp));
  END IF;
END $$;
