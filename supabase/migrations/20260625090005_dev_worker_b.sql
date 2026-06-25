-- ⚠️ 개발 전용: 매칭 검증용 둘째 유저(기사B) 활성화 + 잔액. 운영 no-op.
DO $$
DECLARE v_uid uuid;
BEGIN
  SELECT id INTO v_uid FROM public.profiles WHERE phone = '010-8888-0001';
  IF v_uid IS NULL THEN RAISE NOTICE '[dev] 기사B 없음'; RETURN; END IF;
  UPDATE public.profiles
    SET membership_status = 'active', point_balance = 100000,
        bank_account = '국민 123-456-7890'
    WHERE id = v_uid;
  IF NOT EXISTS (SELECT 1 FROM public.point_transactions WHERE user_id = v_uid AND memo = '기사B 시드충전') THEN
    INSERT INTO public.point_transactions(user_id, type, amount, balance_after, memo)
    VALUES (v_uid, 'charge', 100000, 100000, '기사B 시드충전');
  END IF;
END $$;
