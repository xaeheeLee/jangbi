# 포크레인 배차앱 — 아키텍처 검토 리포트

---

## 검토 결과 요약

| 구분 | 건수 | 심각도 |
|------|------|--------|
| 치명적 버그 (반드시 수정) | 7건 | 🔴 |
| 설계 개선 권고 | 5건 | 🟡 |
| 누락된 명세 보완 | 4건 | 🟠 |

---

## 🔴 치명적 버그 7건

### BUG-1. 본인이 올린 일감에 본인이 지원 가능한 문제

**현상:** `job_applications` INSERT 정책이 `applicant_id = auth.uid()`만 체크합니다. 자기가 등록한 일감에 자기가 지원하는 것을 막는 로직이 없습니다.

**수정:**

```sql
-- job_applications INSERT 정책 수정
CREATE POLICY "본인 지원 등록"
  ON job_applications FOR INSERT
  WITH CHECK (
    applicant_id = auth.uid()
    AND NOT EXISTS (
      SELECT 1 FROM jobs WHERE id = job_id AND poster_id = auth.uid()
    )
  );

-- 추가: DB 레벨 CHECK 제약 (이중 보호)
-- RPC 함수 내부에서 처리하는 것을 권장
```

---

### BUG-2. 우선 배차 지원 시 배차권 차감이 트랜잭션으로 묶이지 않음

**현상:** 원본 설계에서 `job_applications INSERT` → `priority_tickets UPDATE(used_at)` 가 별도 쿼리입니다. 중간에 실패하면 배차권만 차감되고 지원은 안 들어가거나, 지원은 들어갔는데 배차권은 안 차감됩니다.

**수정:** 반드시 하나의 Supabase RPC(DB Function)로 트랜잭션 처리해야 합니다.

```sql
CREATE OR REPLACE FUNCTION apply_with_priority(
  p_job_id uuid,
  p_applicant_id uuid,
  p_applicant_lat double precision,
  p_applicant_lng double precision
)
RETURNS jsonb AS $$
DECLARE
  v_ticket_id uuid;
  v_job record;
  v_profile record;
  v_score numeric;
  v_application_id uuid;
BEGIN
  -- 1. 본인 일감 지원 방지
  SELECT * INTO v_job FROM jobs WHERE id = p_job_id;
  IF v_job.poster_id = p_applicant_id THEN
    RAISE EXCEPTION 'Cannot apply to your own job';
  END IF;

  -- 2. 일감 상태 확인
  IF v_job.status NOT IN ('open', 'priority_window') THEN
    RAISE EXCEPTION 'Job is not available for application';
  END IF;

  -- 3. 중복 지원 방지
  IF EXISTS (
    SELECT 1 FROM job_applications
    WHERE job_id = p_job_id AND applicant_id = p_applicant_id
  ) THEN
    RAISE EXCEPTION 'Already applied to this job';
  END IF;

  -- 4. 유효한 배차권 1개 차감 (원자적: FOR UPDATE SKIP LOCKED)
  UPDATE priority_tickets
  SET used_at = now()
  WHERE id = (
    SELECT id FROM priority_tickets
    WHERE owner_id = p_applicant_id
      AND used_at IS NULL
      AND expires_at > now()
    ORDER BY expires_at ASC  -- 만료 임박한 것부터 사용
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING id INTO v_ticket_id;

  IF v_ticket_id IS NULL THEN
    RAISE EXCEPTION 'No valid priority ticket available';
  END IF;

  -- 5. 점수 계산
  SELECT * INTO v_profile FROM profiles WHERE id = p_applicant_id;
  v_score := calculate_match_score(
    v_profile.rating_sum,
    v_profile.rating_count,
    ST_MakePoint(p_applicant_lng, p_applicant_lat)::geography,
    v_job.location,
    100
  );

  -- 6. 지원 등록
  INSERT INTO job_applications (
    id, job_id, applicant_id, ticket_id,
    is_priority, applicant_location, score, status
  ) VALUES (
    gen_random_uuid(), p_job_id, p_applicant_id, v_ticket_id,
    true,
    ST_MakePoint(p_applicant_lng, p_applicant_lat)::geography,
    v_score,
    'pending'
  ) RETURNING id INTO v_application_id;

  RETURN jsonb_build_object(
    'application_id', v_application_id,
    'ticket_used', v_ticket_id,
    'score', v_score
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

Flutter 클라이언트에서는 이 RPC 하나만 호출합니다:

```dart
final result = await supabase.rpc('apply_with_priority', params: {
  'p_job_id': jobId,
  'p_applicant_id': currentUserId,
  'p_applicant_lat': currentLat,
  'p_applicant_lng': currentLng,
});
```

---

### BUG-3. 매칭 확정 시 race condition — 이중 매칭 가능

**현상:** `process-priority-match` Edge Function에서 `supabase.from('jobs').update(...)` 호출 시, 동시에 같은 일감을 처리하는 두 cron 호출이 있으면 두 번 매칭될 수 있습니다.

**수정:** 매칭 확정도 DB Function으로 원자적 처리합니다.

```sql
CREATE OR REPLACE FUNCTION finalize_priority_match(p_job_id uuid)
RETURNS jsonb AS $$
DECLARE
  v_job record;
  v_winner record;
