-- 관리자 백필용: 일감 좌표(lat/lng) 설정. is_admin 게이트, 락: jobs UPDATE 만.
CREATE OR REPLACE FUNCTION public.admin_set_job_geocode(
  p_job_id uuid, p_lat double precision, p_lng double precision
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT public.is_admin_user() THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  UPDATE public.jobs SET lat = p_lat, lng = p_lng WHERE id = p_job_id;
END $$;
REVOKE ALL ON FUNCTION public.admin_set_job_geocode(uuid, double precision, double precision) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_set_job_geocode(uuid, double precision, double precision) TO authenticated;
