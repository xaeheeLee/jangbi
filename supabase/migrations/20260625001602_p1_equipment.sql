-- ============================================================================
-- 전중배 P1 기반 — 02. 장비 마스터데이터 (카테고리 + 모델코드)
-- 근거: docs/01_dev_plan_v3.0.md §2.1, docs/13_장비_마스터데이터.md
-- 단일 출처(SSOT). 모델 추가/변경은 이 테이블 시드만 수정(CHECK 하드코딩 금지).
-- 매칭의 '이상(≥)' 판정 기준값은 equipment_models.sort_order (카테고리 내 오름차순).
-- ============================================================================

-- 카테고리: mini(미니굴삭기) / track(굴삭기-트랙) / tire(굴삭기-타이어)
CREATE TABLE IF NOT EXISTS public.equipment_categories (
  code       text PRIMARY KEY,
  label      text NOT NULL,
  sort_order int  NOT NULL
);

-- 모델: 카테고리 내 sort_order 오름차순(작은→큰 장비)
CREATE TABLE IF NOT EXISTS public.equipment_models (
  category_code text    NOT NULL REFERENCES public.equipment_categories(code),
  code          text    NOT NULL,
  label         text    NOT NULL,
  sort_order    int     NOT NULL,
  is_active     boolean NOT NULL DEFAULT true,
  PRIMARY KEY (category_code, code)
);

-- ----------------------------------------------------------------------------
-- 시드 (docs/13_장비_마스터데이터.md §3)
-- ----------------------------------------------------------------------------
INSERT INTO public.equipment_categories (code, label, sort_order) VALUES
  ('mini',  '미니굴삭기',     1),
  ('track', '굴삭기(트랙)',   2),
  ('tire',  '굴삭기(타이어)', 3)
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.equipment_models (category_code, code, label, sort_order) VALUES
  ('mini','008','008',1),('mini','010','010',2),('mini','017','017',3),
  ('mini','020','020',4),('mini','025','025',5),('mini','030','030',6),
  ('mini','035','035',7),
  ('track','02LC','02LC',1),('track','03LC','03LC',2),('track','04LC','04LC',3),
  ('track','06LC','06LC',4),('track','08LC','08LC',5),('track','10LC','10LC',6),
  ('track','380LC','380LC',7),('track','460LC','460LC',8),('track','480LC','480LC',9),
  ('track','530LC','530LC',10),('track','730LC','730LC',11),
  ('tire','03W','03W',1),('tire','06W','06W',2),('tire','08W','08W',3)
ON CONFLICT (category_code, code) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 모델 정렬값 조회 함수 — 매칭 '이상(≥)' 판정에 사용 (docs §2.2)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.equipment_model_rank(p_category text, p_model text)
RETURNS int
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT sort_order FROM public.equipment_models
  WHERE category_code = p_category AND code = p_model;
$$;

-- ----------------------------------------------------------------------------
-- RLS: 마스터데이터는 모든 인증 사용자 읽기 전용
-- ----------------------------------------------------------------------------
ALTER TABLE public.equipment_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.equipment_models     ENABLE ROW LEVEL SECURITY;

CREATE POLICY "장비 카테고리 조회" ON public.equipment_categories
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "장비 모델 조회" ON public.equipment_models
  FOR SELECT USING (auth.role() = 'authenticated');
