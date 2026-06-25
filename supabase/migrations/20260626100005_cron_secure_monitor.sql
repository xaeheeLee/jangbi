-- 보안: cron 함수를 일반 사용자가 직접 호출 못 하게 회수(cron만 실행).
-- 결함: deduct_daily_fee 등이 authenticated 호출 가능 → 사용자가 전체 일일차감 트리거 가능.
REVOKE EXECUTE ON FUNCTION public.deduct_daily_fee()        FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.process_windows()         FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.expire_old_jobs()         FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.auto_complete_jobs()      FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_expiring_tickets() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_point_low()        FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.purge_old_photos()        FROM PUBLIC, anon, authenticated;

-- 관리자 모니터링: 등록된 cron 스케줄 조회(관리자웹 시스템 현황용).
CREATE OR REPLACE FUNCTION public.list_cron_jobs()
RETURNS TABLE(jobname text, schedule text, active boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT public.is_admin_user() THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  RETURN QUERY SELECT j.jobname, j.schedule, j.active FROM cron.job j ORDER BY j.jobname;
END $$;
GRANT EXECUTE ON FUNCTION public.list_cron_jobs() TO authenticated;
