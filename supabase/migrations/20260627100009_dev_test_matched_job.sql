-- DEV ONLY: 검증기사를 배차기사로 한 테스트 일감(현장사진 인증 검증용). 운영 no-op(가드).
DO $$
DECLARE v_worker uuid; v_poster uuid;
BEGIN
  SELECT id INTO v_worker FROM public.profiles WHERE phone = '010-9999-0001';  -- 검증기사(배차기사)
  SELECT id INTO v_poster FROM public.profiles WHERE phone = '010-8888-0001';  -- 기사B(발주자)
  IF v_worker IS NULL OR v_poster IS NULL THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.jobs WHERE description = '[시드] 현장사진 검증용') THEN
    INSERT INTO public.jobs(poster_id, work_date, region_code, region_name, address,
                            description, job_type_tags, required_category, required_model,
                            amount, payment_method, status, matched_worker_id, matched_at, lat, lng)
    VALUES (v_poster, now() + interval '1 day', '서울', '서울 송파구', '잠실동 40',
            '[시드] 현장사진 검증용', ARRAY['터파기'], 'track', '06LC', 350000, '직수',
            'matched', v_worker, now(), 37.5133, 127.1028);
  END IF;
END $$;
