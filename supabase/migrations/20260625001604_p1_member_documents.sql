-- ============================================================================
-- 전중배 P1 기반 — 04. member_documents (가입 서류 5종)
-- 근거: docs/01_dev_plan_v3.0.md §2.1 member_documents, §2.4 RLS.
-- Storage 는 비공개 버킷 + 서명URL 로만 접근. 발주자에게는 masked_path 만 노출
-- (get_matched_worker_documents RPC, P2~). RLS 는 본인 SELECT 만.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.member_documents (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  -- 서류 5종: license(자격증) / equipment_reg(장비등록증) / insurance(보험)
  --           / business_reg(사업자등록증) / photo(사진)
  doc_type      text NOT NULL CHECK (doc_type IN
                  ('license','equipment_reg','insurance','business_reg','photo')),
  original_path text,   -- 원본(관리자 검수용, 발주자 비공개)
  masked_path   text,   -- 마스킹 공개용(관리자 처리, 발주자 노출)
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_member_documents_user
  ON public.member_documents(user_id);

-- ----------------------------------------------------------------------------
-- RLS (docs §2.4): 본인만 직접 조회. 발주자 열람은 RPC 로만(P2~).
-- ----------------------------------------------------------------------------
ALTER TABLE public.member_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "본인 서류 조회" ON public.member_documents
  FOR SELECT USING (user_id = auth.uid());
