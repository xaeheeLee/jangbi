-- ============================================================================
-- 인증 지원: 가입 시 profiles 자동 생성 트리거 + member_documents 본인 쓰기 정책
-- B-17: 전화번호+비밀번호 인증은 Supabase Auth(email+password)에
--       전화번호를 합성이메일({digits}@phone.jeonjungbae.app)로 매핑해 사용.
--       실제 전화번호/이름/보유장비는 signUp 시 user_metadata 로 전달 → 본 트리거가 프로필 생성.
-- ============================================================================

-- 신규 auth 유저 → profiles(pending) 생성 + member_no 6자리 발급
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_member_no text;
  v_try int := 0;
BEGIN
  -- 6자리 숫자 회원번호(유일) 발급
  LOOP
    v_member_no := lpad(((floor(random() * 900000))::int + 100000)::text, 6, '0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.profiles WHERE member_no = v_member_no);
    v_try := v_try + 1;
    IF v_try > 50 THEN
      RAISE EXCEPTION 'MEMBER_NO_GEN_FAILED';
    END IF;
  END LOOP;

  INSERT INTO public.profiles (
    id, member_no, name, phone,
    equipment_category, equipment_model, membership_status
  ) VALUES (
    NEW.id,
    v_member_no,
    coalesce(NEW.raw_user_meta_data ->> 'name', ''),
    coalesce(NEW.raw_user_meta_data ->> 'phone', ''),
    nullif(NEW.raw_user_meta_data ->> 'equipment_category', ''),
    nullif(NEW.raw_user_meta_data ->> 'equipment_model', ''),
    'pending'
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- member_documents: 본인 서류 등록/수정(메타데이터 행). 원본 보안은 Storage 정책이 담당.
DROP POLICY IF EXISTS "본인 서류 등록" ON public.member_documents;
CREATE POLICY "본인 서류 등록" ON public.member_documents
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "본인 서류 수정" ON public.member_documents;
CREATE POLICY "본인 서류 수정" ON public.member_documents
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
