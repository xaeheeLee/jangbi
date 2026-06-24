# 포크레인 배차 매칭 앱 — 상세 개발 계획서

---

## 1. Supabase DB 스키마

### 1.1 테이블 정의

#### `profiles` — 기사 프로필

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid (PK, FK → auth.users) | Supabase Auth UID |
| name | text NOT NULL | 이름 |
| phone | text UNIQUE NOT NULL | 전화번호 |
| bank_account | text | 계좌번호 (매칭 후 공개) |
| equipment_track_type | text CHECK ('wheel', 'track') | 바퀴형 / 궤도형 |
| equipment_size | text CHECK ('small', 'medium', 'large') | 소형 / 중형 / 대형 |
| rating_sum | int DEFAULT 0 | 별점 누적합 (추후) |
| rating_count | int DEFAULT 0 | 별점 횟수 (추후) |
| fcm_token | text | FCM 디바이스 토큰 |
| created_at | timestamptz DEFAULT now() | |

평균 별점은 `rating_sum / rating_count`로 계산합니다. 두 컬럼을 분리하면 atomic increment가 가능하고 race condition을 방지할 수 있습니다.

#### `jobs` — 일감

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid (PK, DEFAULT gen_random_uuid()) | |
| poster_id | uuid FK → profiles.id | 일 올린 기사 |
| work_date | timestamptz NOT NULL | 작업 일시 |
| region_name | text NOT NULL | 지역명 (일대) |
| location | geography(Point, 4326) NOT NULL | PostGIS 좌표 |
| address | text | 주소 텍스트 |
| description | text NOT NULL | 작업 정보 |
| required_track_type | text CHECK ('wheel', 'track') | 장비 조건 |
| required_size | text CHECK ('small', 'medium', 'large') | 크기 조건 |
| memo | text | 메모 |
| status | text DEFAULT 'open' CHECK ('open', 'priority_window', 'matched', 'cancelled') | |
| priority_window_ends_at | timestamptz | 우선 배차 60초 마감 시각 |
| matched_worker_id | uuid FK → profiles.id | 최종 배차된 기사 |
| matched_at | timestamptz | 매칭 완료 시각 |
| created_at | timestamptz DEFAULT now() | |

#### `priority_tickets` — 우선 배차권

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid (PK) | |
| owner_id | uuid FK → profiles.id | 보유 기사 |
| source_job_id | uuid FK → jobs.id | 발행 근거 일감 |
| expires_at | timestamptz NOT NULL | 생성 후 30일 |
| used_at | timestamptz | 사용 시각 (NULL = 미사용) |
| created_at | timestamptz DEFAULT now() | |

#### `job_applications` — 지원 (우선 배차 신청)

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid (PK) | |
| job_id | uuid FK → jobs.id | 지원한 일감 |
| applicant_id | uuid FK → profiles.id | 지원 기사 |
| ticket_id | uuid FK → priority_tickets.id NULL | 사용한 우선 배차권 |
| is_priority | boolean DEFAULT false | 우선 지원 여부 |
| applicant_location | geography(Point, 4326) | 지원 시점 기사 위치 |
| score | numeric(5,2) | 별점 70% + 거리 30% 점수 |
| status | text DEFAULT 'pending' CHECK ('pending', 'accepted', 'rejected') | |
| created_at | timestamptz DEFAULT now() | |

#### `notifications` — 알림 로그

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid (PK) | |
| recipient_id | uuid FK → profiles.id | |
| type | text CHECK ('new_job', 'match_success', 'match_fail', 'priority_expired') | |
| title | text | |
| body | text | |
| data | jsonb | 딥링크 등 메타데이터 |
| read | boolean DEFAULT false | |
| created_at | timestamptz DEFAULT now() | |

### 1.2 인덱스

```sql
-- 일감 탐색 성능
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_location ON jobs USING GIST(location);
CREATE INDEX idx_jobs_work_date ON jobs(work_date);
CREATE INDEX idx_jobs_required ON jobs(required_track_type, required_size);

-- 우선 배차권 조회
CREATE INDEX idx_tickets_owner_active
  ON priority_tickets(owner_id)
  WHERE used_at IS NULL AND expires_at > now();

-- 지원 내역 조회
CREATE INDEX idx_applications_job ON job_applications(job_id);
```

