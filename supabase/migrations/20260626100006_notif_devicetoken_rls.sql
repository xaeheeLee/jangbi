-- 인앱 알림센터(읽음 처리) + FCM 디바이스토큰 등록용 본인 RLS.
-- notifications: 본인 알림 읽음(UPDATE) — 본인 것만.
DROP POLICY IF EXISTS "본인 알림 읽음처리" ON public.notifications;
CREATE POLICY "본인 알림 읽음처리" ON public.notifications
  FOR UPDATE TO authenticated
  USING (recipient_id = auth.uid()) WITH CHECK (recipient_id = auth.uid());

-- device_tokens: 본인 토큰 등록/조회/수정(FCM 추후 연동).
DROP POLICY IF EXISTS "본인 토큰 조회" ON public.device_tokens;
CREATE POLICY "본인 토큰 조회" ON public.device_tokens
  FOR SELECT TO authenticated USING (user_id = auth.uid());
DROP POLICY IF EXISTS "본인 토큰 등록" ON public.device_tokens;
CREATE POLICY "본인 토큰 등록" ON public.device_tokens
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "본인 토큰 수정" ON public.device_tokens;
CREATE POLICY "본인 토큰 수정" ON public.device_tokens
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "본인 토큰 삭제" ON public.device_tokens;
CREATE POLICY "본인 토큰 삭제" ON public.device_tokens
  FOR DELETE TO authenticated USING (user_id = auth.uid());
