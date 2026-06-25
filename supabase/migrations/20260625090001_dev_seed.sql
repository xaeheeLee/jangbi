-- ============================================================================
-- ⚠️ 개발 전용 시드 (데이터 탭 검증용). 운영 배포 전 삭제 권장.
-- 테스트 유저(010-9999-0001)가 없으면 아무것도 하지 않음(운영 안전·멱등).
-- 활성화 + 샘플 충전 원장 + 샘플 일감 2건(트리거가 job_no/티켓 생성).
-- ============================================================================
DO $$
DECLARE
  v_uid uuid;
BEGIN
  SELECT id INTO v_uid FROM public.profiles WHERE phone = '010-9999-0001' LIMIT 1;
  IF v_uid IS NULL THEN
    RAISE NOTICE '[dev_seed] 테스트 유저 없음 — 건너뜀';
    RETURN;
  END IF;

  -- 정회원 전환 + 잔액
  UPDATE public.profiles
    SET membership_status = 'active', point_balance = 50000
    WHERE id = v_uid;

  -- 지갑: 충전 원장 1건
  IF NOT EXISTS (SELECT 1 FROM public.point_transactions WHERE user_id = v_uid AND memo = '개발 시드 충전') THEN
    INSERT INTO public.point_transactions(user_id, type, amount, balance_after, memo)
    VALUES (v_uid, 'charge', 50000, 50000, '개발 시드 충전');
  END IF;

  -- 샘플 일감 2건 (job_no는 트리거 생성, 발급 티켓으로 배차권 탭도 채워짐)
  IF NOT EXISTS (SELECT 1 FROM public.jobs WHERE poster_id = v_uid AND description = '[시드] 강남 터파기') THEN
    INSERT INTO public.jobs(poster_id, work_date, region_code, region_name, address,
                            description, job_type_tags, required_category, required_model,
                            amount, payment_method)
    VALUES (v_uid, now() + interval '1 day', '서울', '서울 강남구', '역삼동 123-4',
            '[시드] 강남 터파기', ARRAY['터파기','상차'], 'track', '06LC', 480000, '직수');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.jobs WHERE poster_id = v_uid AND description = '[시드] 분당 파일공사') THEN
    INSERT INTO public.jobs(poster_id, work_date, region_code, region_name, address,
                            description, job_type_tags, required_category, required_model,
                            amount, payment_method)
    VALUES (v_uid, now() + interval '2 day', '경기', '경기 성남시', '분당구 567',
            '[시드] 분당 파일공사', ARRAY['파일','천공'], 'mini', '035', 350000, '현금');
  END IF;

  RAISE NOTICE '[dev_seed] 완료 uid=%', v_uid;
END $$;