### 1.3 RLS (Row Level Security) 정책

```sql
-- profiles: 본인만 수정, 조회는 매칭 상대방에게만 민감 정보 노출
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "프로필 본인 조회/수정"
  ON profiles FOR ALL
  USING (auth.uid() = id);

CREATE POLICY "매칭 상대방 프로필 조회"
  ON profiles FOR SELECT
  USING (
    id IN (
      SELECT matched_worker_id FROM jobs WHERE poster_id = auth.uid() AND status = 'matched'
      UNION
      SELECT poster_id FROM jobs WHERE matched_worker_id = auth.uid() AND status = 'matched'
    )
  );

-- jobs: 누구나 open 조회, 본인만 등록/수정
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "열린 일감 조회" ON jobs FOR SELECT
  USING (status IN ('open', 'priority_window') OR poster_id = auth.uid() OR matched_worker_id = auth.uid());

CREATE POLICY "본인 일감 등록" ON jobs FOR INSERT
  WITH CHECK (poster_id = auth.uid());

-- priority_tickets: 본인 것만
ALTER TABLE priority_tickets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "본인 배차권" ON priority_tickets FOR ALL
  USING (owner_id = auth.uid());

-- job_applications: 본인 지원 + 일감 등록자 조회
ALTER TABLE job_applications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "지원 관련자만 조회"
  ON job_applications FOR SELECT
  USING (
    applicant_id = auth.uid()
    OR job_id IN (SELECT id FROM jobs WHERE poster_id = auth.uid())
  );

CREATE POLICY "본인 지원 등록"
  ON job_applications FOR INSERT
  WITH CHECK (applicant_id = auth.uid());
```

### 1.4 Database Functions (Supabase Edge에서 호출)

```sql
-- 우선 배차권 발급 (일감 등록 시 트리거)
CREATE OR REPLACE FUNCTION issue_priority_ticket()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO priority_tickets (id, owner_id, source_job_id, expires_at)
  VALUES (gen_random_uuid(), NEW.poster_id, NEW.id, now() + interval '30 days');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_issue_ticket
  AFTER INSERT ON jobs
  FOR EACH ROW EXECUTE FUNCTION issue_priority_ticket();

-- 우선 배차 점수 계산 함수
CREATE OR REPLACE FUNCTION calculate_match_score(
  p_rating_sum int,
  p_rating_count int,
  p_applicant_location geography,
  p_job_location geography,
  p_max_distance_km numeric DEFAULT 100
)
RETURNS numeric AS $$
DECLARE
  avg_rating numeric;
  normalized_rating numeric;
  distance_km numeric;
  normalized_distance numeric;
BEGIN
  -- 별점 정규화 (0~1, 리뷰 없으면 0.5)
  IF p_rating_count = 0 THEN
    normalized_rating := 0.5;
  ELSE
    avg_rating := p_rating_sum::numeric / p_rating_count;
    normalized_rating := avg_rating / 5.0;
  END IF;

  -- 거리 정규화 (가까울수록 1에 가까움)
  distance_km := ST_Distance(p_applicant_location, p_job_location) / 1000.0;
  normalized_distance := GREATEST(0, 1 - (distance_km / p_max_distance_km));

  -- 가중치: 별점 70% + 거리 30%
  RETURN (normalized_rating * 0.7) + (normalized_distance * 0.3);
END;
$$ LANGUAGE plpgsql;
```

---

## 2. Flutter 앱 화면 구조

### 2.1 전체 라우팅 맵

```
앱 진입
├── /splash ─── 인증 상태 확인
├── /auth
│   ├── /phone-input ─── 전화번호 입력
│   └── /otp-verify ─── OTP 인증
│   └── /profile-setup ─── 최초 프로필 등록
│
└── /main (BottomNavigationBar: 4탭)
    │
    ├── [탭1] /jobs ─── 일감 목록
    │   ├── /jobs/detail/:id ─── 일감 상세 + 지원 버튼
    │   └── /jobs/create ─── 일 등록 폼
    │
    ├── [탭2] /dispatch ─── 내 배차 내역
    │   ├── /dispatch/active ─── 진행 중 (매칭 대기/완료)
    │   └── /dispatch/detail/:id ─── 배차 상세 (상대방 정보 공개)
    │
    ├── [탭3] /tickets ─── 우선 배차권 관리
    │   └── 보유 현황 / 사용 이력 / 만료 임박 표시
    │
    └── [탭4] /my ─── 마이페이지
        ├── /my/profile-edit ─── 프로필 수정
        ├── /my/posted-jobs ─── 내가 올린 일감
        ├── /my/notifications ─── 알림 목록
        └── /my/settings ─── 설정 (알림 on/off, 로그아웃)
```

