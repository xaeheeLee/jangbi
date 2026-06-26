-- notifications INSERT → send-push Edge Function 자동 호출(pg_net).
CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION public.tg_notify_push()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM net.http_post(
    url := 'https://twrxjkivuxwgekgyvejv.supabase.co/functions/v1/send-push',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('record', to_jsonb(NEW))
  );
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_notify_push ON public.notifications;
CREATE TRIGGER trg_notify_push AFTER INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.tg_notify_push();
