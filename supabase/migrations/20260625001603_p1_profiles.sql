-- ============================================================================
-- 전중배 P1 기반 — 03. profiles (기사 프로필 / 회원 상태)
-- 근거: docs/01_dev_plan_v3.0.md §2.1 profiles, §2.2 profiles_public,
--       §2.4 RLS, v2.1 §2.4 profiles RLS 패턴 유지.
-- 의존: equipment_categories / equipment_models (복합 FK).
-- ============================================================================

-- 회원 등급: pending(승인대기) / active(정회원) / suspended(준회원=잔액<1000, 전체차단)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'membership_status') THEN
    CREATE TYPE public.membership_status AS ENUM ('pending', 'active', 'suspended');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.profiles (
  id                 uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  -- 사람이 읽는 회원번호: 6자리 숫자(알파벳 없음). 지정배차/고객센터 식별.
  member_no          text UNIQUE NOT NULL,
  name               text NOT NULL,
  phone              text UNIQUE NOT NULL,           -- 로그인 ID
  bank_account       text,                            -- 매칭 후 공개 / 인출 지급
  business_email     text,
  business_info      jsonb,
  license_type       text,
  -- 보유 장비 (카테고리 + 모델). (category, model) 복합 FK 로 무결성 보장.
  equipment_category text REFERENCES public.equipment_categories(code),
  equipment_model    text,
  rating_sum         int NOT NULL DEFAULT 0,          -- 별점 누적합
  rating_count       int NOT NULL DEFAULT 0,          -- 별점 횟수
  point_balance      int NOT NULL DEFAULT 0,          -- 포인트 잔액(원자적 갱신은 RPC)
  membership_status  public.membership_status NOT NULL DEFAULT 'pending',
  is_premium         boolean NOT NULL DEFAULT false,  -- 프리미엄 배차인 명단(비공개)
  -- 평점(매칭 2순위, 관리자 ±1). 기본값은 app_settings.admin_score_default(50)와 동일.
  admin_score        int NOT NULL DEFAULT 50,
  cert_points        int NOT NULL DEFAULT 0,          -- 사진 인증 누적 점수
  completed_as_worker int NOT NULL DEFAULT 0,         -- 수행 일감 수(통계)
  -- 알림 필터 (docs §2.1 device_tokens/notifications 절)
  notify_regions     text[],
  notify_equipment   jsonb,
  created_at         timestamptz NOT NULL DEFAULT now(),

  -- 보유 장비 무결성: (카테고리, 모델) 조합이 equipment_models 에 존재해야 함.
  -- 모델은 NULL 허용(미설정). 모델이 있으면 카테고리도 있어야 한다.
  CONSTRAINT fk_profiles_equipment
    FOREIGN KEY (equipment_category, equipment_model)
    REFERENCES public.equipment_models(category_code, code),
  -- member_no: 정확히 6자리 숫자
  CONSTRAINT chk_member_no_6digit CHECK (member_no ~ '^[0-9]{6}$')
);

COMMENT ON COLUMN public.profiles.admin_score IS '매칭 2순위 레버. 사용자엔 50점 표시, 우선순위 용도는 비노출. 기본값=app_settings.admin_score_default.';

-- ----------------------------------------------------------------------------
-- 인덱스 (장비 필터 조회용). docs §2.3 의 jobs 인덱스는 P2 에서 작성.
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_profiles_equipment
  ON public.profiles(equipment_category, equipment_model);
CREATE INDEX IF NOT EXISTS idx_profiles_membership
  ON public.profiles(membership_status);

-- ----------------------------------------------------------------------------
-- 뷰: 공개 기본 정보 (is_premium·admin_score·연락처·포인트·발주이력 비노출) docs §2.2
-- security_invoker=false (소유자 postgres 권한으로 base 테이블 RLS 우회).
-- profiles 본인행 RLS로 막힌 '안전 컬럼만' 전체 사용자에게 노출하기 위함 — 의도된 설계.
-- 민감 컬럼은 SELECT 목록에서 제외되어 이 뷰로는 절대 노출되지 않는다.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.profiles_public
  WITH (security_invoker = false) AS
SELECT id, member_no, name, equipment_category, equipment_model,
       rating_sum, rating_count
FROM public.profiles;

GRANT SELECT ON public.profiles_public TO authenticated;

-- ----------------------------------------------------------------------------
-- RLS (docs §2.4): base 테이블은 '본인 행'만 직접 조회.
-- 타인의 공개정보는 profiles_public 뷰, 연락처는 get_matched_contact(SECURITY
-- DEFINER, P2~)로만 제공한다. 이로써 bank_account·phone·point_balance·admin_score·
-- is_premium 등 민감 컬럼이 타인에게 직접 노출되지 않는다.
-- 쓰기 제어는 본인 한정 INSERT/UPDATE, 핵심 로직은 SECURITY DEFINER RPC(P2~).
-- ----------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "본인 프로필 조회" ON public.profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "본인 프로필 생성" ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "본인 프로필 수정" ON public.profiles
  FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
