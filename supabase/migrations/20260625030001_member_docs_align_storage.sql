-- ============================================================================
-- 서류 5종을 고객 컨펌 목업(Mockup_0425)에 정렬 + 비공개 Storage 버킷
-- 목업 기준 5종: 사업자등록증/건설기계조종사면허/자동차보험증권/차량등록증/통장사본
-- (dev_plan §2.1의 equipment_reg·photo → vehicle_reg·bankbook 으로 교체)
-- 표는 비어 있어 안전. 발주자에겐 마스킹본만 노출(원본 비공개) 원칙 유지.
-- ============================================================================

-- 1) doc_type CHECK 재정의
ALTER TABLE public.member_documents
  DROP CONSTRAINT IF EXISTS member_documents_doc_type_check;

ALTER TABLE public.member_documents
  ADD CONSTRAINT member_documents_doc_type_check
  CHECK (doc_type IN ('business_reg','license','insurance','vehicle_reg','bankbook'));

COMMENT ON COLUMN public.member_documents.doc_type IS
  '서류 5종(목업 기준): business_reg(사업자등록증)/license(건설기계조종사면허)/insurance(자동차보험증권)/vehicle_reg(차량등록증)/bankbook(통장사본)';

-- 2) 비공개 Storage 버킷 (가입 서류 원본/마스킹 보관)
INSERT INTO storage.buckets (id, name, public)
VALUES ('member-docs', 'member-docs', false)
ON CONFLICT (id) DO NOTHING;

-- 3) Storage RLS: 본인 폴더(member-docs/{auth.uid}/...)만 관리.
--    경로 규칙: '{user_id}/{doc_type}_{original|masked}.ext'
--    발주자 열람은 관리자/서버가 발급한 서명URL(마스킹본)로만 — 직접 정책 없음.
DROP POLICY IF EXISTS "본인 서류 업로드" ON storage.objects;
CREATE POLICY "본인 서류 업로드" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'member-docs'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "본인 서류 조회" ON storage.objects;
CREATE POLICY "본인 서류 조회" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'member-docs'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "본인 서류 수정" ON storage.objects;
CREATE POLICY "본인 서류 수정" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'member-docs'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