BEGIN
  -- 비관적 락으로 일감 잠금
  SELECT * INTO v_job FROM jobs
  WHERE id = p_job_id AND status = 'priority_window'
  FOR UPDATE SKIP LOCKED;

  -- 이미 다른 프로세스가 처리했거나 락 실패
  IF v_job IS NULL THEN
    RETURN jsonb_build_object('status', 'already_processed');
  END IF;

  -- 최고 점수 지원자 조회
  SELECT * INTO v_winner FROM job_applications
  WHERE job_id = p_job_id AND is_priority = true AND status = 'pending'
  ORDER BY score DESC, created_at ASC  -- 동점 시 먼저 지원한 사람
  LIMIT 1;

  IF v_winner IS NULL THEN
    -- 우선 지원자 없음 → 일반 공개
    UPDATE jobs SET status = 'open', priority_window_ends_at = NULL
    WHERE id = p_job_id;
    RETURN jsonb_build_object('status', 'opened', 'job_id', p_job_id);
  END IF;

  -- 매칭 확정
  UPDATE jobs SET
    status = 'matched',
    matched_worker_id = v_winner.applicant_id,
    matched_at = now()
  WHERE id = p_job_id;

  -- 당첨자 accepted
  UPDATE job_applications SET status = 'accepted'
  WHERE id = v_winner.id;

  -- 나머지 rejected
  UPDATE job_applications SET status = 'rejected'
  WHERE job_id = p_job_id AND id != v_winner.id AND status = 'pending';

  RETURN jsonb_build_object(
    'status', 'matched',
    'job_id', p_job_id,
    'winner_id', v_winner.applicant_id,
    'poster_id', v_job.poster_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

Edge Function은 이제 로직 없이 RPC 호출만 합니다:

```typescript
// Edge Function: process-priority-match (단순화)
const { data: expiredJobs } = await supabase
  .from('jobs')
  .select('id')
  .eq('status', 'priority_window')
  .lte('priority_window_ends_at', new Date().toISOString());

for (const job of expiredJobs) {
  const { data: result } = await supabase.rpc('finalize_priority_match', {
    p_job_id: job.id,
  });

  // 알림 발송만 Edge Function에서 처리
  if (result.status === 'matched') {
    await sendFCM(result.winner_id, 'match_success', result.job_id);
    await sendFCM(result.poster_id, 'dispatch_complete', result.job_id);
  }
}
```

---

### BUG-4. 일반 공개(선착순) 매칭에 지원 로직이 없음

**현상:** 원본 설계에서 우선 배차 실패 후 `status = 'open'`으로 전환되지만, 일반 기사가 어떻게 지원하고 매칭이 확정되는지에 대한 DB 함수가 전혀 없습니다. 이대로 개발하면 일반 매칭이 동작하지 않습니다.

**수정:**

```sql
CREATE OR REPLACE FUNCTION apply_general(
  p_job_id uuid,
  p_applicant_id uuid,
  p_applicant_lat double precision,
  p_applicant_lng double precision
)
RETURNS jsonb AS $$
DECLARE
  v_job record;
BEGIN
  -- 비관적 락
  SELECT * INTO v_job FROM jobs
  WHERE id = p_job_id AND status = 'open'
  FOR UPDATE SKIP LOCKED;

  IF v_job IS NULL THEN
    RAISE EXCEPTION 'Job not available';
  END IF;

  IF v_job.poster_id = p_applicant_id THEN
    RAISE EXCEPTION 'Cannot apply to your own job';
  END IF;

  -- 선착순: 즉시 매칭 확정
  UPDATE jobs SET
    status = 'matched',
    matched_worker_id = p_applicant_id,
    matched_at = now()
  WHERE id = p_job_id;

  INSERT INTO job_applications (
    id, job_id, applicant_id,
    is_priority, applicant_location, status
  ) VALUES (
    gen_random_uuid(), p_job_id, p_applicant_id,
    false,
    ST_MakePoint(p_applicant_lng, p_applicant_lat)::geography,
    'accepted'
  );

  RETURN jsonb_build_object(
    'status', 'matched',
    'job_id', p_job_id,
    'poster_id', v_job.poster_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

---

### BUG-5. profiles RLS가 일감 목록 화면에서 등록자 이름 조회를 차단

**현상:** `profiles` RLS 정책이 "본인" 또는 "매칭 상대방"에게만 SELECT를 허용합니다. 하지만 일감 목록에서 `jobs.poster_id`로 등록자 이름을 표시하려면 다른 기사의 프로필을 읽어야 합니다. 현재 정책으로는 `403 Forbidden`이 발생합니다.

**수정:** 민감 정보(계좌번호)와 공개 정보(이름)를 분리합니다.

```sql
-- 기본 프로필은 모든 인증 사용자에게 공개 (이름, 장비 정보만)
CREATE POLICY "인증 사용자 기본 프로필 조회"
  ON profiles FOR SELECT
  USING (auth.role() = 'authenticated');

-- 단, 민감 정보는 뷰로 분리
CREATE VIEW public.profiles_public AS
SELECT id, name, equipment_track_type, equipment_size,
       rating_sum, rating_count
FROM profiles;

-- 매칭 상대방만 볼 수 있는 민감 정보 뷰
CREATE VIEW public.profiles_matched AS
SELECT p.id, p.name, p.phone, p.bank_account
FROM profiles p
WHERE p.id IN (
  SELECT matched_worker_id FROM jobs WHERE poster_id = auth.uid() AND status = 'matched'
  UNION
  SELECT poster_id FROM jobs WHERE matched_worker_id = auth.uid() AND status = 'matched'
);
```

또는 더 간결하게: RLS에서 `phone`과 `bank_account` 컬럼만 Column Level Security로 보호합니다. Supabase는 컬럼 단위 RLS를 직접 지원하지 않으므로, 위의 뷰 패턴이 가장 실용적입니다.

---

### BUG-6. `priority_tickets` 부분 인덱스의 `now()` 문제

**현상:** 원본의 인덱스 정의:

```sql
CREATE INDEX idx_tickets_owner_active
  ON priority_tickets(owner_id)
  WHERE used_at IS NULL AND expires_at > now();
```

`now()`는 인덱스 생성 시점의 값으로 고정됩니다. 시간이 지나도 인덱스 조건이 갱신되지 않아, 만료된 티켓도 인덱스에 계속 남아있습니다.

**수정:**

```sql
-- now() 제거 — 미사용 티켓만 인덱싱, 만료 체크는 쿼리에서 수행
CREATE INDEX idx_tickets_owner_unused
  ON priority_tickets(owner_id, expires_at)
  WHERE used_at IS NULL;

-- 쿼리 시:
SELECT * FROM priority_tickets
WHERE owner_id = $1 AND used_at IS NULL AND expires_at > now();
```

---

### BUG-7. jobs 테이블 UPDATE 정책 누락

**현상:** `jobs` 테이블에 INSERT 정책만 있고 UPDATE 정책이 없습니다. `process-priority-match`가 `status`, `matched_worker_id` 등을 업데이트해야 하는데, RLS에 의해 차단됩니다.

**수정:**

```sql
-- 일감 등록자 본인만 수정 가능 (취소 등)
CREATE POLICY "본인 일감 수정"
  ON jobs FOR UPDATE
  USING (poster_id = auth.uid())
  WITH CHECK (poster_id = auth.uid());

-- 서버 사이드 매칭 처리는 SECURITY DEFINER 함수가 RLS 우회하므로 별도 정책 불필요
-- 단, Edge Function이 service_role 키를 사용하는 경우에도 안전
```

중요: `finalize_priority_match`와 `apply_general` 함수는 `SECURITY DEFINER`로 선언되어 있어 RLS를 우회합니다. 따라서 매칭 관련 UPDATE는 함수 내부에서만 일어나야 하며, 클라이언트에서 직접 `jobs.update()`를 호출하면 안 됩니다.

---

## 🟡 설계 개선 권고 5건

### IMP-1. 장비 조건 매칭 검증 누락

**문제:** 지원 시 기사의 보유 장비가 일감의 요구 조건과 맞는지 검증하는 로직이 없습니다. 바퀴형 기사가 궤도형 일감에 지원 가능합니다.

**수정:** `apply_with_priority`와 `apply_general` 함수 내부에 추가:

```sql
-- 장비 조건 검증 (두 RPC 함수 모두에 추가)
IF v_job.required_track_type IS NOT NULL THEN
  IF v_profile.equipment_track_type != v_job.required_track_type THEN
    RAISE EXCEPTION 'Equipment track type mismatch';
  END IF;
END IF;

IF v_job.required_size IS NOT NULL THEN
  IF v_profile.equipment_size != v_job.required_size THEN
    RAISE EXCEPTION 'Equipment size mismatch';
  END IF;
END IF;
```

---

### IMP-2. 다중 기기 FCM 토큰 미지원

**문제:** `profiles.fcm_token`이 단일 `text`입니다. 기사가 휴대폰+태블릿을 사용하면 하나만 알림을 받습니다.

**수정:**

```sql
-- 별도 테이블로 분리
CREATE TABLE device_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid FK → profiles.id NOT NULL,
  token text NOT NULL,
  platform text CHECK ('ios', 'android'),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(user_id, token)
);
```

---

### IMP-3. 일감 등록 시 `status` 플로우 불명확

**문제:** 일감이 등록되면 즉시 `status = 'open'`이 되는데, 우선 배차 윈도우를 열려면 `priority_window`로 전환해야 합니다. 이 전환 시점이 트리거인지 Edge Function인지 모호합니다.

**수정:** 명확한 플로우 정의:

```sql
-- 일감 등록 시 status 결정 로직을 트리거에 통합
CREATE OR REPLACE FUNCTION on_job_created()
RETURNS TRIGGER AS $$
DECLARE
  v_has_priority_holders boolean;
