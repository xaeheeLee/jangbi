# 장비나라 — 구현 이슈 트래커 (v1.0)

> **이 문서의 목적**
> 2차 미팅 준비 검토 과정에서 발견한 **구현/설계상 오류·어색한 부분**을 한곳에 모아 관리합니다.
> 미팅 결과 + 본 이슈 처리 후 `01_dev_plan_v2.1.md`가 `v2.2`로 갱신됩니다.
>
> **표기 규칙**
> - 🔴 critical — 1차 개발 착수 전 반드시 결정/수정
> - 🟡 minor — 구현 중 갱신 가능 (착수 후 정리)
> - 상태: `open` → `in-progress` → `resolved`

---

## 진행 현황 요약

| ID | 제목 | 심각도 | 상태 |
|----|------|--------|------|
| B-1 | 장비 톤수 ↔ DB enum 매핑 부재 | 🔴 | open |
| B-2 | 매칭 점수 공식이 mockup ↔ v2.1 불일치 | 🔴 | open |
| B-3 | mockup 입력값을 받지 못하는 jobs 스키마 (5개 컬럼 누락) | 🔴 | open |
| B-4 | `profiles.activity_score` 컬럼 부재 | 🔴 | open |
| B-5 | 30/60초 윈도우 vs pg_cron 1분 단위 괴리 | 🔴 | open |
| B-6 | `finalize_priority_match`에서 winner 일정 재검증 없음 | 🔴 | open |
| B-7 | Realtime UPDATE 이벤트와 RLS 충돌 가능성 | 🟡 | open |
| B-8 | mockup "지원자 N명" 표시가 RLS 위반 | 🟡 | open |
| B-9 | mockup 5탭과 v2.1 라우팅 5탭 불일치 | 🟡 | open |
| B-10 | 로그아웃 시 device_token 미삭제 | 🟡 | open |
| B-11 | 자기 일감 등록 시 본인 배차권 발급의 어뷰징 위험 | 🟡 | open |
| B-12 | BEFORE INSERT 트리거의 SECURITY DEFINER 의미 모호 | 🟡 | open |
| B-13 | `expire-old-jobs` cron이 `priority_window`를 무차별 expire | 🟡 | open |
| B-14 | `matched → completed` 24시간 자동 전환의 모호함 | 🟡 | open |
| B-15 | 1차 캘린더 충돌 정의가 "날짜 단위"라 실용성 부족 | 🟡 | open |
| B-16 | 위치 권한 거부 사용자 fallback 정책 부재 | 🟡 | open |
| B-17 | Supabase Auth — phone OTP + 비밀번호 조합 직접 미지원 | 🟡 | open |
| B-18 | `score numeric(7,4)` IMP-4 흔적이 본문에 남아있음 | 🟡 | open |

---

## 🔴 Critical — 1차 개발 착수 전 결정 필요

### B-1. 장비 톤수 ↔ DB enum 매핑 부재

- **현상**
  - DB 스키마: `equipment_size CHECK ('small','medium','large')` (3단계)
  - mockup 가입/등록 화면: 02톤 / 035톤 / 06톤 / 3.5톤 / 5톤 (5단계)
- **영향**: 매칭 조건이 정확히 작동하지 않음. 02톤·035톤·06톤이 모두 "소형"으로 묶이면, 등록자는 "06톤"을 요구했는데 02톤 기사도 매칭됨.
- **결정 옵션**
  - A. enum 폐기 → `equipment_tons text` 또는 `numeric(4,2)`로 톤수 그대로 저장
  - B. enum 유지 + 매핑 테이블 (`equipment_tier_map`) 추가
- **권장**: A. 톤수 그대로 저장 + 필터/조건 매칭 시 정확히 비교.

### B-2. 매칭 점수 공식이 mockup ↔ v2.1 불일치

- **현상**
  - `calculate_match_score`: **별점 70% + 거리 30%**
  - mockup `bidding` 화면: "**활동지수+거리** 기준 자동 선정", "나의 활동지수 92점 · 매칭 확률 높음"
  - mockup `jobdetail` 안내: "별점+거리 기준 자동 채택" (v2.1과 일치)
- **영향**: 같은 mockup 안에서도 두 가지 표현이 섞여 있어 고객/사용자 모두 혼란.
- **연결**: 미팅 Q2(매칭 공식), Q7(활동지수 산정).
- **결정 옵션**
  - A. 별점만 (v2.1 그대로)
  - B. 활동지수 도입 → `calculate_match_score`를 (활동지수·별점·거리 가중 평균)로 재정의
  - C. 4지표안 (고객 예시: 콜수행 40 + 정시 30 + 평가 50 − 취소 20)

### B-3. mockup 입력값을 받지 못하는 jobs 스키마

| mockup UI | 필요 컬럼 | v2.1 jobs | 결정 필요 |
|---|---|---|---|
| 작업 종료 시간 (시작~종료) | `work_end_date timestamptz` | 없음 (P1-2) | 1차 포함 여부 |
| 작업 종류 태그 (뿌레카/그라플…) | `work_types text[]` | 없음 | 1차 포함 여부 |
| 이용 금액 (60만원) | `price int` | 없음 | 1차 포함 여부 |
| 사진 첨부 | `images text[]` (Supabase Storage 경로) | 없음 | 1차 포함 여부 |
| 임시저장 | `status` enum에 `'draft'` | 없음 | 1차 포함 여부 |

