-- 보안: 관리자 전용 RPC를 service_role(관리자웹 서버)만 실행 가능하게 제한.
-- 결함: approve_withdraw/reject_withdraw/admin_adjust_score 에 관리자 가드가 없어
--       일반 인증 사용자가 자기 인출을 직접 승인하거나 평점을 조작할 수 있었음.
-- 해법: PUBLIC/anon/authenticated 의 EXECUTE 회수, service_role 에만 부여.
--       관리자웹은 service_role 키로 호출(서버 전용).

REVOKE EXECUTE ON FUNCTION public.approve_withdraw(uuid)              FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.reject_withdraw(uuid, text)        FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_adjust_score(uuid, int, text) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.approve_withdraw(uuid)               TO service_role;
GRANT EXECUTE ON FUNCTION public.reject_withdraw(uuid, text)         TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_adjust_score(uuid, int, text)  TO service_role;