### 2.2 주요 화면별 위젯 구성

**일감 목록 화면 (`/jobs`)**
- 상단: 필터 칩 (바퀴/궤도, 소형/중형/대형)
- 정렬 토글: 거리순 / 날짜순
- `ListView.builder` → `JobCard` 위젯
  - 매칭 완료: 빨간 배지 + `ImageFiltered`(blur) 또는 `BackdropFilter`
  - 미매칭: 지역명, 일시, 장비조건, 거리 표시
- FAB: 일 등록 화면으로 이동

**일감 상세 화면 (`/jobs/detail/:id`)**
- Google Maps 위젯 (핀 표시)
- 작업 정보, 장비 조건, 메모
- 하단 CTA 버튼: "지원하기" (우선 배차권 보유 시 "우선 지원" 표시)
- 우선 배차 진행 중이면 카운트다운 타이머 표시

**일 등록 화면 (`/jobs/create`)**
- `Form` 위젯: 날짜/시간 피커, 지역명 입력
- Google Maps 위젯: 핀 드래그 or 주소 검색 (Geocoding)
- 장비 조건 드롭다운
- 등록 완료 시 → 우선 배차권 +1 토스트 메시지

**배차 상세 화면 (`/dispatch/detail/:id`)**
- 매칭 상태 표시
- 매칭 완료 시: 상대방 이름, 전화번호, 계좌번호 카드
- 전화 걸기 버튼 (`url_launcher`)

### 2.3 상태 관리

Riverpod을 권장합니다. 주요 Provider 구조는 다음과 같습니다.

```
authStateProvider          ← Supabase Auth 상태 스트림
profileProvider            ← 본인 프로필 (AsyncNotifier)
jobListProvider            ← 일감 목록 (필터/정렬 파라미터 포함)
jobDetailProvider(id)      ← 개별 일감 상세 (Family)
myDispatchListProvider     ← 내 배차 내역
ticketCountProvider        ← 유효한 우선 배차권 수
notificationListProvider   ← 알림 목록
locationProvider           ← Geolocator 현재 위치
```

---

## 3. 핵심 비즈니스 로직 구현

### 3.1 우선 배차권 60초 매칭 타이머

이 로직은 **서버 사이드(Supabase Edge Function + pg_cron)**에서 처리해야 합니다. 클라이언트 타이머에 의존하면 앱 종료, 네트워크 끊김 등에서 일관성이 깨집니다.

**플로우:**

```
1. 기사 A가 일감 등록
   → DB 트리거로 우선 배차권 발급
   → Edge Function "notify-new-job" 호출

2. Edge Function: 조건 맞는 기사 중 우선 배차권 보유자 조회
   → FCM 푸시 발송 (우선 지원 안내)
   → jobs.status = 'priority_window'
   → jobs.priority_window_ends_at = now() + 60초

3. 우선 배차권 보유 기사가 "우선 지원" 클릭
   → job_applications INSERT (is_priority = true)
   → priority_tickets.used_at = now() (차감)
   → calculate_match_score() 호출하여 score 저장

4. 60초 후: pg_cron 또는 Edge Function cron이 실행
   → priority_window_ends_at <= now() 인 일감 조회
   → 우선 지원자 존재 시: score 최고점 기사를 matched_worker_id에 기록
   → 우선 지원자 없을 시: status = 'open' (일반 공개 전환)
   → 결과에 따라 FCM 알림 발송 (매칭 성공/실패)
```

**60초 타이머 구현 옵션 비교:**

| 방법 | 장점 | 단점 |
|------|------|------|
| pg_cron (1분 간격) | 가장 단순, Supabase 내장 | 최소 1분 단위, 수 초 오차 |
| Supabase Edge Function + setTimeout | 정확한 60초 | Edge Function에 max duration 제한 존재 |
| **권장: pg_cron + Edge Function 조합** | pg_cron이 매분 만료 대상 처리, Edge Function은 점수 계산 담당 | 약간의 구현 복잡도 |