- **권장**: 모두 1차 포함. mockup이 이미 받고 있으므로 출시 후 P1으로 미루면 UI 재작업이 더 비쌈.

### B-4. `profiles.activity_score` 컬럼 부재

- **현상**: mockup 곳곳에 "활동지수 92" 표시 (마이페이지·일감 상세·우선배차 진행). DB에는 `rating_sum`/`rating_count`만 있음.
- **결정 필요**
  - 별도 컬럼으로 저장 (`activity_score int DEFAULT 50`)
  - 산정 정책 (Q7): 어떤 이벤트에 가산/감산?
  - 갱신 트리거 (일감 완료 시 +N 등)
- **연결**: Q7.

### B-5. 30/60초 윈도우 vs pg_cron 1분 단위 괴리

- **현상**: `process-priority-windows` cron이 매분 실행 → 윈도우가 실제로 30~89초 (목표가 30초일 때) 또는 60~119초 (목표가 60초일 때).
- **영향**: mockup `bidding` 화면이 클라이언트 카운트다운 "24초"를 보여주는데 서버 단 마감이 +30초 이상 지연될 수 있음 → 사용자 혼란, 추가 지원 가능 시간 존재.
- **해결 옵션**
  - A. **Edge Function setInterval** — 워밍 유지하면서 5~10초 단위로 만료 검사
  - B. **클라이언트 카운트다운 + 서버 finalize 트리거** — Realtime으로 종료 시 push
  - C. cron을 그대로 두되, **클라이언트 표시값을 `priority_window_ends_at` 기준으로 동기화**하고 +20초까지 grace
- **권장**: A 또는 C. (B는 클라이언트 신뢰 위험)

### B-6. `finalize_priority_match`에서 winner 일정 재검증 없음

- **현상**: 우선 지원 시점에 일정 충돌 체크하지만, 30~60초 사이에 winner가 다른 일감의 `apply_general`로 매칭될 수 있음. finalize는 그 사실을 확인하지 않음.
- **결과**: 동일 날짜에 2건 매칭 → 작업자 노쇼 발생.
- **수정**: `finalize_priority_match`에서 winner 결정 후, 해당 winner의 `matched_worker_id` 기존 일정과 `tstzrange` 겹침 재검증. 충돌 시 차순위로 fallback.

---

## 🟡 Minor — 구현 중 갱신 가능

### B-7. Realtime UPDATE 이벤트와 RLS 충돌 가능성

- **현상**: `supabase.from('jobs').stream().eq('matched_worker_id', currentUserId)` 구독.
- **문제**: 매칭 *직전* 본인은 그 jobs row가 RLS상 보이지 않을 수 있음 (status=`open`이면 보이지만, 어쨌든 본인이 매칭되는 UPDATE 이벤트가 RLS를 통과해서 도달해야 함).
- **검증 필요**: Supabase Realtime이 UPDATE 시 이전 row와 새 row 모두 RLS 통과를 요구하는지 실제 테스트.
- **대안**: `job_applications`를 `applicant_id = me`로 구독하거나, 매칭 시점에 별도 알림 RPC 발송.

### B-8. mockup "지원자 N명" 표시가 RLS 위반

- **현상**: mockup `bidding` 화면 "현재 지원자 3명". 현재 RLS는 본인 지원 + 본인 발주만 SELECT 허용.
- **수정**: `count_priority_applicants(p_job_id uuid)` SECURITY DEFINER RPC 신설 → 개수만 반환.

### B-9. mockup 5탭과 v2.1 라우팅 5탭 불일치

- **mockup**: 홈 / 일감 / 캘린더 / 배차권 / MY
- **v2.1**: jobs / dispatch / calendar / tickets / my
- **결정**
  - "홈"이 별도 화면인지 (대시보드?) 혹은 일감 목록과 동일?
  - "dispatch(내 배차)" 탭을 폐기하고 MY 메뉴로 통합?
- **권장**: mockup 기준으로 v2.1 라우팅 조정.

### B-10. 로그아웃 시 device_token 미삭제

- **현상**: v2.1에 로그아웃 흐름에서 `device_tokens` 정리 규약 없음.
- **위험**: 같은 기기에서 다른 사용자가 로그인 시, 이전 사용자에게 푸시 발송됨.
- **수정**: 로그아웃 시 `DELETE FROM device_tokens WHERE token = currentToken`.

### B-11. 자기 일감 등록 시 본인 배차권 발급 — 어뷰징 위험

- **현상**: `on_job_created` 트리거가 등록자에게 무조건 배차권 1장 발급.
- **위험**: 가짜 일감 양산 → 배차권 무한 발급.
- **방어 옵션**
  - A. 등록 시 발급 유지, 일감 cancel/expired 시 배차권 회수
  - B. **매칭/완료된 일감에 한해 발급** (등록 시점 → 완료 시점으로 이동)
  - C. 1일/주당 발급 상한 (예: 1일 3장)

