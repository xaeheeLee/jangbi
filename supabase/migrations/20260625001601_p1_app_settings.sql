-- ============================================================================
-- 전중배 P1 기반 — 01. extensions + app_settings (운영 설정 상수)
-- 근거: docs/01_dev_plan_v3.0.md §2.1 app_settings, CLAUDE.md §3
-- 모든 정책 수치는 이 테이블에서 읽는다(SQL/코드 하드코딩 금지).
-- ============================================================================

-- 확장: uuid 생성(gen_random_uuid), 암호화/해시(crypt 등 — 지정배차 비번 해시 P3)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ----------------------------------------------------------------------------
-- app_settings — key/value 운영 상수 (코드 수정 없이 정책 변경)
-- value 는 text 로 저장하고 사용처에서 형변환(int/numeric)한다.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_settings (
  key         text PRIMARY KEY,
  value       text NOT NULL,
  description text,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.app_settings IS '운영 정책 상수. RPC/cron 에서 SELECT ... INTO 로 읽어 사용. 하드코딩 금지.';

-- 시드: docs/01_dev_plan_v3.0.md §2.1 app_settings 표 값 그대로
INSERT INTO public.app_settings (key, value, description) VALUES
  ('priority_window_seconds',  '30',   '우선배차 윈도우 초(20초 추후 변경 예정)'),
  ('daily_fee',                '1000', '하루 차감 포인트'),
  ('referral_rate',            '0.10', '소개비율'),
  ('platform_fee',             '0',    '매칭 건당 플랫폼 수수료(추후 1000)'),
  ('pg_fee',                   '440',  '충전 PG 수수료(입금액 미포함, 발급 후 포인트에서 차감)'),
  ('vat_rate',                 '0.10', '부가세율'),
  ('bayes_c',                  '3.5',  '베이지안 사전평균'),
  ('bayes_m',                  '5',    '베이지안 가중치'),
  ('designated_bonus_per',     '3',    '지정배차 N건당 우선배차권 1장(발주자·매칭성사 기준)'),
  ('designated_window_seconds','300',  '지정배차 윈도우(5분), 미수락 시 일반 선착순 전환'),
  ('admin_score_default',      '50',   '평점 기본값(관리자 ±1 조정, 매칭 2순위)'),
  ('photo_point_per_phase',    '1',    '사진 단계(도착/작업/종료)당 점수'),
  ('photo_complete_bonus',     '1',    '3종 완비 보너스'),
  ('photo_points_per_ticket',  '40',   '누적 N점당 우선배차권 1장'),
  ('photo_retention_days',     '365',  '사진 보관일(이후 관리자 장기보관 백업)'),
  ('ticket_expiry_days',       '30',   '우선배차권 유효기간(잠정 30일, 조사 후 확정 예정)')
ON CONFLICT (key) DO NOTHING;

-- RLS: 운영 상수는 모든 인증 사용자가 읽기만 가능(쓰기는 관리자/마이그레이션/RPC)
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "설정 읽기" ON public.app_settings
  FOR SELECT USING (auth.role() = 'authenticated');
