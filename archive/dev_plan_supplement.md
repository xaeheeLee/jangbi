# 포크레인 배차 매칭 앱 — 개발 계획서 v2.0 보완 문서

> 본 문서는 v2.0 계획서 검토 결과 발견된 추가 수정/개선 사항을 정리한 패치 모음입니다.
> 우선순위(P0/P1/P2)에 따라 단계적으로 적용하세요.

---

## 목차

1. [P0 — 운영 전 필수 수정](#p0--운영-전-필수-수정)
   - [P0-1. `apply_with_priority`에 일정 충돌 체크 추가](#p0-1-apply_with_priority에-일정-충돌-체크-추가)
   - [P0-2. 탈락자 배차권 반환 시 만료일 연장](#p0-2-탈락자-배차권-반환-시-만료일-연장)
   - [P0-3. matched → completed 자동 전환 cron](#p0-3-matched--completed-자동-전환-cron)
2. [P1 — 권장 개선](#p1--권장-개선)
   - [P1-1. 일감 취소/수정 정책](#p1-1-일감-취소수정-정책)
   - [P1-2. 시간대 기반 충돌 체크](#p1-2-시간대-기반-충돌-체크)
   - [P1-3. 지원 이력 RLS 정책 보강](#p1-3-지원-이력-rls-정책-보강)
3. [P2 — 향후 개선](#p2--향후-개선)
   - [P2-1. 전화번호 변경 RPC](#p2-1-전화번호-변경-rpc)
   - [P2-2. 알림 페이지네이션 및 자동 정리](#p2-2-알림-페이지네이션-및-자동-정리)
4. [락 순서 원칙 (개발 가이드)](#락-순서-원칙-개발-가이드)
5. [Flutter 측 변경사항 요약](#flutter-측-변경사항-요약)
6. [마이그레이션 적용 체크리스트](#마이그레이션-적용-체크리스트)

---

## P0 — 운영 전 필수 수정

이 3개 항목은 출시 전 반드시 적용해야 운영 안정성을 확보할 수 있습니다.

### P0-1. `apply_with_priority`에 일정 충돌 체크 추가

**문제:**
`apply_general`에는 같은 날 일정 충돌 시 `SCHEDULE_CONFLICT` 에러를 던지는데, `apply_with_priority`에는 없습니다. 우선 지원이 더 중요한 경로(배차권을 차감하는 행위)이므로 일관성을 위해 동일하게 적용해야 합니다.

**파일:** `supabase/migrations/013_p0_patches.sql`

```sql
-- ═══════════════════════════════════════════════════════
-- P0-1: apply_with_priority에 SCHEDULE_CONFLICT 체크 추가
-- ═══════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION apply_with_priority(
  p_job_id uuid,
  p_applicant_id uuid,
  p_applicant_lat double precision,
  p_applicant_lng double precision,
  p_force_apply boolean DEFAULT false  -- 추가: 충돌 무시하고 진행 플래그
)
RETURNS jsonb AS $$
DECLARE
  v_ticket_id uuid;
  v_job record;
  v_profile record;
  v_score numeric;
  v_application_id uuid;
  v_applicant_geo geography;
BEGIN
  v_applicant_geo := ST_MakePoint(p_applicant_lng, p_applicant_lat)::geography;

  -- 1. 일감 조회 + 락
  SELECT * INTO v_job FROM jobs
  WHERE id = p_job_id FOR UPDATE;

  IF v_job IS NULL THEN
    RAISE EXCEPTION 'JOB_NOT_FOUND'
      USING HINT = 'Job does not exist';
  END IF;

  -- 2. 본인 일감 지원 차단
  IF v_job.poster_id = p_applicant_id THEN
    RAISE EXCEPTION 'SELF_APPLY'
      USING HINT = 'Cannot apply to your own job';
  END IF;

  -- 3. 상태 확인
  IF v_job.status != 'priority_window' THEN
    RAISE EXCEPTION 'JOB_UNAVAILABLE'
      USING HINT = 'Job is not in priority window';
  END IF;

  -- 4. 중복 지원 방지
  IF EXISTS (
    SELECT 1 FROM job_applications
    WHERE job_id = p_job_id AND applicant_id = p_applicant_id
  ) THEN
    RAISE EXCEPTION 'DUPLICATE_APPLICATION'
      USING HINT = 'Already applied to this job';
  END IF;

  -- 5. 프로필 조회 + 장비 조건 검증
  SELECT * INTO v_profile FROM profiles WHERE id = p_applicant_id;

  IF v_job.required_track_type IS NOT NULL
     AND v_profile.equipment_track_type != v_job.required_track_type THEN
    RAISE EXCEPTION 'EQUIPMENT_MISMATCH'
      USING HINT = 'Equipment track type does not match';
  END IF;

  IF v_job.required_size IS NOT NULL
     AND v_profile.equipment_size != v_job.required_size THEN
    RAISE EXCEPTION 'EQUIPMENT_MISMATCH'
      USING HINT = 'Equipment size does not match';
  END IF;

  -- ※ 6. [신규] 일정 충돌 체크 (force가 아닐 때)
  IF NOT p_force_apply AND EXISTS (
    SELECT 1 FROM jobs
    WHERE matched_worker_id = p_applicant_id
      AND status IN ('matched', 'completed')
      AND work_date::date = v_job.work_date::date
  ) THEN
    RAISE EXCEPTION 'SCHEDULE_CONFLICT'
      USING HINT = 'You already have a job on this date';
  END IF;

  -- 7. 배차권 차감 (원자적, 만료 임박순)
  UPDATE priority_tickets
  SET used_at = now()
  WHERE id = (
    SELECT id FROM priority_tickets
    WHERE owner_id = p_applicant_id
      AND used_at IS NULL
      AND expires_at > now()
    ORDER BY expires_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING id INTO v_ticket_id;

  IF v_ticket_id IS NULL THEN
    RAISE EXCEPTION 'NO_TICKET'
      USING HINT = 'No valid priority ticket available';
  END IF;

  -- 8. 점수 계산
  v_score := calculate_match_score(
    v_profile.rating_sum, v_profile.rating_count,
    v_applicant_geo, v_job.location, 100
  );

  -- 9. 지원 등록
  INSERT INTO job_applications (
    job_id, applicant_id, ticket_id,
    is_priority, applicant_location, score, status
  ) VALUES (
    p_job_id, p_applicant_id, v_ticket_id,
    true, v_applicant_geo, v_score, 'pending'
  ) RETURNING id INTO v_application_id;

  RETURN jsonb_build_object(
    'application_id', v_application_id,
    'ticket_used', v_ticket_id,
    'score', v_score
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

**Flutter 측 변경:**

```dart
// 우선 지원 시에도 충돌 다이얼로그 처리
case 'SCHEDULE_CONFLICT':
  final proceed = await showConflictDialog(
    title: '일정 충돌 경고',
    body: '해당 날짜에 이미 배차된 일정이 있습니다.\n그래도 우선 지원하시겠습니까?\n(배차권 1개가 차감됩니다)',
  );
  if (proceed) {
    await supabase.rpc('apply_with_priority', params: {
      ...sameParams, 'p_force_apply': true,
    });
  }
```

---

### P0-2. 탈락자 배차권 반환 시 만료일 연장

**문제:**
`finalize_priority_match`에서 탈락자의 `used_at = NULL`로 복구할 때, `expires_at`은 그대로입니다. 만료 임박이었던 배차권은 반환되어도 곧 만료되므로 **사실상 무용지물**이 됩니다. 사용자 입장에서는 "지원했다가 떨어졌더니 배차권이 거의 만료된 상태로 돌아왔다"는 불공정 경험이 됩니다.

**해결:**
탈락자 배차권 반환 시 `expires_at`을 최소 7일 이상 보장.

```sql
-- ═══════════════════════════════════════════════════════
-- P0-2: finalize_priority_match — 탈락자 배차권 만료일 연장
-- ═══════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION finalize_priority_match(p_job_id uuid)
RETURNS jsonb AS $$
DECLARE
  v_job record;
  v_winner record;
BEGIN
  -- 비관적 락으로 이중 처리 방지
  SELECT * INTO v_job FROM jobs
  WHERE id = p_job_id AND status = 'priority_window'
  FOR UPDATE SKIP LOCKED;

  IF v_job IS NULL THEN
    RETURN jsonb_build_object('status', 'already_processed');
  END IF;

  -- 최고 점수 지원자 (동점 시 먼저 지원한 사람 우선)
  SELECT * INTO v_winner FROM job_applications
  WHERE job_id = p_job_id AND is_priority = true AND status = 'pending'
  ORDER BY score DESC, created_at ASC
  LIMIT 1;

  IF v_winner IS NULL THEN
    UPDATE jobs
    SET status = 'open', priority_window_ends_at = NULL
    WHERE id = p_job_id;
    RETURN jsonb_build_object('status', 'opened', 'job_id', p_job_id);
  END IF;

  -- 매칭 확정
  UPDATE jobs SET
    status = 'matched',
    matched_worker_id = v_winner.applicant_id,
    matched_at = now()
  WHERE id = p_job_id;

  UPDATE job_applications SET status = 'accepted'
  WHERE id = v_winner.id;

  UPDATE job_applications SET status = 'rejected'
  WHERE job_id = p_job_id AND id != v_winner.id AND status = 'pending';

  -- ※ [수정] 탈락자 배차권 반환 + 만료일 최소 7일 보장
  UPDATE priority_tickets
  SET used_at = NULL,
      expires_at = GREATEST(expires_at, now() + interval '7 days')
  WHERE id IN (
    SELECT ticket_id FROM job_applications
    WHERE job_id = p_job_id AND status = 'rejected' AND ticket_id IS NOT NULL
  );

  RETURN jsonb_build_object(
    'status', 'matched',
    'job_id', p_job_id,
    'winner_id', v_winner.applicant_id,
    'poster_id', v_job.poster_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

**효과:**
- 사용자 신뢰 확보: "떨어져도 배차권은 살아 있다"
- 추가 7일 보장으로 다른 일감에 재사용 가능

---

### P0-3. matched → completed 자동 전환 cron

**문제:**
현재 `expire-old-jobs` cron은 `open`, `priority_window` 상태만 처리합니다. **매칭된 일감은 영원히 `matched` 상태로 남아 있습니다.** 이는:
- 별점 시스템 추후 도입 시 평가 대상 식별 불가
- 정산/통계 쿼리 복잡화
- 캘린더에서 과거 일감과 진행 중 일감 구분 어려움

**해결:**
작업일 기준 24시간 경과 시 `matched` → `completed` 자동 전환.

```sql
-- ═══════════════════════════════════════════════════════
-- P0-3: matched → completed 자동 전환 cron
-- ═══════════════════════════════════════════════════════
SELECT cron.schedule(
  'auto-complete-jobs',
  '0 1 * * *',  -- 매일 새벽 1시
  $$
    UPDATE jobs
    SET status = 'completed'
    WHERE status = 'matched'
      AND work_date < now() - interval '24 hours';
  $$
);
```

**고려사항:**
- 24시간을 작업 종료 후 충분한 기록 시간으로 가정
- 별점 시스템 도입 시 `completed` 상태에서만 평가 가능하도록 설정
- 분쟁/취소 처리는 `completed` 전환 전에 해결되어야 함 (별도 정책 필요)

---

## P1 — 권장 개선

운영 시작 전후로 적용 권장. 사용자 경험과 데이터 정합성 향상.

### P1-1. 일감 취소/수정 정책

**문제:**
현재 계획서에는 등록 후 일감 라이프사이클 전체가 정의되어 있지 않습니다. 다음 시나리오 모두 처리 누락:
- 등록자가 매칭 전 일감 취소 → 배차권 회수 여부?
- 등록자가 매칭 후 일감 시간 변경 → 매칭된 기사 재동의 필요?
- 매칭된 기사 펑크(no-show) → 페널티?

**해결:**

#### 1) `jobs.status` 확장

```sql
-- 기존 status enum 확장
ALTER TABLE jobs DROP CONSTRAINT IF EXISTS jobs_status_check;

ALTER TABLE jobs ADD CONSTRAINT jobs_status_check CHECK (
  status IN (
    'open',                  -- 일반 공개
    'priority_window',       -- 우선 배차 60초
    'matched',               -- 매칭 완료
    'completed',             -- 작업 완료 (자동 전환)
    'cancelled_by_poster',   -- 등록자 취소
    'cancelled_by_worker',   -- 매칭된 기사 취소
    'expired'                -- 시간 경과 자동 마감
  )
);
```

#### 2) 일감 취소 RPC

```sql
CREATE OR REPLACE FUNCTION cancel_job(
  p_job_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
  v_job record;
BEGIN
  SELECT * INTO v_job FROM jobs
  WHERE id = p_job_id FOR UPDATE;

  IF v_job IS NULL THEN
    RAISE EXCEPTION 'JOB_NOT_FOUND';
  END IF;

  -- 등록자만 취소 가능
  IF v_job.poster_id != auth.uid() THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED'
      USING HINT = 'Only poster can cancel';
  END IF;

  -- 이미 종료된 상태면 차단
  IF v_job.status IN ('completed', 'cancelled_by_poster',
                      'cancelled_by_worker', 'expired') THEN
    RAISE EXCEPTION 'JOB_UNAVAILABLE'
      USING HINT = 'Job already finalized';
  END IF;

  -- 매칭 전 취소: 배차권 회수
  IF v_job.status IN ('open', 'priority_window') THEN
    -- 등록 시 발급됐던 배차권 회수
    UPDATE priority_tickets
    SET expires_at = now()  -- 즉시 만료시켜 사용 불가 처리
    WHERE source_job_id = p_job_id AND used_at IS NULL;

    -- 우선 지원자들의 배차권 반환
    UPDATE priority_tickets
    SET used_at = NULL,
        expires_at = GREATEST(expires_at, now() + interval '7 days')
    WHERE id IN (
      SELECT ticket_id FROM job_applications
      WHERE job_id = p_job_id AND ticket_id IS NOT NULL
    );

    UPDATE job_applications
    SET status = 'rejected'
    WHERE job_id = p_job_id AND status = 'pending';
  END IF;

  -- 매칭 후 취소: 알림 발송 (배차권 회수 없음)
  -- 매칭된 기사에게 알림이 필요 → Edge Function에서 처리

  UPDATE jobs
  SET status = 'cancelled_by_poster'
  WHERE id = p_job_id;

  RETURN jsonb_build_object(
    'status', 'cancelled',
    'job_id', p_job_id,
    'previous_status', v_job.status,
    'matched_worker_id', v_job.matched_worker_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

#### 3) 일감 시간 변경 정책

매칭 후 시간 변경은 **금지**. 시간을 바꾸려면 일감을 취소하고 재등록.
대신 `memo` 필드 수정만 허용:

```sql
CREATE POLICY "본인 일감 메모 수정"
  ON jobs FOR UPDATE
  USING (poster_id = auth.uid())
  WITH CHECK (
    poster_id = auth.uid()
    -- work_date, location 등 핵심 필드 변경 차단은 트리거로 처리
  );

-- 핵심 필드 변경 차단 트리거
CREATE OR REPLACE FUNCTION prevent_critical_field_change()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status IN ('matched', 'completed') THEN
    IF NEW.work_date != OLD.work_date OR
       NEW.location::text != OLD.location::text OR
       NEW.required_track_type != OLD.required_track_type OR
       NEW.required_size != OLD.required_size THEN
      RAISE EXCEPTION 'CANNOT_MODIFY_MATCHED_JOB'
        USING HINT = 'Critical fields cannot be changed after matching';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_critical_change
  BEFORE UPDATE ON jobs
  FOR EACH ROW EXECUTE FUNCTION prevent_critical_field_change();
```

#### 4) 노쇼/펑크 처리 (별점 시스템과 연계)

별점 시스템 도입 시 `cancelled_by_worker` 또는 노쇼 신고 → 1점 자동 부여 등 정책 별도 수립.
**현재 단계에서는 상태값만 정의해두고, 운영 정책은 별점 시스템 도입 시 확정.**

---

### P1-2. 시간대 기반 충돌 체크

**문제:**
현재 충돌 체크는 `work_date::date` 기준으로 같은 날만 비교합니다. 그러나 같은 날 09:00 작업과 14:00 작업은 충돌이 아닙니다. 사용자가 합리적으로 두 건 다 수행 가능한 경우에도 차단되어 매칭 기회를 놓칩니다.

**해결:**
작업 종료 시간 컬럼 추가 또는 기본 작업 시간 가정.

#### 옵션 A: 작업 종료 시간 컬럼 추가 (권장)

```sql
-- ═══════════════════════════════════════════════════════
-- P1-2: 작업 종료 시간 컬럼 추가
-- ═══════════════════════════════════════════════════════
ALTER TABLE jobs
ADD COLUMN work_end_date timestamptz;

-- 등록 시 종료 시간 미입력 시 기본 4시간 가정
ALTER TABLE jobs
ALTER COLUMN work_end_date SET DEFAULT NULL;

-- 기존 데이터 보정 (4시간 가정)
UPDATE jobs
SET work_end_date = work_date + interval '4 hours'
WHERE work_end_date IS NULL;
```

#### 옵션 B: 등록 화면에서 작업 시간 입력 받기

Flutter `/jobs/create` 화면에 "예상 작업 시간" 드롭다운 추가:
- 2시간 / 4시간 / 8시간 (전일) / 직접 입력

#### 충돌 체크 로직 수정

```sql
-- apply_general 및 apply_with_priority 내부 충돌 체크 변경
IF NOT p_force_apply AND EXISTS (
  SELECT 1 FROM jobs
  WHERE matched_worker_id = p_applicant_id
    AND status IN ('matched', 'completed')
    AND tstzrange(work_date,
                  COALESCE(work_end_date, work_date + interval '4 hours'))
        && tstzrange(v_job.work_date,
                     COALESCE(v_job.work_end_date,
                              v_job.work_date + interval '4 hours'))
) THEN
  RAISE EXCEPTION 'SCHEDULE_CONFLICT'
    USING HINT = 'Time overlap with existing schedule';
END IF;
```

PostgreSQL의 `tstzrange` 타입과 `&&` 연산자(겹침 체크)를 사용하여 정확한 시간대 겹침을 검사합니다.

#### 캘린더 충돌 표시 로직도 동일하게 변경

```dart
// CalendarScreen
bool hasTimeConflict(List<CalendarEvent> events) {
  for (int i = 0; i < events.length; i++) {
    for (int j = i + 1; j < events.length; j++) {
      final a = events[i];
      final b = events[j];
      final aEnd = a.workEndDate ?? a.workDate.add(Duration(hours: 4));
      final bEnd = b.workEndDate ?? b.workDate.add(Duration(hours: 4));
      if (a.workDate.isBefore(bEnd) && b.workDate.isBefore(aEnd)) {
        return true;
      }
    }
  }
  return false;
}
```

---

### P1-3. 지원 이력 RLS 정책 보강

**문제:**
현재 `jobs` SELECT 정책으로는 본인이 과거 지원했지만 다른 기사가 매칭된 일감은 조회할 수 없습니다. "내 지원 내역" 화면을 만들 수 없습니다.

**해결:**

```sql
-- ═══════════════════════════════════════════════════════
-- P1-3: 지원 이력으로 jobs 조회 허용
-- ═══════════════════════════════════════════════════════
DROP POLICY IF EXISTS "열린 일감 조회" ON jobs;

CREATE POLICY "열린 일감 또는 관련 일감 조회"
  ON jobs FOR SELECT
  USING (
    status IN ('open', 'priority_window')
    OR poster_id = auth.uid()
    OR matched_worker_id = auth.uid()
    OR id IN (
      SELECT job_id FROM job_applications
      WHERE applicant_id = auth.uid()
    )
  );
```

**활용:**
- "내 지원 내역" 화면 구현 가능
- 탈락한 일감도 이력으로 조회 가능 (사용자가 어떤 일감에 떨어졌는지 확인)

**Flutter 측:**

```dart
// /my/applications 화면 추가
final myApplicationsProvider = FutureProvider<List<Job>>((ref) async {
  final apps = await supabase
    .from('job_applications')
    .select('job_id, status, created_at, jobs(*)')
    .eq('applicant_id', currentUserId)
    .order('created_at', ascending: false);
  return apps.map((a) => Job.fromJson(a['jobs'])).toList();
});
```

---

## P2 — 향후 개선

운영 시작 후 사용자 피드백에 따라 적용. 지금 당장 필요하지는 않음.

### P2-1. 전화번호 변경 RPC

**문제:**
`profiles.phone`은 `UNIQUE NOT NULL`이라 사용자가 번호를 변경하면 인증 절차 없이 직접 UPDATE할 수 없습니다. 또한 SMS 인증을 카카오 로그인으로 대체하는 경우 `phone`이 NULL일 수 없는 제약과 충돌합니다.

**해결:**

```sql
-- ═══════════════════════════════════════════════════════
-- P2-1: 전화번호 변경 RPC (OTP 재인증 후)
-- ═══════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION change_phone_number(
  p_user_id uuid,
  p_new_phone text,
  p_otp_verified boolean
)
RETURNS jsonb AS $$
BEGIN
  IF NOT p_otp_verified THEN
    RAISE EXCEPTION 'OTP_NOT_VERIFIED'
      USING HINT = 'OTP verification required';
  END IF;

  -- 본인만 변경 가능
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  -- 중복 검사
  IF EXISTS (
    SELECT 1 FROM profiles
    WHERE phone = p_new_phone AND id != p_user_id
  ) THEN
    RAISE EXCEPTION 'PHONE_ALREADY_EXISTS'
      USING HINT = 'This phone number is already in use';
  END IF;

  UPDATE profiles
  SET phone = p_new_phone
  WHERE id = p_user_id;

  RETURN jsonb_build_object('status', 'changed', 'new_phone', p_new_phone);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

**Flutter 흐름:**
1. 마이페이지 → 전화번호 변경 클릭
2. 새 번호 입력 → OTP 발송
3. OTP 인증 성공 → `change_phone_number(p_otp_verified: true)` 호출

---

### P2-2. 알림 페이지네이션 및 자동 정리

**문제:**
`notifications` 테이블이 누적되면 모바일 클라이언트가 모두 로드 시 성능 저하. 30일 이상 지난 읽은 알림은 가치가 낮아 정리 필요.

**해결:**

```sql
-- ═══════════════════════════════════════════════════════
-- P2-2: 오래된 알림 자동 정리 cron
-- ═══════════════════════════════════════════════════════
SELECT cron.schedule(
  'cleanup-old-notifications',
  '0 3 * * 0',  -- 매주 일요일 새벽 3시
  $$
    DELETE FROM notifications
    WHERE read = true
      AND created_at < now() - interval '30 days';

    DELETE FROM notifications
    WHERE read = false
      AND created_at < now() - interval '90 days';
  $$
);
```

**Flutter 측 페이지네이션:**

```dart
class NotificationListNotifier extends StateNotifier<NotificationState> {
  static const PAGE_SIZE = 30;

  Future<void> loadPage(int offset) async {
    final data = await supabase
      .from('notifications')
      .select()
      .eq('recipient_id', currentUserId)
      .order('created_at', ascending: false)
      .range(offset, offset + PAGE_SIZE - 1);

    state = state.copyWith(
      items: [...state.items, ...data.map(Notification.fromJson)],
      hasMore: data.length == PAGE_SIZE,
      offset: offset + data.length,
    );
  }
}
```

---

## 락 순서 원칙 (개발 가이드)

향후 추가 RPC 작성 시 데드락 방지를 위해 락 순서를 통일합니다.

### 표준 락 순서

```
1. jobs (FOR UPDATE / FOR UPDATE SKIP LOCKED)
2. priority_tickets (FOR UPDATE SKIP LOCKED)
3. job_applications (UPDATE/INSERT)
4. profiles (SELECT, 락 없음)
5. notifications (INSERT, 락 없음)
```

### 위반 예시 (잘못된 순서)

```sql
-- ❌ 잘못된 순서: tickets 먼저, jobs 나중
SELECT * FROM priority_tickets WHERE ... FOR UPDATE;
SELECT * FROM jobs WHERE ... FOR UPDATE;
```

### 올바른 예시

```sql
-- ✅ jobs 먼저
SELECT * FROM jobs WHERE id = p_job_id FOR UPDATE;
-- 그 다음 tickets
UPDATE priority_tickets SET ... WHERE ...;
```

### 코드 리뷰 체크리스트

- [ ] 모든 `FOR UPDATE` 락이 `jobs → priority_tickets → job_applications` 순서인가?
- [ ] 한 트랜잭션에서 같은 테이블에 락을 두 번 걸지 않는가?
- [ ] 외부 호출 (HTTP, FCM)이 락 보유 중에 일어나지 않는가?

---

## Flutter 측 변경사항 요약

본 보완 문서 적용 시 Flutter 코드에 반영해야 할 내용입니다.

### 1. P0-1: 우선 지원에도 충돌 다이얼로그

`features/jobs/presentation/widgets/apply_button.dart`:

```dart
Future<void> applyWithPriority(String jobId, {bool force = false}) async {
  try {
    await supabase.rpc('apply_with_priority', params: {
      'p_job_id': jobId,
      'p_applicant_id': currentUserId,
      'p_applicant_lat': currentLat,
      'p_applicant_lng': currentLng,
      'p_force_apply': force,
    });
    showSuccess('우선 지원이 완료되었습니다!');
  } on PostgrestException catch (e) {
    if (e.message == 'SCHEDULE_CONFLICT' && !force) {
      final proceed = await showConflictDialog(
        title: '일정 충돌 경고',
        body: '해당 날짜에 이미 배차된 일정이 있습니다.\n'
              '그래도 우선 지원하시겠습니까?\n'
              '(배차권 1개가 차감됩니다)',
      );
      if (proceed) await applyWithPriority(jobId, force: true);
    } else {
      handleError(e);
    }
  }
}
```

### 2. P1-1: 일감 취소 화면

`/jobs/detail/:id`에서 본인 등록 일감일 때만 "취소하기" 버튼 표시:

```dart
if (job.posterId == currentUserId &&
    !['completed', 'cancelled_by_poster',
      'cancelled_by_worker', 'expired'].contains(job.status))
  ElevatedButton(
    onPressed: () async {
      final confirm = await showCancelDialog();
      if (confirm) {
        await supabase.rpc('cancel_job', params: {
          'p_job_id': job.id,
        });
        ref.invalidate(jobListProvider);
        Navigator.pop(context);
      }
    },
    child: Text('일감 취소'),
  ),
```

### 3. P1-2: 작업 시간 입력 필드

`/jobs/create` 화면에 작업 시간 드롭다운 추가:

```dart
DropdownButton<Duration>(
  value: selectedDuration,
  items: [
    DropdownMenuItem(value: Duration(hours: 2), child: Text('약 2시간')),
    DropdownMenuItem(value: Duration(hours: 4), child: Text('약 4시간 (반일)')),
    DropdownMenuItem(value: Duration(hours: 8), child: Text('약 8시간 (전일)')),
  ],
  onChanged: (v) => setState(() => selectedDuration = v),
),
```

등록 시:

```dart
await supabase.from('jobs').insert({
  ...,
  'work_date': workDate.toIso8601String(),
  'work_end_date': workDate.add(selectedDuration).toIso8601String(),
});
```

### 4. P1-3: 내 지원 내역 화면

`/my/applications` 신규 라우트 추가. 마이페이지 메뉴에 진입점 추가.

### 5. P2-1: 전화번호 변경 화면

`/my/profile-edit/phone-change` 추가. OTP 재인증 → `change_phone_number` 호출 흐름.

### 6. P2-2: 알림 무한 스크롤

`/my/notifications` 화면을 `ListView.builder` + `ScrollController` 기반 페이지네이션으로 변경.

---

## 마이그레이션 적용 체크리스트

### P0 적용 (출시 전 필수)

- [ ] `013_p0_patches.sql` 작성 (P0-1, P0-2 포함)
- [ ] `014_auto_complete_cron.sql` 작성 (P0-3)
- [ ] 로컬 환경에서 마이그레이션 적용 및 테스트
  - [ ] 우선 지원 충돌 시나리오 검증
  - [ ] 탈락자 배차권 만료일 확인
  - [ ] cron 실행 로그 확인 (`SELECT * FROM cron.job_run_details`)
- [ ] Flutter 측 `p_force_apply` 파라미터 추가
- [ ] 우선 지원 충돌 다이얼로그 UI 추가
- [ ] 스테이징 환경 배포 및 회귀 테스트
- [ ] 프로덕션 배포

### P1 적용 (출시 직후)

- [ ] `015_job_lifecycle.sql` 작성 (P1-1)
  - [ ] status enum 확장
  - [ ] cancel_job RPC
  - [ ] 핵심 필드 변경 차단 트리거
- [ ] `016_time_overlap_check.sql` 작성 (P1-2)
  - [ ] work_end_date 컬럼 추가
  - [ ] 기존 데이터 보정
  - [ ] apply_general / apply_with_priority 충돌 로직 변경
- [ ] `017_application_rls.sql` 작성 (P1-3)
  - [ ] jobs SELECT 정책 보강
- [ ] Flutter 변경사항 반영
  - [ ] 일감 취소 UI
  - [ ] 작업 시간 입력 드롭다운
  - [ ] 내 지원 내역 화면

### P2 적용 (운영 안정 후)

- [ ] `018_phone_change.sql` 작성 (P2-1)
- [ ] `019_notification_cleanup.sql` 작성 (P2-2)
- [ ] Flutter 측 변경사항 반영
  - [ ] 전화번호 변경 흐름
  - [ ] 알림 페이지네이션

---

## 변경 이력

| 버전 | 날짜 | 내용 |
|------|------|------|
| v2.0 | 2026.04 | 최초 통합 계획서 (원본 + 검토 통합) |
| v2.0 보완 | 2026.05 | 추가 검토 결과 P0/P1/P2 패치 정리 |
