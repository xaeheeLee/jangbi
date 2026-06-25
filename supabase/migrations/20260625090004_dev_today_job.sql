-- ⚠️ 개발 전용: 강남(우선배차) 일감 work_date를 오늘로 — 캘린더 오늘 카드 검증용. 운영 no-op.
DO $$
DECLARE v_uid uuid;
BEGIN
  SELECT id INTO v_uid FROM public.profiles WHERE phone = '010-9999-0001';
  IF v_uid IS NULL THEN RETURN; END IF;
  UPDATE public.jobs SET work_date = date_trunc('day', now()) + interval '8 hours'
   WHERE poster_id = v_uid AND description = '[시드] 강남 터파기';
END $$;