**pg_cron 설정 예시:**

```sql
-- 매 분마다 실행: 만료된 우선 배차 윈도우 처리
SELECT cron.schedule(
  'process-priority-windows',
  '* * * * *',   -- 매 분
  $$
    SELECT net.http_post(
      url := 'https://<project>.supabase.co/functions/v1/process-priority-match',
      headers := '{"Authorization": "Bearer <service_role_key>"}'::jsonb
    );
  $$
);
```

**Flutter 클라이언트 측:**

```dart
// 일감 상세 화면에서 카운트다운 UI만 표시
// 실제 매칭 판정은 서버에서 수행
StreamBuilder<int>(
  stream: _countdownStream(job.priorityWindowEndsAt),
  builder: (context, snapshot) {
    final remaining = snapshot.data ?? 0;
    if (remaining > 0) {
      return Text('우선 배차 마감까지 ${remaining}초');
    }
    return Text('일반 공개 전환 중...');
  },
)
```

### 3.2 별점 70% + 거리 30% 자동 채택 알고리즘

**점수 계산 상세 로직 (Edge Function: `process-priority-match`):**

```typescript
// Deno Edge Function 의사코드
async function processExpiredWindows() {
  // 1. 만료된 우선 배차 윈도우 조회
  const expiredJobs = await supabase
    .from('jobs')
    .select('*')
    .eq('status', 'priority_window')
    .lte('priority_window_ends_at', new Date().toISOString());

  for (const job of expiredJobs) {
    // 2. 해당 일감의 우선 지원자들 조회 (score 내림차순)
    const { data: applications } = await supabase
      .from('job_applications')
      .select('*, applicant:profiles(*)')
      .eq('job_id', job.id)
      .eq('is_priority', true)
      .eq('status', 'pending')
      .order('score', { ascending: false });

    if (applications.length > 0) {
      const winner = applications[0];

      // 3. 매칭 확정
      await supabase.from('jobs').update({
        status: 'matched',
        matched_worker_id: winner.applicant_id,
        matched_at: new Date().toISOString(),
      }).eq('id', job.id);

      // 4. 지원자 상태 업데이트
      await supabase.from('job_applications')
        .update({ status: 'accepted' })
        .eq('id', winner.id);

      await supabase.from('job_applications')
        .update({ status: 'rejected' })
        .eq('job_id', job.id)
        .neq('id', winner.id);

      // 5. 알림 발송
      await sendFCM(winner.applicant_id, '매칭 성공!');
      await sendFCM(job.poster_id, '배차 완료!');
    } else {
      // 우선 지원자 없음 → 일반 공개
      await supabase.from('jobs').update({
        status: 'open',
        priority_window_ends_at: null,
      }).eq('id', job.id);
    }
  }
}
```

**점수 계산 예시:**

| 기사 | 평균 별점 | 거리 (km) | 별점 점수 (×0.7) | 거리 점수 (×0.3) | 총점 |
|------|-----------|-----------|-------------------|-------------------|------|
| 기사 A | 4.5/5 | 10km | 0.63 | 0.27 | **0.90** |
| 기사 B | 5.0/5 | 50km | 0.70 | 0.15 | 0.85 |
| 기사 C | 3.0/5 | 5km | 0.42 | 0.29 | 0.71 |

→ 기사 A 채택 (별점과 거리의 균형이 가장 좋음)

### 3.3 FCM + Supabase Edge Function 알람 플로우

```
[이벤트 발생]
    │
    ▼
[Supabase DB Webhook / Trigger]
    │
    ▼
[Edge Function: send-notification]
    │
    ├─ 1. 대상 기사 조건 쿼리
    │     (장비 조건 매칭 + 우선 배차권 보유 여부)
    │
    ├─ 2. notifications 테이블에 로그 INSERT
    │
    ├─ 3. 대상자들의 fcm_token 조회
    │
    └─ 4. FCM HTTP v1 API 호출 (배치 전송)
         POST https://fcm.googleapis.com/v1/projects/{id}/messages:send
         {
           "message": {
             "token": "<fcm_token>",
             "notification": {
               "title": "새 일감이 등록되었습니다",
               "body": "강남구 · 궤도형 대형 · 3/15 09:00"
             },
             "data": {
               "type": "new_job",
               "job_id": "xxx"
             }
           }
         }
```