BEGIN
  -- 1. 우선 배차권 발급
  INSERT INTO priority_tickets (id, owner_id, source_job_id, expires_at)
  VALUES (gen_random_uuid(), NEW.poster_id, NEW.id, now() + interval '30 days');

  -- 2. 조건 맞는 우선 배차권 보유자가 있는지 확인
  SELECT EXISTS (
    SELECT 1 FROM priority_tickets pt
    JOIN profiles p ON p.id = pt.owner_id
    WHERE pt.used_at IS NULL
      AND pt.expires_at > now()
      AND pt.owner_id != NEW.poster_id
      AND (NEW.required_track_type IS NULL OR p.equipment_track_type = NEW.required_track_type)
      AND (NEW.required_size IS NULL OR p.equipment_size = NEW.required_size)
  ) INTO v_has_priority_holders;

  -- 3. 우선 보유자가 있으면 priority_window, 없으면 바로 open
  IF v_has_priority_holders THEN
    NEW.status := 'priority_window';
    NEW.priority_window_ends_at := now() + interval '60 seconds';
  ELSE
    NEW.status := 'open';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- BEFORE INSERT 트리거로 변경 (NEW 값을 수정해야 하므로)
CREATE TRIGGER trg_on_job_created
  BEFORE INSERT ON jobs
  FOR EACH ROW EXECUTE FUNCTION on_job_created();
