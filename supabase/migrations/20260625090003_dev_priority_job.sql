-- ⚠️ 개발 전용: 시드 일감 하나를 우선배차(priority_window)로 — 빨강 카드/카운트다운 검증용.
-- 테스트 유저/일감 없으면 no-op(운영 안전). pg_cron 비활성이라 자동 finalize 안 됨.
DO $$
DECLARE v_uid uuid; v_job uuid;
BEGIN
  SELECT id INTO v_uid FROM public.profiles WHERE phone = '010-9999-0001';
  IF v_uid IS NULL THEN RETURN; END IF;
  SELECT id INTO v_job FROM public.jobs
    WHERE poster_id = v_uid AND description = '[시드] 강남 터파기';
  IF v_job IS NULL THEN RETURN; END IF;
  UPDATE public.jobs
    SET status = 'priority_window',
        priority_window_ends_at = now() + interval '30 minutes'
    WHERE id = v_job;
END $$;