**알림 유형별 트리거:**

| 이벤트 | 트리거 | 대상 | 우선순위 |
|--------|--------|------|----------|
| 새 일감 등록 | jobs INSERT webhook | 조건 맞는 기사 (우선권 보유자 먼저) | High |
| 매칭 성공 | process-priority-match 내부 | 채택 기사 + 일 등록 기사 | High |
| 매칭 실패 | process-priority-match 내부 | 탈락 기사들 | Normal |
| 우선 배차권 만료 임박 | pg_cron (일 1회) | 3일 내 만료 기사 | Low |

**Flutter 클라이언트 FCM 설정:**

```dart
// main.dart
await Firebase.initializeApp();
final fcmToken = await FirebaseMessaging.instance.getToken();
// → Supabase profiles.fcm_token 업데이트

FirebaseMessaging.onMessage.listen((message) {
  // 포그라운드 알림 → 앱 내 스낵바 또는 로컬 노티피케이션
});

FirebaseMessaging.onMessageOpenedApp.listen((message) {
  // 알림 탭 → 해당 일감 상세로 딥링크
  final jobId = message.data['job_id'];
  context.push('/jobs/detail/$jobId');
});
```

---

## 4. 개발 순서 (Phase별 로드맵)

### Phase 1 — 기반 구축 (2주)

- Supabase 프로젝트 생성, PostGIS 확장 활성화
- Flutter 프로젝트 초기 구조 (`go_router`, `riverpod`, `supabase_flutter`)
- 전화번호 인증 회원가입 + 프로필 등록 플로우
- profiles 테이블 + RLS
- 기본 라우팅 및 BottomNavigationBar 골격

**완료 기준:** 회원가입 → 로그인 → 프로필 조회 동작

### Phase 2 — 일감 CRUD (2주)

- jobs 테이블 + RLS + PostGIS 인덱스
- 일 등록 폼 (Google Maps 핀 + Geocoding)
- 일감 목록 화면 (필터, 정렬)
- 일감 상세 화면
- 우선 배차권 자동 발급 트리거

**완료 기준:** 일감 등록 → 목록 조회 → 상세 확인, 배차권 자동 발급

### Phase 3 — 매칭 엔진 (2~3주)

- job_applications 테이블
- 일반 지원 (선착순) 로직
- 우선 지원 로직 + 배차권 차감
- `calculate_match_score` DB 함수
- Edge Function: `process-priority-match` (60초 후 자동 채택)
- pg_cron 설정
- 매칭 완료 시 상대방 정보 공개 화면

**완료 기준:** 우선 지원 60초 → 자동 채택 → 상대방 정보 열람

### Phase 4 — 푸시 알림 (1주)

- Firebase 프로젝트 연동 (iOS/Android)
- FCM 토큰 관리
- Edge Function: `send-notification`
- DB Webhook 설정 (jobs INSERT → 알림)
- 알림 목록 화면

**완료 기준:** 일감 등록 시 조건 기사에게 푸시 수신

### Phase 5 — 폴리싱 및 테스트 (1~2주)

- 배차 완료 일감 블러 처리 UI
- 우선 배차권 관리 화면 (보유/사용/만료 현황)
- 에러 핸들링, 로딩 상태, 빈 화면 처리
- Edge case 테스트 (동시 지원, 네트워크 불안정 등)
- iOS/Android 빌드 및 실기기 테스트

### Phase 6 — 추후 기능 (별도 일정)

- 별점 시스템 (작업 완료 후 상호 평가)
- 캘린더 뷰 (내 배차 일정)
- 기사 간 채팅 (Supabase Realtime)
- 우선 배차권 월 정액제 결제 (인앱 결제 or PG)

---

## 5. 기술적 리스크 및 해결 방안

### 5.1 60초 타이머 정확도

**리스크:** pg_cron은 1분 단위라서 최대 59초 지연 가능. 60초 윈도우가 실질적으로 60~119초가 될 수 있음.

**해결:** priority_window_ends_at을 정확한 timestamp로 저장하고, pg_cron 실행 시 `WHERE priority_window_ends_at <= now()` 조건으로 필터합니다. 초기에는 이 정도 오차가 수용 가능하며, 사용량 증가 시 Supabase Realtime + Edge Function의 서버 사이드 타이머로 교체할 수 있습니다.

