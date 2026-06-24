# Claude Code 작업 지침 (장비나라 프로젝트)

이 파일은 Claude Code가 자동으로 읽는 컨텍스트 파일입니다. 모든 작업 전에 이 지침을 따르세요.

## 🎯 프로젝트 개요

- **앱:** 전중배(전국중장비배차) — 구 가칭 장비나라. 중장비 기사 간 배차 매칭 모바일 앱
- **스택:** Flutter + Supabase (PostgreSQL + Realtime + Auth + Storage) + Riverpod + FCM + 토스페이먼츠(가상계좌)
- **개발 모드:** 1인 개발자가 Claude Code 활용하여 진행
- ⚠️ **거리/GPS 매칭은 폐지됨** — 매칭은 별점 100%(베이지안). 지도는 위치 표시용. PostGIS는 1차에서 선택.

## 📚 작업 전 필수 확인 문서

새 작업 시작 시 다음 순서로 참고하세요. **현행 기준은 v3.0 / v1.1이며, v2.1·v1.0은 폐기(이력용)입니다.**

1. **docs/01_dev_plan_v3.0.md** — 메인 개발 계획서 (DB 스키마, RPC, RLS 모두 포함) ← 현행
2. **docs/12_기능명세서_v1.1.md** — 계약 별첨 기능 명세 ← 현행
3. **docs/3차 미팅 요약.md** — 최신 의사결정
4. **HANDOFF.md** / **docs/05_conversation_summary.md** — 전체 컨텍스트
5. **mockups/Mockup_0425/** — UI 디자인 기준 (`index.html` 모바일, `admin.html` 관리자웹)

## 🛠️ 코딩 시 절대 원칙

### 1. 락 순서 준수

모든 SQL RPC에서 락은 다음 순서로만 잡습니다:
```
1. jobs (FOR UPDATE / FOR UPDATE SKIP LOCKED)
2. priority_tickets (FOR UPDATE SKIP LOCKED)
3. job_applications (UPDATE/INSERT)
4. profiles (포인트 차감/가산 UPDATE)
5. point_transactions (INSERT, 원장)
6. notifications (INSERT, 락 없음)
```

순서 어기면 데드락. 새 RPC 작성 시 반드시 확인.

### 2. RLS 우회는 SECURITY DEFINER로만

핵심 비즈니스 로직(매칭, 배차권 차감, **포인트 충전/차감/소개비/인출** 등)은 전부 `SECURITY DEFINER` RPC 함수로 작성. RLS는 SELECT 정책에만 사용.

### 3. 모든 정책 수치는 app_settings 상수로 분리

우선배차 윈도우 초, 하루 차감(1000p), 소개비율(10%), 플랫폼 수수료(현재 0, 추후 1000p), PG 수수료(440p), 베이지안 c/m, 지정배차 보상(3건당 1장) 등은 **하드코딩 금지**, `app_settings` 테이블에서 읽기.

```dart
// ❌ const PRIORITY_WINDOW_SECONDS = 30;
// ✅ app_settings.priority_window_seconds (기본 30초, 20초는 추후 변경 예정)
```

### 3-1. 매칭/등급 핵심 규칙 (v3.0)

- **매칭 점수 = 별점 100% 베이지안** (거리/GPS 사용 금지)
- **우선순위:** 프리미엄 명단 → 우선배차권+발주이력(직전3개월 매칭성사 일반발주, 지정배차 제외) → 우선배차권+별점 → 일반 선착순
- **프리미엄 = `profiles.is_premium` 플래그**(관리자 명단), 만료/수량 없음, 하루 1건 면제, 우선배차권 없이 우선지원 가능
- **회원등급:** pending(승인대기) / active(정회원) / suspended(준회원=잔액<1000, 전체차단)
- **하루 1건 = 배차 수락일 기준**(프리미엄·지정배차 제외)
- **차단:** `user_blocks`. 단방향 저장, 양방향 비노출+매칭 차단

### 4. 디자인 토큰 사용

| 토큰 | 값 |
|------|-----|
| Primary | `#002F6C` |
| Primary Light | `#3B82F6` |
| Primary BG | `#EFF6FF` |
| 폰트 | Pretendard Variable |

## 🚨 코드 작성 시 주의사항

### Flutter 측

- **Riverpod 사용** — Provider 이름은 `*Provider` 컨벤션
- **go_router** — 라우팅 (계획서 섹션 3.1 참조)
- **에러 처리** — RPC 에러 코드 매핑 (계획서 섹션 7.1)
- **Realtime 구독** — 일감 목록 + 배차 상태 양방향

### Supabase 측

- **모든 RPC는 PostgreSQL 함수** — Edge Functions 최소화
- **pg_cron 작업:**
  - deduct-daily-fee (매일 새벽, 1000p 차감 + 잔액부족 시 박탈)
  - process-priority-windows (매분)
  - expire-old-jobs (매일 자정)
  - auto-complete-jobs (매일 새벽 1시)
  - notify-expiring-tickets (매일 오전 9시)
  - notify-point-low (매일 오전 9시, 잔액 임박 경고)
- **포인트 원장:** 모든 증감은 `point_transactions`에 `balance_after`까지 기록(세무·정산·감사)
- **서류 Storage:** 비공개 버킷 + 서명URL. 발주자에게는 **마스킹본만** 노출(원본 비공개)

### 푸시 알림

- **High priority FCM** 사용 (갤럭시 절전모드 일부 우회)
- **Silent push** 로 사전 동기화
- **앱 첫 실행 시** 디바이스 케어 예외 등록 안내

## 📋 현재 작업 단계

**Phase 0 — 환경 셋업 (미시작):** Flutter / Supabase / Firebase / 토스페이먼츠

**로드맵 (v3.0, 약 24~26주):**
- P1 기반(회원가입 서류5종·로그인·승인대기·골격) → P2 일감 CRUD(일반/지정·지역장비필터)
- P3 매칭 엔진(우선배차권·베이지안·4단계·지정배차) → **P4 포인트/결제(충전·일일차감·소개비·인출·원장)**
- P5 푸시(알림 필터) → P6 캘린더 → **P7 관리자 웹(승인·마스킹·프리미엄명단·세무export)** → P8 폴리싱/배포

> **P4 결제/인출은 PG 계약 + 사업자 선불업 등록 완료가 선행**되어야 마감 가능(블로커).

자세한 태스크는 `docs/01_dev_plan_v3.0.md` 섹션 8 참조.

## 📝 작업 진행 시 권장사항

1. **DB 먼저, UI 나중:** 마이그레이션 → RPC → Flutter UI 순
2. **각 Phase 끝에 1주 버퍼** 확보
3. **실기기 테스트** 필수 (특히 갤럭시)
4. **마일스톤 데모** 단위로 commit

## 🔗 주요 참고 링크

- Supabase 문서: https://supabase.com/docs
- Flutter 문서: https://docs.flutter.dev
- PostGIS 문서: https://postgis.net/documentation/
- 카카오맵 JavaScript API: https://apis.map.kakao.com/web/
- 카카오 로컬 REST API: https://developers.kakao.com/docs/latest/ko/local/dev-guide
- Pretendard 폰트: https://github.com/orioncactus/pretendard
- pretendard pub.dev: https://pub.dev/packages/pretendard

## ✅ 정책 항목 (전부 확정)

- **R1:** 인출 = 충전금 포함 전 잔액(본인 명의 계좌)
- **R2:** 충전 입금=원금+부가세10%, PG 수수료 440p는 포인트에서 차감(약관에 사용자 부담 명시)
- **R3:** 우선배차 윈도우 기본 30초(20초 추후)
- **R4:** 사업자 선불업 등록 진행 전제

상세: `docs/12_기능명세서_v1.1.md` 섹션 7.
