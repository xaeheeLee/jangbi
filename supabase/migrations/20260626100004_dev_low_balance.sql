-- ⚠️ 개발 전용: 기사C 잔액을 1500으로 — 일일차감 후 박탈(suspend) 검증용. 운영 no-op.
DO $$
DECLARE v_uid uuid;
BEGIN
  SELECT id INTO v_uid FROM public.profiles WHERE phone='010-7777-0001';
  IF v_uid IS NULL THEN RETURN; END IF;
  UPDATE public.profiles SET point_balance=1500 WHERE id=v_uid;
END $$;
