-- DEV ONLY: 검증용 일감 status=matched 보정. 운영 no-op.
UPDATE public.jobs SET status = 'matched'
 WHERE description = '[시드] 현장사진 검증용' AND matched_worker_id IS NOT NULL;