```

---

### IMP-4. score 컬럼 numeric(5,2) 범위 부족

**문제:** `score numeric(5,2)`는 최대 999.99까지 저장 가능하지만, 현재 점수 범위는 0.00~1.00입니다. 나중에 가중치를 변경하거나 보너스 점수를 추가하면 소수점 정밀도가 부족할 수 있습니다.

**수정:** `numeric(7,4)`로 변경하여 0.0000~999.9999 범위를 지원합니다.

---

### IMP-5. 만료된 일감 자동 정리 없음

**문제:** `work_date`가 지난 일감이 `status = 'open'`으로 남아있으면 계속 목록에 표시됩니다.

**수정:**

```sql
-- pg_cron: 매일 자정 실행 — 지난 일감 자동 마감
SELECT cron.schedule(
  'expire-old-jobs',
  '0 0 * * *',
  $$
    UPDATE jobs
    SET status = 'cancelled'
    WHERE status IN ('open', 'priority_window')
      AND work_date < now() - interval '1 hour';
  $$
);
```

추가로 클라이언트 쿼리에서도 `work_date > now()` 필터를 기본 적용합니다.

---

## 🟠 누락된 명세 보완 4건

### SPEC-1. 일반 매칭에서 "우선 배차 윈도우 중 일반 지원" 차단

우선 배차 윈도우(60초) 동안에는 우선 배차권이 없는 기사가 지원하지 못하도록 차단해야 합니다.

```dart
// Flutter: 지원 버튼 활성화 조건
bool canApply(Job job, bool hasPriorityTicket) {
  if (job.status == 'priority_window') {
    return hasPriorityTicket; // 우선권 보유자만
  }
  if (job.status == 'open') {
    return true; // 누구나
  }
  return false; // matched, cancelled
}
```

DB 레벨에서도 `apply_general` 함수가 `status = 'open'`만 허용하므로 이미 보호됩니다.

---

### SPEC-2. Supabase Realtime 구독 설계

일감 목록과 배차 상태는 실시간 반영이 필요합니다. 설계에 Realtime 구독이 누락되어 있습니다.

```dart
// 일감 목록 실시간 갱신
final jobsSubscription = supabase
  .from('jobs')
  .stream(primaryKey: ['id'])
  .inFilter('status', ['open', 'priority_window'])
  .listen((data) {
    ref.read(jobListProvider.notifier).refresh(data);
  });

