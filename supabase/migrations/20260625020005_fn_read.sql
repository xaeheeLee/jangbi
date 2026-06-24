-- ============================================================================
-- 전중배 — 15. 읽기 RPC (발주자 전용, SECURITY DEFINER)
-- 근거: docs/01_dev_plan_v3.0.md §2.2.
-- 매칭 성사 후 발주자에게만 기사 연락처 / 마스킹 서류 경로를 노출한다.
-- ⚠ Storage 서명URL 은 SQL 에서 직접 생성 불가(Supabase Storage API/Edge 담당).
--   따라서 본 RPC 는 '권한 검증 후 마스킹본 경로'만 반환하고, 서명URL 발급은
--   클라이언트가 storage.from(bucket).createSignedUrl(path) 로 수행한다(원본 비공개 유지).
-- 두 함수 모두 auth.uid() = 발주자 + 일감 matched/completed 일 때만 결과 반환.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 매칭 상대(기사) 연락처 — get_matched_contact (발주자 전용)
--   매칭/완료 상태이고 호출자가 발주자일 때만 기사 연락처 반환.
--   기사도 자신이 배차받은 일감의 발주자 연락처를 동일 방식으로 받을 수 있어야 하므로
--   양측(발주자→기사 / 기사→발주자) 모두 허용한다.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_matched_contact(p_job_id uuid)
RETURNS TABLE(name text, phone text, bank_account text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_job   public.jobs;
  v_other uuid;
BEGIN
  SELECT * INTO v_job FROM public.jobs WHERE id = p_job_id;
  IF v_job.id IS NULL OR v_job.status NOT IN ('matched', 'completed') THEN
    RAISE EXCEPTION 'JOB_UNAVAILABLE';
  END IF;

  -- 호출자가 발주자면 상대=기사, 호출자가 기사면 상대=발주자. 그 외는 거부.
  IF auth.uid() = v_job.poster_id THEN
    v_other := v_job.matched_worker_id;
  ELSIF auth.uid() = v_job.matched_worker_id THEN
    v_other := v_job.poster_id;
  ELSE
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  RETURN QUERY
  SELECT p.name, p.phone, p.bank_account
  FROM public.profiles p WHERE p.id = v_other;
END;
$$;

-- ----------------------------------------------------------------------------
-- 매칭된 기사 서류(마스킹본 경로) — get_matched_worker_documents (발주자 전용)
--   매칭/완료 일감의 발주자만, 기사의 masked_path 가 있는 서류 경로를 받는다.
--   원본(original_path)은 절대 노출하지 않는다(관리자 검수 전용).
--   반환 masked_path 로 클라이언트가 서명URL 을 발급(비공개 버킷).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_matched_worker_documents(p_job_id uuid)
RETURNS TABLE(doc_type text, masked_path text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  SELECT d.doc_type, d.masked_path
  FROM public.member_documents d
  JOIN public.jobs j ON j.id = p_job_id
  WHERE j.poster_id = auth.uid()                 -- 발주자 본인만
    AND j.status IN ('matched', 'completed')
    AND d.user_id = j.matched_worker_id          -- 배차된 기사 서류
    AND d.masked_path IS NOT NULL;               -- 마스킹본만(원본 비공개)
END;
$$;

COMMENT ON FUNCTION public.get_matched_worker_documents(uuid)
  IS '발주자 전용. 매칭된 기사 서류의 masked_path 만 반환(원본 비공개). 서명URL 은 클라이언트 발급.';
