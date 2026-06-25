-- ============================================================================
-- jobs / job_equipment_options INSERT 정책 (앱의 일감 등록 허용)
-- on_job_created 트리거가 INSERT 시 발동하는 설계라 클라이언트 직접 INSERT가 필요.
-- 안전장치: 본인(poster) 이면서 active 회원만 등록 가능(WITH CHECK).
-- 등록 후 윈도우/티켓/job_no 등은 트리거가 처리.
-- ============================================================================

DROP POLICY IF EXISTS "본인 일감 등록" ON public.jobs;
CREATE POLICY "본인 일감 등록" ON public.jobs
  FOR INSERT TO authenticated
  WITH CHECK (
    poster_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.membership_status = 'active'
    )
  );

DROP POLICY IF EXISTS "본인 일감 옵션 등록" ON public.job_equipment_options;
CREATE POLICY "본인 일감 옵션 등록" ON public.job_equipment_options
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.jobs j
      WHERE j.id = job_id AND j.poster_id = auth.uid()
    )
  );