// 내 배차 상태 변경 감지
final dispatchSubscription = supabase
  .from('jobs')
  .stream(primaryKey: ['id'])
  .eq('matched_worker_id', currentUserId)
  .listen((data) {
    // 매칭 완료 알림 UI 표시
  });
```

---

### SPEC-3. 탈락 시 배차권 반환 정책

우선 지원했지만 탈락한 기사의 배차권은 반환해야 하는지 명시되어 있지 않습니다. 사용자 경험상 **탈락 시 배차권 반환**이 합리적입니다.

```sql
-- finalize_priority_match 함수에 추가
-- 탈락자 배차권 반환
UPDATE priority_tickets
SET used_at = NULL
WHERE id IN (
  SELECT ticket_id FROM job_applications
  WHERE job_id = p_job_id
    AND status = 'rejected'
    AND ticket_id IS NOT NULL
);
```

---

### SPEC-4. 에러 코드 체계

RPC 함수에서 `RAISE EXCEPTION`으로 에러를 던지지만, 클라이언트에서 구분하기 어렵습니다. 에러 코드를 표준화합니다.

```sql
-- 에러 코드 규칙
RAISE EXCEPTION 'SELF_APPLY'
  USING HINT = 'Cannot apply to your own job';

RAISE EXCEPTION 'JOB_UNAVAILABLE'
  USING HINT = 'Job is not available for application';

RAISE EXCEPTION 'DUPLICATE_APPLICATION'
  USING HINT = 'Already applied to this job';

RAISE EXCEPTION 'NO_TICKET'
  USING HINT = 'No valid priority ticket available';

RAISE EXCEPTION 'EQUIPMENT_MISMATCH'
  USING HINT = 'Equipment type or size does not match';
```

```dart
// Flutter에서 에러 처리
try {
  await supabase.rpc('apply_with_priority', params: {...});
} on PostgrestException catch (e) {
  switch (e.message) {
    case 'SELF_APPLY':
      showSnackBar('본인이 등록한 일감에는 지원할 수 없습니다');
    case 'NO_TICKET':
      showSnackBar('유효한 우선 배차권이 없습니다');
    case 'EQUIPMENT_MISMATCH':
      showSnackBar('장비 조건이 맞지 않습니다');
    default:
      showSnackBar('지원 중 오류가 발생했습니다');
  }
}
```

---

## 수정 반영 체크리스트

개발 시작 전 아래 항목이 모두 반영되었는지 확인하세요.

| # | 항목 | 반영 |
|---|------|------|
| BUG-1 | 본인 일감 지원 차단 | ☐ |
| BUG-2 | 우선 지원을 단일 RPC 트랜잭션으로 | ☐ |
| BUG-3 | 매칭 확정을 FOR UPDATE SKIP LOCKED으로 | ☐ |
| BUG-4 | 일반 매칭 RPC 함수 추가 | ☐ |
| BUG-5 | 프로필 공개/민감 정보 분리 (뷰) | ☐ |
| BUG-6 | 부분 인덱스에서 now() 제거 | ☐ |
| BUG-7 | jobs UPDATE RLS 정책 추가 | ☐ |
| IMP-1 | 장비 조건 매칭 검증 | ☐ |
| IMP-2 | 다중 기기 FCM 토큰 테이블 | ☐ |
| IMP-3 | 일감 생성 시 status 자동 결정 트리거 | ☐ |
| IMP-4 | score 컬럼 numeric(7,4) | ☐ |
| IMP-5 | 만료 일감 자동 정리 cron | ☐ |
| SPEC-1 | 우선 윈도우 중 일반 지원 차단 | ☐ |
| SPEC-2 | Realtime 구독 설계 추가 | ☐ |
| SPEC-3 | 탈락 시 배차권 반환 | ☐ |
| SPEC-4 | 에러 코드 표준화 | ☐ |