### 5.2 동시 지원 Race Condition

**리스크:** 여러 기사가 동시에 우선 지원 시 배차권 이중 차감이나 중복 매칭 발생 가능.

**해결:**
- 배차권 차감은 `UPDATE ... WHERE used_at IS NULL` + `RETURNING`을 사용하여 원자적으로 처리
- 매칭 확정은 `UPDATE jobs SET matched_worker_id = $1 WHERE id = $2 AND status = 'priority_window'` 로 한 번만 성공하도록 보장
- 지원 INSERT에 `UNIQUE(job_id, applicant_id)` 제약 추가

### 5.3 PostGIS 거리 계산 성능

**리스크:** 사용자 증가 시 거리 기반 정렬/필터링 쿼리 부하.

**해결:** `geography` 타입의 GIST 인덱스로 공간 쿼리를 최적화합니다. 초기 규모에서는 충분하며, 수만 건 이상 시 `ST_DWithin`으로 반경 제한 후 정렬하는 2단계 쿼리로 전환합니다.

### 5.4 FCM 토큰 관리

**리스크:** 토큰 만료, 앱 삭제, 기기 변경 시 푸시 실패.

**해결:**
- 앱 시작 시마다 `getToken()` 호출하여 갱신
- `onTokenRefresh` 리스너로 자동 업데이트
- FCM 전송 실패 응답 시 해당 토큰 삭제
- 알림 실패 시 앱 내 notifications 테이블은 항상 기록 (인앱 알림으로 보완)

### 5.5 Supabase 전화번호 인증 제한

**리스크:** Supabase Phone Auth는 Twilio 연동이 필요하고, SMS 비용이 발생함.

**해결:** 개발/테스트 단계에서는 Supabase의 test OTP 기능을 활용합니다. 프로덕션에서는 Twilio 또는 국내 SMS API(알리고, NHN Cloud 등)를 Supabase Auth Hook으로 연동합니다. 대안으로 카카오 로그인 등 소셜 인증도 고려할 수 있습니다.

### 5.6 일반 공개 선착순 매칭의 공정성

**리스크:** 선착순은 네트워크 속도에 의존하여 불공정할 수 있음.

**해결:** 일반 공개 전환 후에도 5~10초의 짧은 수집 윈도우를 두고 선착순이 아닌 거리 기반 매칭을 적용하는 것을 고려합니다. 초기에는 순수 선착순으로 시작하되, 사용자 피드백에 따라 조정합니다.

### 5.7 Supabase Edge Function Cold Start

**리스크:** Edge Function의 콜드 스타트(~1초)로 인해 알림 지연 발생 가능.

**해결:** 알림은 실시간성이 약간 느슨해도 허용되는 기능입니다. pg_cron이 이미 1분 단위이므로 추가 1초 지연은 무시할 수 있습니다. 필요 시 Edge Function을 주기적으로 호출하여 warm 상태를 유지할 수 있습니다.

---

## 부록: 프로젝트 폴더 구조 (권장)

```
lib/
├── main.dart
├── app/
│   ├── router.dart              # GoRouter 설정
│   └── theme.dart               # 앱 테마
├── core/
│   ├── supabase_client.dart     # Supabase 초기화
│   ├── constants.dart
│   └── extensions.dart
├── features/
│   ├── auth/
│   │   ├── presentation/        # 화면, 위젯
│   │   ├── providers/           # Riverpod providers
│   │   └── data/                # Repository
│   ├── jobs/
│   │   ├── presentation/
│   │   │   ├── job_list_screen.dart
│   │   │   ├── job_detail_screen.dart
│   │   │   ├── job_create_screen.dart
│   │   │   └── widgets/
│   │   ├── providers/
│   │   ├── data/
│   │   └── domain/              # 모델 클래스
│   ├── dispatch/
│   ├── tickets/
│   ├── notifications/
│   └── profile/
├── shared/
│   ├── widgets/                 # 공통 위젯
│   └── models/                  # 공통 모델

supabase/
├── migrations/                  # SQL 마이그레이션 파일
├── functions/
│   ├── send-notification/
│   ├── process-priority-match/
│   └── shared/                  # 공통 유틸 (FCM 호출 등)
└── config.toml
```
