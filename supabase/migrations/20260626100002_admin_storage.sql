-- 관리자웹: 서류 마스킹·사진 인증을 위한 Storage 정책 + 마스킹 RPC.
-- 관리자(is_admin)는 비공개 버킷 객체를 서명URL로 열람 가능해야 함(원본 검수).

-- member-docs: 관리자 조회/업로드(마스킹본)
DROP POLICY IF EXISTS "관리자 서류 조회" ON storage.objects;
CREATE POLICY "관리자 서류 조회" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'member-docs' AND public.is_admin_user());
DROP POLICY IF EXISTS "관리자 서류 업로드" ON storage.objects;
CREATE POLICY "관리자 서류 업로드" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'member-docs' AND public.is_admin_user());
DROP POLICY IF EXISTS "관리자 서류 수정" ON storage.objects;
CREATE POLICY "관리자 서류 수정" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'member-docs' AND public.is_admin_user());

-- job-photos 비공개 버킷(현장 사진) + 본인 업로드 + 관리자 조회
INSERT INTO storage.buckets (id, name, public)
VALUES ('job-photos', 'job-photos', false) ON CONFLICT (id) DO NOTHING;
DROP POLICY IF EXISTS "본인 현장사진 업로드" ON storage.objects;
CREATE POLICY "본인 현장사진 업로드" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'job-photos' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "본인 현장사진 조회" ON storage.objects;
CREATE POLICY "본인 현장사진 조회" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'job-photos' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "관리자 현장사진 조회" ON storage.objects;
CREATE POLICY "관리자 현장사진 조회" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'job-photos' AND public.is_admin_user());

-- 마스킹본 경로 설정 RPC(관리자 전용): member_documents.masked_path 갱신
CREATE OR REPLACE FUNCTION public.set_masked_document(p_doc_id uuid, p_masked_path text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT public.is_admin_user() THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  UPDATE public.member_documents SET masked_path = p_masked_path WHERE id = p_doc_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'DOC_NOT_FOUND'; END IF;
  RETURN jsonb_build_object('doc_id', p_doc_id, 'masked_path', p_masked_path);
END $$;
GRANT EXECUTE ON FUNCTION public.set_masked_document(uuid, text) TO authenticated;
