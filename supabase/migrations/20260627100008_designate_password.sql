-- 지정배차 비밀번호 해시 저장(평문 금지, pgcrypto). 발주자 본인의 지정 일감만.
-- apply_match 가 crypt(p_password, designate_password)=designate_password 로 검증하므로
-- 동일 pgcrypto crypt/gen_salt(bf) 로 저장한다. 락: jobs UPDATE 만(순서 규칙 준수).
CREATE OR REPLACE FUNCTION public.set_job_designate_password(
  p_job_id uuid,
  p_password text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
  IF p_password IS NULL OR length(btrim(p_password)) = 0 THEN
    RAISE EXCEPTION 'INVALID_PASSWORD';
  END IF;
  UPDATE public.jobs
     SET designate_password = crypt(p_password, gen_salt('bf'))
   WHERE id = p_job_id
     AND poster_id = auth.uid()
     AND is_designated = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED_OR_NOT_FOUND';
  END IF;
END $$;

REVOKE ALL ON FUNCTION public.set_job_designate_password(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.set_job_designate_password(uuid, text) TO authenticated;
