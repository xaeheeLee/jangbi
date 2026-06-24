-- ============================================================================
-- 전중배 P5 — 08. notifications + device_tokens (알림 로그 / FCM 토큰)
-- 근거: docs/01_dev_plan_v3.0.md §2.1(v2.1 유지 + type 추가), §2.3 인덱스, §2.4(v2.1 패턴).
-- 의존: profiles.
-- v3.0 추가 type: point_low, membership_suspended, charge_paid, withdraw_processed, ticket_granted.
-- 알림 INSERT 는 RPC/cron(다음 단계). 읽음처리(UPDATE)는 본인 한정 허용(v2.1 패턴).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- device_tokens — FCM 디바이스 토큰(다중 기기) (v2.1 유지)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.device_tokens (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  token      text NOT NULL,
  platform   text CHECK (platform IN ('ios','android')),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_device_tokens UNIQUE (user_id, token)  -- 중복 방지
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON public.device_tokens(user_id);

-- ----------------------------------------------------------------------------
-- notifications — 알림 로그 (v2.1 type + v3.0 신규 type)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  -- v2.1: new_job, match_success, match_fail, priority_expired, schedule_conflict, job_cancelled
  -- v3.0 추가: point_low, membership_suspended, charge_paid, withdraw_processed, ticket_granted
  type         text NOT NULL CHECK (type IN (
                 'new_job','match_success','match_fail','priority_expired',
                 'schedule_conflict','job_cancelled',
                 'point_low','membership_suspended','charge_paid',
                 'withdraw_processed','ticket_granted')),
  title        text NOT NULL,
  body         text,
  data         jsonb,                          -- 딥링크 등 메타데이터
  read         boolean NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_recipient
  ON public.notifications(recipient_id, created_at DESC);

-- ----------------------------------------------------------------------------
-- RLS (docs §2.4, v2.1 패턴 유지)
--   notifications: 본인 알림 SELECT + 본인 알림 읽음처리 UPDATE.
--   device_tokens: 본인 토큰 FOR ALL(등록/갱신/삭제는 클라이언트 직접, user_id=auth.uid() 가드).
-- ----------------------------------------------------------------------------
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "본인 알림만 조회" ON public.notifications
  FOR SELECT USING (recipient_id = auth.uid());

CREATE POLICY "본인 알림 읽음 처리" ON public.notifications
  FOR UPDATE USING (recipient_id = auth.uid()) WITH CHECK (recipient_id = auth.uid());

CREATE POLICY "본인 토큰 관리" ON public.device_tokens
  FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