### B-12. BEFORE INSERT 트리거의 SECURITY DEFINER 의미 모호

- **현상**: `on_job_created`가 `SECURITY DEFINER`. 트리거 자체는 호출자 권한과 무관하게 동작하므로 의미가 모호하지만, 함수 내부에서 `priority_tickets INSERT`를 위해 필요.
- **권장**: 함수 내부에 `IF auth.uid() != NEW.poster_id THEN RAISE EXCEPTION` 권한 검증 추가.

### B-13. `expire-old-jobs` cron이 `priority_window`를 무차별 expire

- **현상**: `WHERE status IN ('open','priority_window') AND work_date < now() - interval '1 hour'`.
- **위험**: finalize 누락된 priority_window 일감이 어디에도 매칭되지 않은 채 expired로 빠짐.
- **수정**: priority_window는 별도 처리 (`finalize_priority_match` 강제 호출 후 그래도 미매칭이면 expired).

### B-14. `matched → completed` 24시간 자동 전환의 모호함

- **현상**: 8시간 작업도, 3일 작업도, 24시간 후 일률적으로 completed로 전환.
- **결정 필요**: 작업자/발주자 "완료" 신호 도입 여부 + Q12 평가 시스템 시점.
- **권장**: `work_end_date + interval '2 hours'` 후 자동 전환으로 변경 (work_end_date 컬럼 도입과 묶음).

### B-15. 1차 캘린더 충돌 정의가 "날짜 단위"라 실용성 부족

- **현상**: 1차는 같은 날짜에 2건 있으면 충돌. 시간대 겹침은 P1-2.
- **현장 현실**: 포크레인은 오전·오후 다른 현장이 흔함 → 1차부터 사용자 짜증 유발.
- **권장**: P1-2(work_end_date + tstzrange 겹침)를 1차에 통합 (B-3과 동시 처리).

### B-16. 위치 권한 거부 사용자 fallback 정책 부재

- **현상**: `apply_*` RPC가 lat/lng 필수. 거리순 정렬도 위치 필요. 거부 시 동작 정의 없음.
- **결정 옵션**
  - A. 위치 권한 거부 시 앱 사용 차단
  - B. 거리 점수 0.5 fallback + 거리순 정렬 비활성
  - C. 마지막 알려진 위치 + 기간 만료 시 재요청
- **iOS 백그라운드 위치**: 매우 까다로움 → 앱 열기 전엔 위치 못 얻음. 푸시 받고 → 앱 열고 → 위치 갱신 흐름 명확화 필요.

### B-17. Supabase Auth — phone OTP + 비밀번호 조합 직접 미지원

- **현상**: Supabase Auth 표준은 phone OTP **또는** email/password. 양쪽 동시 운영이 표준 제공 아님.
- **구현 옵션**
  - A. phone을 email 형식(`010-xxxx-yyyy@jangbinara.local`)으로 변환 + password 사용
  - B. 가입은 phone OTP, 로그인은 ID/PW (custom auth + 자체 토큰)
  - C. 카카오 소셜 로그인 도입 (SMS 비용 절감 + UX 단순화)
- **권장**: A 또는 C. 추가 작업 +0.5~1주 산정.

### B-18. `score numeric(7,4)` IMP-4 흔적이 본문에 남아있음

- **현상**: v2.1 본문 표는 `score numeric(7,4)`로 갱신되었으나 IMP-4 보완 설명만 별도로 남아있어 혼란 가능.
- **조치**: v2.2 작성 시 IMP-4 흔적 정리.

---

## 신규 안건과의 연결 (미팅용 Q13~)

본 트래커의 항목 중 일부는 미팅에서 결정되어야 처리 가능합니다. `02_meeting_agenda_v1.2.md` 신규 항목과의 대응:

| 미팅 Q | 본 트래커 |
|--------|-----------|
| Q13 1차 work_end_date 포함 | B-3, B-15 |
| Q14 사진 첨부 1차 포함 | B-3 |
| Q15 임시저장 1차 포함 | B-3 |
| Q16 매칭 후 취소·노쇼 정책 | B-14 (간접) |
| Q17 매칭 후 거래(결제) 흐름 / 계좌 공개 방향 | — |
| Q18 등록자 배차권 발급 의도 | B-11 |
| Q19 위치 권한 거부 대응 | B-16 |
| Q20 푸시 발송 범위 | — |
| Q21 일감 검색 기능 | — |
| Q22 캘린더 휴무 등록 | — |
| Q23 5탭 구성 (홈 vs dispatch) | B-9 |
| Q24 매칭 후 양측 정보 공개 범위 | — |
| Q25 우선배차 취소·환불 | — |
| Q26 매칭 결과 → 캘린더 UX 흐름 | — |

---

## 변경 이력

| 버전 | 날짜 | 내용 |
|------|------|------|
| v1.0 | 2026-05-22 | 최초 작성. 2차 미팅 준비 검토에서 발견한 B-1~B-18 정리 |
