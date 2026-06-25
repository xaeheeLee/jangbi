-- pg_cron 활성화 + 020006 cron 스케줄 등록(확장 비활성으로 건너뛴 것 재실행).
CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job
      WHERE jobname IN ('deduct-daily-fee','process-windows','expire-old-jobs',
        'auto-complete-jobs','notify-expiring-tickets','notify-point-low','purge-old-photos');
    PERFORM cron.schedule('deduct-daily-fee','5 0 * * *','SELECT public.deduct_daily_fee();');
    PERFORM cron.schedule('process-windows','* * * * *','SELECT public.process_windows();');
    PERFORM cron.schedule('expire-old-jobs','0 0 * * *','SELECT public.expire_old_jobs();');
    PERFORM cron.schedule('auto-complete-jobs','0 1 * * *','SELECT public.auto_complete_jobs();');
    PERFORM cron.schedule('notify-expiring-tickets','0 9 * * *','SELECT public.notify_expiring_tickets();');
    PERFORM cron.schedule('notify-point-low','0 9 * * *','SELECT public.notify_point_low();');
    PERFORM cron.schedule('purge-old-photos','0 2 * * *','SELECT public.purge_old_photos();');
  ELSE
    RAISE NOTICE 'pg_cron 여전히 비활성 — 대시보드 활성화 필요';
  END IF;
END $$;
