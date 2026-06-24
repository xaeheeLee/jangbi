# 포크레인 배차 매칭 앱 — 최종 개발 계획서 (v2.0)

> 본 문서는 원본 계획서 + 아키텍처 검토 결과를 통합한 최종본입니다.
> 모든 버그 수정, 설계 개선, 캘린더 기능이 반영되어 있습니다.

---

## 목차

1. [앱 개요 및 기술 스택](#1-앱-개요-및-기술-스택)
2. [Supabase DB 스키마](#2-supabase-db-스키마)
3. [Flutter 앱 화면 구조](#3-flutter-앱-화면-구조)
4. [핵심 비즈니스 로직](#4-핵심-비즈니스-로직)
5. [캘린더 기능 명세](#5-캘린더-기능-명세)
6. [FCM 푸시 알림 설계](#6-fcm-푸시-알림-설계)
7. [에러 처리 표준](#7-에러-처리-표준)
8. [개발 로드맵 및 마일스톤](#8-개발-로드맵-및-마일스톤)
9. [기술적 리스크 및 해결 방안](#9-기술적-리스크-및-해결-방안)
10. [추후 검토 기능 후보](#10-추후-검토-기능-후보)
11. [프로젝트 폴더 구조](#11-프로젝트-폴더-구조)

---

## 1. 앱 개요 및 기술 스택

### 1.1 앱 목적

포크레인 기사들 간 일감 등록 및 배차 매칭 플랫폼. 단일 유저 타입(포크레인 기사)이 일감 올리기와 배차받기를 모두 수행할 수 있습니다.

### 1.2 기술 스택

| 구분 | 기술 |
|------|------|
| Frontend | Flutter (iOS / Android) |
| 상태 관리 | Riverpod |
| Backend / DB | Supabase (PostgreSQL + PostGIS + Realtime + Auth + Storage) |
| 지도 | Google Maps Flutter Plugin + Geocoding API |
| 푸시 알림 | FCM + Supabase Edge Functions |
| 스케줄러 | pg_cron (Supabase 내장) |
| 결제 | 추후 구현 (현재 제외) |

---

## 2. Supabase DB 스키마

### 2.1 테이블 정의

#### `profiles` — 기사 프로필

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid PK, FK → auth.users | Supabase Auth UID |
| name | text NOT NULL | 이름 |
| phone | text UNIQUE NOT NULL | 전화번호 |
| bank_account | text | 계좌번호 (매칭 후 공개) |
| equipment_track_type | text CHECK ('wheel', 'track') | 바퀴형 / 궤도형 |
| equipment_size | text CHECK ('small', 'medium', 'large') | 소형 / 중형 / 대형 |
| rating_sum | int DEFAULT 0 | 별점 누적합 (추후) |
| rating_count | int DEFAULT 0 | 별점 횟수 (추후) |
| created_at | timestamptz DEFAULT now() | |

평균 별점은 `rating_sum / rating_count`로 계산합니다. 두 컬럼을 분리하면 atomic increment가 가능하고 race condition을 방지합니다.

#### `device_tokens` — FCM 디바이스 토큰 (다중 기기 지원)

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid PK DEFAULT gen_random_uuid() | |
| user_id | uuid FK → profiles.id NOT NULL | |
| token | text NOT NULL | FCM 토큰 |
| platform | text CHECK ('ios', 'android') | |
| updated_at | timestamptz DEFAULT now() | |
| UNIQUE(user_id, token) | | 중복 방지 |

#### `jobs` — 일감

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid PK DEFAULT gen_random_uuid() | |
| poster_id | uuid FK → profiles.id NOT NULL | 일 올린 기사 |
| work_date | timestamptz NOT NULL | 작업 일시 |
| region_name | text NOT NULL | 지역명 (일대) |
| location | geography(Point, 4326) NOT NULL | PostGIS 좌표 |
| address | text | 주소 텍스트 |
| description | text NOT NULL | 작업 정보 |
| required_track_type | text CHECK ('wheel', 'track') | 장비 조건 |
| required_size | text CHECK ('small', 'medium', 'large') | 크기 조건 |
| memo | text | 메모 |
| status | text DEFAULT 'open' CHECK ('open', 'priority_window', 'matched', 'completed', 'cancelled') | |
| priority_window_ends_at | timestamptz | 우선 배차 60초 마감 시각 |
| matched_worker_id | uuid FK → profiles.id | 최종 배차된 기사 |
| matched_at | timestamptz | 매칭 완료 시각 |
| created_at | timestamptz DEFAULT now() | |

#### `priority_tickets` — 우선 배차권

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid PK DEFAULT gen_random_uuid() | |
| owner_id | uuid FK → profiles.id NOT NULL | 보유 기사 |
| source_job_id | uuid FK → jobs.id NOT NULL | 발행 근거 일감 |
| expires_at | timestamptz NOT NULL | 생성 후 30일 |
| used_at | timestamptz | 사용 시각 (NULL = 미사용) |
| created_at | timestamptz DEFAULT now() | |

#### `job_applications` — 지원 (배차 신청)

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid PK DEFAULT gen_random_uuid() | |
| job_id | uuid FK → jobs.id NOT NULL | 지원한 일감 |
| applicant_id | uuid FK → profiles.id NOT NULL | 지원 기사 |
| ticket_id | uuid FK → priority_tickets.id | 사용한 우선 배차권 (일반 지원 시 NULL) |
| is_priority | boolean DEFAULT false | 우선 지원 여부 |
| applicant_location | geography(Point, 4326) | 지원 시점 기사 위치 |
| score | numeric(7,4) | 별점 70% + 거리 30% 점수 |
| status | text DEFAULT 'pending' CHECK ('pending', 'accepted', 'rejected') | |
| created_at | timestamptz DEFAULT now() | |
| UNIQUE(job_id, applicant_id) | | 중복 지원 방지 |

#### `notifications` — 알림 로그

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid PK DEFAULT gen_random_uuid() | |
| recipient_id | uuid FK → profiles.id NOT NULL | |
| type | text CHECK ('new_job', 'match_success', 'match_fail', 'priority_expired', 'schedule_conflict') | |
| title | text NOT NULL | |
| body | text | |
| data | jsonb | 딥링크 등 메타데이터 |
| read | boolean DEFAULT false | |
| created_at | timestamptz DEFAULT now() | |

### 2.2 뷰 — 프로필 공개/민감 정보 분리

```sql
-- 모든 인증 사용자가 조회 가능한 기본 정보
CREATE VIEW public.profiles_public AS
SELECT id, name, equipment_track_type, equipment_size,
       rating_sum, rating_count
FROM profiles;

-- 매칭 상대방만 볼 수 있는 민감 정보
CREATE OR REPLACE FUNCTION get_matched_contact(p_job_id uuid)
RETURNS TABLE(name text, phone text, bank_account text)
SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT p.name, p.phone, p.bank_account
  FROM profiles p
  JOIN jobs j ON j.id = p_job_id AND j.status = 'matched'
  WHERE (
    (j.poster_id = auth.uid() AND p.id = j.matched_worker_id)
    OR
    (j.matched_worker_id = auth.uid() AND p.id = j.poster_id)
  );
END;
$$ LANGUAGE plpgsql;
```

### 2.3 인덱스

```sql
-- 일감 탐색
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_location ON jobs USING GIST(location);
CREATE INDEX idx_jobs_work_date ON jobs(work_date);
CREATE INDEX idx_jobs_required ON jobs(required_track_type, required_size);
CREATE INDEX idx_jobs_poster ON jobs(poster_id);
CREATE INDEX idx_jobs_worker ON jobs(matched_worker_id);

-- 우선 배차권 (now() 사용하지 않음 — 쿼리에서 만료 체크)
CREATE INDEX idx_tickets_owner_unused
  ON priority_tickets(owner_id, expires_at)
  WHERE used_at IS NULL;

-- 지원 내역
CREATE INDEX idx_applications_job ON job_applications(job_id);
CREATE INDEX idx_applications_applicant ON job_applications(applicant_id);

-- 캘린더 조회 (기사별 배차 일정)
CREATE INDEX idx_jobs_worker_date ON jobs(matched_worker_id, work_date)
  WHERE status IN ('matched', 'completed');
CREATE INDEX idx_jobs_poster_date ON jobs(poster_id, work_date);

-- 알림
CREATE INDEX idx_notifications_recipient ON notifications(recipient_id, created_at DESC);

-- 디바이스 토큰
CREATE INDEX idx_device_tokens_user ON device_tokens(user_id);
```

### 2.4 RLS (Row Level Security) 정책

```sql
-- ■ profiles
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "인증 사용자 기본 프로필 조회"
  ON profiles FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "본인 프로필 수정"
  ON profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

CREATE POLICY "본인 프로필 생성"
  ON profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- ■ jobs
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "열린 일감 조회"
  ON jobs FOR SELECT
  USING (
    status IN ('open', 'priority_window')
    OR poster_id = auth.uid()
    OR matched_worker_id = auth.uid()
  );

CREATE POLICY "본인 일감 등록"
  ON jobs FOR INSERT
  WITH CHECK (poster_id = auth.uid());

CREATE POLICY "본인 일감 수정"
  ON jobs FOR UPDATE
  USING (poster_id = auth.uid())
  WITH CHECK (poster_id = auth.uid());

-- ■ priority_tickets
ALTER TABLE priority_tickets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "본인 배차권 조회"
  ON priority_tickets FOR SELECT
  USING (owner_id = auth.uid());

-- INSERT/UPDATE는 SECURITY DEFINER 함수에서만 수행

-- ■ job_applications
ALTER TABLE job_applications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "지원 관련자만 조회"
  ON job_applications FOR SELECT
  USING (
    applicant_id = auth.uid()
    OR job_id IN (SELECT id FROM jobs WHERE poster_id = auth.uid())
  );

-- INSERT는 SECURITY DEFINER RPC 함수에서만 수행

-- ■ notifications
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "본인 알림만 조회"
  ON notifications FOR SELECT
  USING (recipient_id = auth.uid());

CREATE POLICY "본인 알림 읽음 처리"
  ON notifications FOR UPDATE
  USING (recipient_id = auth.uid());

-- ■ device_tokens
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "본인 토큰 관리"
  ON device_tokens FOR ALL
  USING (user_id = auth.uid());
```

### 2.5 Database Functions

#### 2.5.1 점수 계산 함수

```sql
CREATE OR REPLACE FUNCTION calculate_match_score(
  p_rating_sum int,
  p_rating_count int,
  p_applicant_location geography,
  p_job_location geography,
  p_max_distance_km numeric DEFAULT 100
)
RETURNS numeric AS $$
DECLARE
  normalized_rating numeric;
  distance_km numeric;
  normalized_distance numeric;
BEGIN
  -- 별점 정규화 (0~1, 리뷰 없으면 0.5)
  IF p_rating_count = 0 THEN
    normalized_rating := 0.5;
  ELSE
    normalized_rating := (p_rating_sum::numeric / p_rating_count) / 5.0;
  END IF;

  -- 거리 정규화 (가까울수록 1에 가까움)
  distance_km := ST_Distance(p_applicant_location, p_job_location) / 1000.0;
  normalized_distance := GREATEST(0, 1.0 - (distance_km / p_max_distance_km));

  -- 가중치: 별점 70% + 거리 30%
  RETURN ROUND((normalized_rating * 0.7) + (normalized_distance * 0.3), 4);
END;
$$ LANGUAGE plpgsql IMMUTABLE;
```

#### 2.5.2 일감 생성 트리거 (상태 자동 결정 + 배차권 발급)

```sql
CREATE OR REPLACE FUNCTION on_job_created()
RETURNS TRIGGER AS $$
DECLARE
  v_has_priority_holders boolean;
BEGIN
  -- 1. 등록자에게 우선 배차권 1개 발급
  INSERT INTO priority_tickets (owner_id, source_job_id, expires_at)
  VALUES (NEW.poster_id, NEW.id, now() + interval '30 days');

  -- 2. 조건 맞는 우선 배차권 보유자 존재 여부 확인
  SELECT EXISTS (
    SELECT 1 FROM priority_tickets pt
    JOIN profiles p ON p.id = pt.owner_id
    WHERE pt.used_at IS NULL
      AND pt.expires_at > now()
      AND pt.owner_id != NEW.poster_id
      AND (NEW.required_track_type IS NULL
           OR p.equipment_track_type = NEW.required_track_type)
      AND (NEW.required_size IS NULL
           OR p.equipment_size = NEW.required_size)
  ) INTO v_has_priority_holders;

  -- 3. 상태 결정
  IF v_has_priority_holders THEN
    NEW.status := 'priority_window';
    NEW.priority_window_ends_at := now() + interval '60 seconds';
  ELSE
    NEW.status := 'open';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_on_job_created
  BEFORE INSERT ON jobs
  FOR EACH ROW EXECUTE FUNCTION on_job_created();
```

#### 2.5.3 우선 지원 RPC (트랜잭션 보장)

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

  -- 6. 배차권 차감 (원자적, 만료 임박순)
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

  -- 7. 점수 계산
  v_score := calculate_match_score(
    v_profile.rating_sum, v_profile.rating_count,
    v_applicant_geo, v_job.location, 100
  );

  -- 8. 지원 등록
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

#### 2.5.4 일반 지원 RPC (선착순 즉시 매칭)

```sql
CREATE OR REPLACE FUNCTION apply_general(
  p_job_id uuid,
  p_applicant_id uuid,
  p_applicant_lat double precision,
  p_applicant_lng double precision,
  p_force_apply boolean DEFAULT false
)
RETURNS jsonb AS $$
DECLARE
  v_job record;
  v_profile record;
  v_applicant_geo geography;
BEGIN
  v_applicant_geo := ST_MakePoint(p_applicant_lng, p_applicant_lat)::geography;

  -- 비관적 락
  SELECT * INTO v_job FROM jobs
  WHERE id = p_job_id AND status = 'open'
  FOR UPDATE SKIP LOCKED;

  IF v_job IS NULL THEN
    RAISE EXCEPTION 'JOB_UNAVAILABLE'
      USING HINT = 'Job is not available';
  END IF;

  IF v_job.poster_id = p_applicant_id THEN
    RAISE EXCEPTION 'SELF_APPLY'
      USING HINT = 'Cannot apply to your own job';
  END IF;

  -- 장비 조건 검증
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

  -- 일정 충돌 체크 (강제 적용이 아닐 때만)
  IF NOT p_force_apply AND EXISTS (
    SELECT 1 FROM jobs
    WHERE matched_worker_id = p_applicant_id
      AND status IN ('matched', 'completed')
      AND work_date::date = v_job.work_date::date
  ) THEN
    RAISE EXCEPTION 'SCHEDULE_CONFLICT'
      USING HINT = 'You already have a job on this date';
  END IF;

  -- 선착순 즉시 매칭
  UPDATE jobs SET
    status = 'matched',
    matched_worker_id = p_applicant_id,
    matched_at = now()
  WHERE id = p_job_id;

  INSERT INTO job_applications (
    job_id, applicant_id, is_priority,
    applicant_location, status
  ) VALUES (
    p_job_id, p_applicant_id, false,
    v_applicant_geo, 'accepted'
  );

  RETURN jsonb_build_object(
    'status', 'matched',
    'job_id', p_job_id,
    'poster_id', v_job.poster_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

#### 2.5.5 우선 배차 마감 처리 RPC (60초 후 자동 채택)

```sql
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
    -- 우선 지원자 없음 → 일반 공개
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

  -- 당첨자 accepted
  UPDATE job_applications SET status = 'accepted'
  WHERE id = v_winner.id;

  -- 나머지 rejected
  UPDATE job_applications SET status = 'rejected'
  WHERE job_id = p_job_id AND id != v_winner.id AND status = 'pending';

  -- 탈락자 배차권 반환
  UPDATE priority_tickets SET used_at = NULL
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

### 2.6 pg_cron 스케줄

```sql
-- 1) 매 분: 만료된 우선 배차 윈도우 처리
SELECT cron.schedule(
  'process-priority-windows',
  '* * * * *',
  $$
    SELECT net.http_post(
      url := 'https://<project>.supabase.co/functions/v1/process-priority-match',
      headers := '{"Authorization": "Bearer <service_role_key>"}'::jsonb
    );
  $$
);

-- 2) 매일 자정: 지난 일감 자동 마감
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

-- 3) 매일 오전 9시: 우선 배차권 만료 임박 알림
SELECT cron.schedule(
  'notify-expiring-tickets',
  '0 9 * * *',
  $$
    SELECT net.http_post(
      url := 'https://<project>.supabase.co/functions/v1/notify-expiring-tickets',
      headers := '{"Authorization": "Bearer <service_role_key>"}'::jsonb
    );
  $$
);
```

---

## 3. Flutter 앱 화면 구조

### 3.1 전체 라우팅 맵

```
앱 진입
├── /splash ─── 인증 상태 확인
├── /auth
│   ├── /phone-input ─── 전화번호 입력
│   ├── /otp-verify ─── OTP 인증
│   └── /profile-setup ─── 최초 프로필 등록
│
└── /main (BottomNavigationBar: 5탭)
    │
    ├── [탭1] /jobs ─── 일감 목록
    │   ├── /jobs/detail/:id ─── 일감 상세 + 지원 버튼
    │   └── /jobs/create ─── 일 등록 폼
    │
    ├── [탭2] /dispatch ─── 내 배차 내역
    │   ├── /dispatch/active ─── 진행 중 (매칭 대기/완료)
    │   └── /dispatch/detail/:id ─── 배차 상세 (상대방 정보 공개)
    │
    ├── [탭3] /calendar ─── 배차 캘린더
    │   └── /calendar/day/:date ─── 특정일 상세 일정
    │
    ├── [탭4] /tickets ─── 우선 배차권 관리
    │   └── 보유 현황 / 사용 이력 / 만료 임박 표시
    │
    └── [탭5] /my ─── 마이페이지
        ├── /my/profile-edit ─── 프로필 수정
        ├── /my/posted-jobs ─── 내가 올린 일감
        ├── /my/notifications ─── 알림 목록
        └── /my/settings ─── 설정 (알림 on/off, 로그아웃)
```

### 3.2 주요 화면별 구성

**일감 목록 (`/jobs`)**
- 상단: 필터 칩 (바퀴/궤도, 소형/중형/대형)
- 정렬 토글: 거리순 / 날짜순
- `ListView.builder` → `JobCard` 위젯
- 매칭 완료: 빨간 "배차완료" 배지 + `BackdropFilter` 블러
- FAB: 일 등록 화면

**일감 상세 (`/jobs/detail/:id`)**
- Google Maps 위젯 (핀)
- 작업 정보, 장비 조건, 메모
- 하단 CTA: "지원하기" / "우선 지원" (배차권 보유 시)
- 우선 배차 진행 중이면 카운트다운 타이머 표시
- 일정 충돌 시 경고 배너 표시

**일 등록 (`/jobs/create`)**
- Form: 날짜/시간 피커, 지역명 입력
- Google Maps: 핀 드래그 or 주소 검색
- 장비 조건 드롭다운
- 등록 완료 → "우선 배차권 +1" 토스트

**배차 상세 (`/dispatch/detail/:id`)**
- 매칭 상태 표시
- 매칭 완료 시: 상대방 이름, 전화번호, 계좌번호 카드
- 전화 걸기 버튼 (`url_launcher`)

**배차 캘린더 (`/calendar`)** — 섹션 5에서 상세 기술

### 3.3 상태 관리 (Riverpod)

```
authStateProvider          ← Supabase Auth 상태 스트림
profileProvider            ← 본인 프로필 (AsyncNotifier)
jobListProvider            ← 일감 목록 (필터/정렬/Realtime)
jobDetailProvider(id)      ← 개별 일감 상세 (Family)
myDispatchListProvider     ← 내 배차 내역
calendarEventsProvider     ← 캘린더 일정 (월별 로드)
scheduleConflictProvider   ← 일정 충돌 체크
ticketCountProvider        ← 유효한 우선 배차권 수
notificationListProvider   ← 알림 목록
locationProvider           ← Geolocator 현재 위치
```

### 3.4 Supabase Realtime 구독

```dart
// 일감 목록 실시간 갱신
supabase
  .from('jobs')
  .stream(primaryKey: ['id'])
  .inFilter('status', ['open', 'priority_window'])
  .listen((data) => ref.read(jobListProvider.notifier).refresh(data));

// 내 배차 상태 변경 감지
supabase
  .from('jobs')
  .stream(primaryKey: ['id'])
  .eq('matched_worker_id', currentUserId)
  .listen((data) {
    ref.read(myDispatchListProvider.notifier).refresh(data);
    ref.read(calendarEventsProvider.notifier).refresh(data);
  });
```

---

## 4. 핵심 비즈니스 로직

### 4.1 우선 배차권 60초 매칭 — 전체 플로우

```
1. 기사 A가 일감 등록
   → BEFORE INSERT 트리거 실행
   → 우선 배차권 1개 발급
   → 우선권 보유자 존재 시: status='priority_window', 60초 타이머 설정
   → 미존재 시: status='open'
   → DB Webhook → Edge Function "send-notification" 호출

2. 조건 맞는 우선 배차권 보유 기사들에게 FCM 푸시 발송

3. 우선 배차권 보유 기사가 "우선 지원" 클릭
   → Flutter: supabase.rpc('apply_with_priority', params: {...})
   → 트랜잭션 내에서: 배차권 차감 + 점수 계산 + 지원 등록

4. 60초 후 pg_cron → Edge Function "process-priority-match" 호출
   → 만료된 윈도우 조회
   → supabase.rpc('finalize_priority_match', {p_job_id: ...})
   → 결과: matched(최고점 채택) or opened(일반 공개 전환)
   → FCM 알림 발송 (매칭 성공/실패)
   → 탈락자 배차권 자동 반환

5. 일반 공개 전환 시
   → 배차권 없는 기사 포함 모두에게 알림
   → 선착순 지원: supabase.rpc('apply_general', params: {...})
   → FOR UPDATE SKIP LOCKED으로 동시 매칭 방지
```

### 4.2 점수 계산 예시

| 기사 | 평균 별점 | 거리 | 별점 점수 (×0.7) | 거리 점수 (×0.3) | 총점 |
|------|-----------|------|-------------------|-------------------|------|
| A | 4.5/5 | 10km | 0.6300 | 0.2700 | **0.9000** |
| B | 5.0/5 | 50km | 0.7000 | 0.1500 | 0.8500 |
| C | 3.0/5 | 5km | 0.4200 | 0.2850 | 0.7050 |
| D | 신규 (없음) | 20km | 0.3500 | 0.2400 | 0.5900 |

→ 기사 A 채택. 신규 기사(D)는 기본 0.5 별점을 부여하여 불이익 최소화.

### 4.3 Edge Function: process-priority-match

```typescript
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

Deno.serve(async () => {
  const { data: expiredJobs } = await supabase
    .from('jobs')
    .select('id')
    .eq('status', 'priority_window')
    .lte('priority_window_ends_at', new Date().toISOString());

  const results = [];

  for (const job of expiredJobs ?? []) {
    const { data: result } = await supabase.rpc('finalize_priority_match', {
      p_job_id: job.id,
    });

    if (result?.status === 'matched') {
      await sendFCM(result.winner_id, {
        type: 'match_success', title: '배차 확정!',
        body: '우선 배차에 선정되었습니다', job_id: result.job_id,
      });
      await sendFCM(result.poster_id, {
        type: 'match_success', title: '배차 완료!',
        body: '기사가 배정되었습니다', job_id: result.job_id,
      });
    } else if (result?.status === 'opened') {
      await notifyOpenJob(result.job_id);
    }

    results.push(result);
  }

  return new Response(JSON.stringify({ processed: results.length, results }));
});
```

---

## 5. 캘린더 기능 명세

### 5.1 기능 범위

| 기능 | 포함 |
|------|------|
| 내 배차 일정 월간 달력 표시 | ✅ |
| 일별 상세 일정 조회 | ✅ |
| 일정 충돌 경고 (지원 시) | ✅ |
| 일 등록 시 본인 일정 충돌 표시 | ✅ |

### 5.2 화면 설계

**월간 캘린더 (`/calendar`)**

```
┌─────────────────────────────────┐
│  ◀  2026년 4월  ▶              │
├──┬──┬──┬──┬──┬──┬──┤
│일│월│화│수│목│금│토│
├──┼──┼──┼──┼──┼──┼──┤
│  │  │ 1│ 2│ 3│ 4│ 5│
│  │  │  │🔵│  │🟠│  │
├──┼──┼──┼──┼──┼──┼──┤
│ 6│ 7│ 8│ 9│10│11│12│
│  │🔵│  │  │🔵│  │  │
│  │  │  │  │🟠│  │  │
...
```

- 🔵 파란 점: 배차받은 일정 (내가 일하러 가는 날)
- 🟠 주황 점: 내가 올린 일감 (배차 완료된 것)
- 점이 2개 이상인 날: 충돌 경고 아이콘(⚠️) 표시
- 날짜 탭 → 하단 시트로 해당일 일정 목록

**일별 상세 (하단 시트)**

```
┌─────────────────────────────────┐
│ 4월 10일 (목) — 일정 2건  ⚠️   │
├─────────────────────────────────┤
│ 🔵 09:00  강남구 역삼동          │
│    궤도형 대형 · 토목 작업       │
│    [상세 보기]                   │
├─────────────────────────────────┤
│ 🟠 14:00  서초구 반포동          │
│    바퀴형 중형 · 조경 작업       │
│    배차 완료 · 김기사님          │
│    [상세 보기]                   │
├─────────────────────────────────┤
│ ⚠️ 같은 날 2건의 작업이 있습니다 │
│    시간이 겹치지 않는지 확인하세요 │
└─────────────────────────────────┘
```

### 5.3 일정 충돌 경고 로직

**충돌 정의:** 같은 날짜에 2건 이상의 배차(matched) 일정이 있는 경우.

**적용 시점:**

1. **캘린더 화면:** 해당 날짜에 ⚠️ 경고 아이콘
2. **일감 지원 시:** `apply_general` RPC 내부에서 충돌 체크 → `SCHEDULE_CONFLICT` 에러 → 확인 다이얼로그 → "그래도 진행" 시 `p_force_apply: true`로 재호출
3. **일 등록 화면:** 본인이 이미 배차받은 날에 일감을 등록하면 안내 배너

### 5.4 캘린더 데이터 쿼리

```dart
Future<Map<DateTime, List<CalendarEvent>>> loadMonthEvents(
  String userId, DateTime month
) async {
  final startOfMonth = DateTime(month.year, month.month, 1);
  final endOfMonth = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

  final { data } = await supabase
    .from('jobs')
    .select('id, work_date, region_name, description, status, '
            'poster_id, matched_worker_id, required_track_type, required_size')
    .or('matched_worker_id.eq.$userId,poster_id.eq.$userId')
    .inFilter('status', ['matched', 'completed'])
    .gte('work_date', startOfMonth.toIso8601String())
    .lte('work_date', endOfMonth.toIso8601String())
    .order('work_date');

  return groupByDate(data, userId);
}
```

---

## 6. FCM 푸시 알림 설계

### 6.1 알림 유형

| 이벤트 | 트리거 | 대상 | 우선순위 |
|--------|--------|------|----------|
| 새 일감 등록 | jobs INSERT webhook | 조건 맞는 기사 (우선권 보유자 먼저) | High |
| 매칭 성공 | finalize / apply_general 결과 | 채택 기사 + 일 등록 기사 | High |
| 매칭 실패 (탈락) | finalize 결과 | 탈락 기사들 | Normal |
| 일반 공개 전환 | finalize 결과 | 조건 맞는 모든 기사 | Normal |
| 일정 충돌 경고 | 매칭 확정 시 | 해당 기사 | Normal |
| 배차권 만료 임박 | pg_cron (일 1회) | 3일 내 만료 기사 | Low |

### 6.2 FCM 토큰 관리

```dart
Future<void> initFCM() async {
  await Firebase.initializeApp();

  final token = await FirebaseMessaging.instance.getToken();
  if (token != null) await _upsertToken(token);

  FirebaseMessaging.instance.onTokenRefresh.listen(_upsertToken);
  FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
}

Future<void> _upsertToken(String token) async {
  await supabase.from('device_tokens').upsert({
    'user_id': currentUserId,
    'token': token,
    'platform': Platform.isIOS ? 'ios' : 'android',
    'updated_at': DateTime.now().toIso8601String(),
  }, onConflict: 'user_id,token');
}
```

### 6.3 Edge Function: send-notification

```typescript
async function sendFCM(userId: string, payload: NotificationPayload) {
  const { data: tokens } = await supabase
    .from('device_tokens').select('token').eq('user_id', userId);

  await supabase.from('notifications').insert({
    recipient_id: userId,
    type: payload.type, title: payload.title,
    body: payload.body, data: { job_id: payload.job_id },
  });

  for (const { token } of tokens ?? []) {
    try {
      await fetch(
        `https://fcm.googleapis.com/v1/projects/${PROJECT_ID}/messages:send`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token,
              notification: { title: payload.title, body: payload.body },
              data: { type: payload.type, job_id: payload.job_id },
              android: { priority: 'high' },
              apns: { payload: { aps: { sound: 'default' } } },
            },
          }),
        }
      );
    } catch (e) {
      if (isTokenInvalid(e)) {
        await supabase.from('device_tokens').delete().eq('token', token);
      }
    }
  }
}
```

---

## 7. 에러 처리 표준

### 7.1 에러 코드 체계

| 에러 코드 | 의미 | 사용자 메시지 |
|-----------|------|---------------|
| SELF_APPLY | 본인 일감 지원 | "본인이 등록한 일감에는 지원할 수 없습니다" |
| JOB_UNAVAILABLE | 일감 상태 불일치 | "이미 마감된 일감입니다" |
| JOB_NOT_FOUND | 일감 미존재 | "일감을 찾을 수 없습니다" |
| DUPLICATE_APPLICATION | 중복 지원 | "이미 지원한 일감입니다" |
| NO_TICKET | 유효 배차권 없음 | "사용 가능한 우선 배차권이 없습니다" |
| EQUIPMENT_MISMATCH | 장비 조건 불일치 | "보유 장비가 요구 조건과 맞지 않습니다" |
| SCHEDULE_CONFLICT | 일정 충돌 | "해당 날짜에 이미 배차된 일정이 있습니다" |

### 7.2 Flutter 에러 핸들링

```dart
Future<void> applyToJob(String jobId, bool isPriority) async {
  try {
    final rpcName = isPriority ? 'apply_with_priority' : 'apply_general';
    await supabase.rpc(rpcName, params: {
      'p_job_id': jobId,
      'p_applicant_id': currentUserId,
      'p_applicant_lat': currentLat,
      'p_applicant_lng': currentLng,
    });
    showSuccess('지원이 완료되었습니다!');
  } on PostgrestException catch (e) {
    switch (e.message) {
      case 'SCHEDULE_CONFLICT':
        final proceed = await showConflictDialog();
        if (proceed) {
          await supabase.rpc('apply_general', params: {
            ...sameParams, 'p_force_apply': true,
          });
        }
      case 'SELF_APPLY':
        showError('본인이 등록한 일감에는 지원할 수 없습니다');
      case 'NO_TICKET':
        showError('사용 가능한 우선 배차권이 없습니다');
      case 'EQUIPMENT_MISMATCH':
        showError('보유 장비가 요구 조건과 맞지 않습니다');
      case 'DUPLICATE_APPLICATION':
        showError('이미 지원한 일감입니다');
      default:
        showError('지원 중 오류가 발생했습니다');
    }
  }
}
```

---

## 8. 개발 로드맵 및 마일스톤

### 8.1 전체 일정 개요

| Phase | 기간 | 핵심 산출물 | 마일스톤 |
|-------|------|-------------|----------|
| Phase 1 | 2주 (1~2주차) | 인증 + 프로필 + 앱 골격 | M1 |
| Phase 2 | 2주 (3~4주차) | 일감 CRUD + 지도 | M2 |
| Phase 3 | 3주 (5~7주차) | 매칭 엔진 (우선/일반) | M3 |
| Phase 4 | 1주 (8주차) | 푸시 알림 | M4 |
| Phase 5 | 2주 (9~10주차) | 캘린더 + 일정 충돌 | M5 |
| Phase 6 | 2주 (11~12주차) | 폴리싱 + QA + 배포 준비 | M6 |
| **총 기간** | **약 12주** | | |

### 8.2 Phase별 상세 마일스톤

#### Phase 1 — 기반 구축 (1~2주차)

**목표:** 사용자가 앱에 가입하고 프로필을 설정할 수 있다.

| 태스크 | 세부 내용 | 완료 기준 |
|--------|-----------|-----------|
| 1-1 | Supabase 프로젝트 생성, PostGIS 활성화 | DB 접속 확인 |
| 1-2 | Flutter 프로젝트 초기화 (go_router, riverpod, supabase_flutter) | 앱 빌드 성공 |
| 1-3 | profiles, device_tokens 테이블 + RLS 배포 | 마이그레이션 적용 |
| 1-4 | 전화번호 인증 회원가입 플로우 | OTP 발송 → 인증 → 로그인 |
| 1-5 | 프로필 등록/수정 화면 | 장비 정보 저장 확인 |
| 1-6 | BottomNavigationBar 5탭 골격 | 탭 전환 동작 |
| 1-7 | 마이페이지 기본 화면 | 프로필 조회/수정/로그아웃 |

**✅ 마일스톤 M1:** 회원가입 → 로그인 → 프로필 설정 → 탭 전환 동작

---

#### Phase 2 — 일감 CRUD (3~4주차)

**목표:** 사용자가 일감을 등록하고 목록에서 조회할 수 있다.

| 태스크 | 세부 내용 | 완료 기준 |
|--------|-----------|-----------|
| 2-1 | jobs, priority_tickets 테이블 + 인덱스 + RLS 배포 | 마이그레이션 적용 |
| 2-2 | on_job_created 트리거 배포 | 배차권 자동 발급 + 상태 자동 결정 |
| 2-3 | 일 등록 화면 (Google Maps 핀 + Geocoding) | 좌표/주소 저장 확인 |
| 2-4 | 일감 목록 화면 (필터/정렬) | 장비 필터, 거리순/날짜순 |
| 2-5 | 일감 상세 화면 (지도 핀 + 정보) | 상세 정보 표시 |
| 2-6 | 매칭 완료 블러 처리 UI | 빨간 배지 + 블러 |
| 2-7 | 우선 배차권 관리 화면 | 배차권 목록 표시 |
| 2-8 | profiles_public 뷰 + get_matched_contact RPC 배포 | 프로필 정보 분리 동작 |

**✅ 마일스톤 M2:** 일감 등록 → 목록 조회 → 상세 확인 → 배차권 +1 확인

---

#### Phase 3 — 매칭 엔진 (5~7주차)

**목표:** 우선 배차 / 일반 배차 매칭이 정상 동작한다.

| 태스크 | 세부 내용 | 완료 기준 |
|--------|-----------|-----------|
| 3-1 | job_applications 테이블 + 인덱스 + RLS 배포 | 마이그레이션 적용 |
| 3-2 | calculate_match_score 함수 배포 | 점수 계산 정확성 검증 |
| 3-3 | apply_with_priority RPC 배포 + 테스트 | 트랜잭션 원자성 검증 |
| 3-4 | apply_general RPC 배포 + 테스트 | 선착순 + 장비 검증 + 일정 충돌 체크 |
| 3-5 | finalize_priority_match RPC 배포 | FOR UPDATE SKIP LOCKED 검증 |
| 3-6 | Edge Function: process-priority-match 배포 | 60초 후 자동 채택 |
| 3-7 | pg_cron 설정 (process-priority-windows, expire-old-jobs) | 스케줄 실행 확인 |
| 3-8 | 지원 UI (우선/일반 분기 + 카운트다운 타이머) | 버튼 상태 분기 |
| 3-9 | 배차 상세 화면 (상대방 정보 공개) | get_matched_contact 동작 |
| 3-10 | Realtime 구독 (일감 목록 + 배차 상태) | 실시간 반영 |
| 3-11 | 동시 지원 테스트 (Race condition) | 이중 매칭 없음 확인 |
| 3-12 | 탈락자 배차권 반환 검증 | 반환 후 재사용 가능 |

**✅ 마일스톤 M3:** 우선 지원 60초 → 자동 채택 → 상대방 정보 열람 + 일반 선착순 매칭

---

#### Phase 4 — 푸시 알림 (8주차)

**목표:** 일감 등록/매칭 이벤트에 대해 푸시 알림을 수신한다.

| 태스크 | 세부 내용 | 완료 기준 |
|--------|-----------|-----------|
| 4-1 | Firebase 프로젝트 연동 (iOS APN, Android FCM) | 테스트 푸시 수신 |
| 4-2 | FCM 토큰 등록/갱신 로직 | device_tokens 반영 |
| 4-3 | Edge Function: send-notification 배포 | FCM 전송 성공 |
| 4-4 | DB Webhook: jobs INSERT → send-notification | 일감 등록 시 알림 |
| 4-5 | 매칭 성공/실패 알림 연동 | process-priority-match 내 알림 |
| 4-6 | notifications 테이블 + RLS 배포 | 알림 로그 저장 |
| 4-7 | 알림 목록 화면 + 읽음 처리 | 인앱 알림 표시 |
| 4-8 | 알림 탭 → 딥링크 | 포그라운드/백그라운드 동작 |

**✅ 마일스톤 M4:** 일감 등록 → 조건 기사 푸시 수신 → 탭하여 상세 이동

---

#### Phase 5 — 캘린더 + 일정 충돌 (9~10주차)

**목표:** 기사가 본인 배차 일정을 달력으로 관리하고, 충돌 시 경고를 받는다.

| 태스크 | 세부 내용 | 완료 기준 |
|--------|-----------|-----------|
| 5-1 | 캘린더 월간 화면 (table_calendar 패키지) | 월 전환 + 일정 도트 |
| 5-2 | calendarEventsProvider 구현 | 월별 데이터 로드 |
| 5-3 | 날짜별 도트 마커 (배차받음 🔵 / 올림 🟠) | 구분 표시 |
| 5-4 | 일별 상세 바텀시트 | 일정 목록 + 상세 이동 |
| 5-5 | 일정 충돌 경고 아이콘 (달력 UI) | ⚠️ 표시 |
| 5-6 | 충돌 확인 다이얼로그 + force 재호출 | SCHEDULE_CONFLICT 처리 |
| 5-7 | 일감 상세 화면에 충돌 경고 배너 | 기존 일정 표시 |
| 5-8 | Realtime으로 캘린더 자동 갱신 | 매칭 완료 시 즉시 반영 |

**✅ 마일스톤 M5:** 캘린더 배차 일정 표시 + 충돌 경고 + 강제 지원 동작

---

#### Phase 6 — 폴리싱 + QA + 배포 준비 (11~12주차)

**목표:** 프로덕션 배포 가능 수준의 품질 확보.

| 태스크 | 세부 내용 | 완료 기준 |
|--------|-----------|-----------|
| 6-1 | 에러 핸들링 전수 검토 | 모든 RPC try-catch + 메시지 |
| 6-2 | 로딩/빈 화면/에러 상태 UI | Shimmer + 빈 상태 |
| 6-3 | Edge case 테스트 | 동시 지원, 네트워크 끊김, 토큰 만료 |
| 6-4 | iOS TestFlight / Android 내부 테스트 | 실기기 설치 |
| 6-5 | 성능 최적화 | 프로파일링 완료 |
| 6-6 | 앱 아이콘, 스플래시, 앱 이름 | 브랜딩 적용 |
| 6-7 | 스토어 메타데이터 | 스크린샷, 설명문 |
| 6-8 | 개인정보 처리방침, 이용약관 | 법률 문서 |

**✅ 마일스톤 M6:** 스토어 심사 제출 준비 완료

---

## 9. 기술적 리스크 및 해결 방안

### 9.1 60초 타이머 정확도

- **리스크:** pg_cron은 최소 1분 단위. 60초 윈도우가 60~119초가 될 수 있음.
- **해결:** `priority_window_ends_at`에 정확한 timestamp 저장, `WHERE <= now()` 필터. 초기 수용 가능, 사용량 증가 시 Edge Function 서버 사이드 타이머로 교체.

### 9.2 동시 지원 Race Condition

- **리스크:** 여러 기사 동시 지원 시 이중 매칭 또는 배차권 이중 차감.
- **해결:** 모든 핵심 로직을 SECURITY DEFINER RPC 함수에 통합. `FOR UPDATE SKIP LOCKED` 비관적 락. `UNIQUE(job_id, applicant_id)` 제약.

### 9.3 PostGIS 거리 계산 성능

- **리스크:** 사용자 증가 시 공간 쿼리 부하.
- **해결:** GIST 인덱스. 수만 건 이상 시 `ST_DWithin` 반경 제한 후 정렬.

### 9.4 FCM 토큰 관리

- **리스크:** 토큰 만료, 앱 삭제, 기기 변경.
- **해결:** 앱 시작 시 갱신, `onTokenRefresh` 리스너, 전송 실패 시 토큰 삭제, 인앱 notifications 테이블로 보완.

### 9.5 Supabase 전화번호 인증

- **리스크:** Twilio 연동 필요, SMS 비용.
- **해결:** 개발 시 test OTP 활용. 프로덕션에서 국내 SMS API(알리고, NHN Cloud) Auth Hook 연동 또는 카카오 소셜 인증.

### 9.6 일반 공개 선착순의 공정성

- **리스크:** 네트워크 속도 의존.
- **해결:** 초기 선착순, 피드백에 따라 5~10초 수집 윈도우 + 거리 기반 매칭 조정.

### 9.7 Edge Function Cold Start

- **리스크:** ~1초 콜드 스타트로 알림 지연.
- **해결:** pg_cron이 매분 호출하므로 warm 유지. 알림은 약간의 지연 허용.

### 9.8 캘린더 데이터 볼륨

- **리스크:** 오래된 일정 누적으로 쿼리 성능 저하.
- **해결:** `idx_jobs_worker_date` 복합 인덱스. 월 단위 페이지네이션.

---

## 10. 추후 검토 기능 후보

고객과 검토 후 우선순위를 결정할 기능 목록입니다.

### 10.1 수익화 / 비즈니스 모델

| 기능 | 설명 | 예상 복잡도 |
|------|------|-------------|
| 우선 배차권 월 정액제 | 월 구독으로 배차권 무제한/N개 지급 (인앱 결제 or PG) | 높음 |
| 프리미엄 일감 노출 | 추가 비용 지불 시 목록 상단 고정 | 중간 |

### 10.2 작업 관리

| 기능 | 설명 | 예상 복잡도 |
|------|------|-------------|
| 작업 완료 인증 | GPS+사진 기반 작업 완료 확인, 분쟁 방지용 증빙 | 높음 |
| 반복 일감 등록 | 정기 작업을 주간/월간 반복 등록 (건설현장 장기계약) | 중간 |
| 작업 일보/리포트 | 하루 작업 내역 기록, 정산 근거 제공 | 중간 |
| 작업 시간 기록 | 출발/도착/완료 시간 자동 기록 (GPS 기반) | 중간 |

### 10.3 신뢰 / 커뮤니티

| 기능 | 설명 | 예상 복잡도 |
|------|------|-------------|
| 기사 별점 시스템 | 작업 완료 후 상호 평가 (DB 필드 준비됨) | 중간 |
| 블랙리스트 / 차단 | 특정 기사와 매칭 제외 (상호 차단) | 낮음 |
| 기사 간 채팅 | 매칭 후 Supabase Realtime 기반 1:1 채팅 | 높음 |
| 기사 포트폴리오 | 작업 사진, 자격증, 경력 표시 | 중간 |
| 추천인 보상 | 신규 기사 추천 시 배차권 보너스 | 낮음 |

### 10.4 정보 / 편의

| 기능 | 설명 | 예상 복잡도 |
|------|------|-------------|
| 날씨 연동 | 작업일 기상예보 표시, 우천 시 자동 알림 | 낮음 |
| 캘린더 히트맵 | 지역별 일감 밀집도를 달력/지도에 표시 | 중간 |
| 정산 관리 | 월별 작업 내역 + 금액 정리 (엑셀 내보내기) | 중간 |
| 즐겨찾기 기사 | 자주 함께 일하는 기사 즐겨찾기 + 우선 매칭 | 낮음 |
| 공지사항 / FAQ | 앱 내 운영 공지, 자주 묻는 질문 | 낮음 |
| 다국어 지원 | 외국인 기사 대상 (베트남어, 중국어 등) | 중간 |
| 내비게이션 연동 | 일감 상세에서 카카오맵/네이버맵/T맵 바로 열기 | 낮음 |
| 유가 정보 | 주변 주유소 경유 가격 표시 (장비 운행 비용 참고) | 낮음 |

### 10.5 기능 우선순위 검토 기준 (고객 논의 시 참고)

- **사용자 획득:** 새 기사를 데려올 수 있는 기능인가?
- **리텐션:** 기존 기사가 계속 쓰게 만드는 기능인가?
- **수익화:** 과금 포인트가 되는 기능인가?
- **신뢰/안전:** 분쟁/리스크를 줄이는 기능인가?
- **ROI:** 구현 대비 임팩트가 큰가?

---

## 11. 프로젝트 폴더 구조

```
lib/
├── main.dart
├── app/
│   ├── router.dart              # GoRouter 설정
│   └── theme.dart               # 앱 테마
├── core/
│   ├── supabase_client.dart     # Supabase 초기화
│   ├── fcm_service.dart         # FCM 초기화 + 토큰 관리
│   ├── constants.dart
│   ├── error_handler.dart       # 에러 코드 매핑
│   └── extensions.dart
├── features/
│   ├── auth/
│   │   ├── presentation/        # phone_input, otp_verify, profile_setup
│   │   ├── providers/
│   │   └── data/
│   ├── jobs/
│   │   ├── presentation/
│   │   │   ├── job_list_screen.dart
│   │   │   ├── job_detail_screen.dart
│   │   │   ├── job_create_screen.dart
│   │   │   └── widgets/         # JobCard, FilterChips, CountdownTimer
│   │   ├── providers/
│   │   ├── data/
│   │   └── domain/              # Job 모델
│   ├── dispatch/
│   │   ├── presentation/        # dispatch_list, dispatch_detail
│   │   ├── providers/
│   │   └── data/
│   ├── calendar/
│   │   ├── presentation/
│   │   │   ├── calendar_screen.dart
│   │   │   ├── day_detail_sheet.dart
│   │   │   └── widgets/         # ConflictBanner, EventDot
│   │   ├── providers/           # calendarEventsProvider, scheduleConflictProvider
│   │   └── data/
│   ├── tickets/
│   │   ├── presentation/
│   │   └── providers/
│   ├── notifications/
│   │   ├── presentation/
│   │   └── providers/
│   └── profile/
│       ├── presentation/        # profile_edit, posted_jobs, settings
│       └── providers/
├── shared/
│   ├── widgets/                 # LoadingShimmer, EmptyState, ErrorView
│   └── models/                  # 공통 모델

supabase/
├── migrations/
│   ├── 001_profiles.sql
│   ├── 002_device_tokens.sql
│   ├── 003_jobs.sql
│   ├── 004_priority_tickets.sql
│   ├── 005_job_applications.sql
│   ├── 006_notifications.sql
│   ├── 007_views.sql
│   ├── 008_functions.sql
│   ├── 009_triggers.sql
│   ├── 010_indexes.sql
│   ├── 011_rls.sql
│   └── 012_cron.sql
├── functions/
│   ├── process-priority-match/
│   ├── send-notification/
│   ├── notify-expiring-tickets/
│   └── _shared/                 # 공통 유틸
└── config.toml
```
