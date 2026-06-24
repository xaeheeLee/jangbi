# 전중배 — 최종 개발 계획서 (v3.0)

> 본 문서는 v2.1 계획서를 **3차 미팅 결과**(`docs/3차 미팅 요약.md`)와 **기능명세서 v1.1**에 맞춰 전면 개정한 단일 계획서입니다.
> v2.1 대비 **매칭/점수 로직 교체, 포인트 경제·회원등급·지정배차·필터·관리자웹** 등이 신규 반영되었습니다.
> v2.1의 일부 상세(FCM Edge Function 전체 코드, 락 순서 가이드, P1/P2 SQL)는 변경이 없으므로 `01_dev_plan_v2.1.md` 해당 섹션을 그대로 참조합니다.

---

## 0. v2.1 → v3.0 변경 개요

| # | 영역 | v2.1 | v3.0 |
|---|------|------|------|
| 1 | 매칭 점수 | 별점 70% + **거리 30%** (PostGIS) | **별점 100% 베이지안** (거리·GPS 폐지) |
| 2 | 매칭 우선순위 | 프리미엄권 / 우선+별점 / 일반 | **프리미엄명단 / 평점(관리자) / 일감횟수(발주이력) / 별점 / 선착순** (5단계, 2026-06-14 미팅) |
| 3 | 프리미엄 | 소모성 배차권(테이블) | **명단 플래그**(`profiles.is_premium`), 하루1건 면제 |
| 4 | 발주 이력 | 없음 | **직전 3개월 매칭성사 일반발주 건수**(지정배차 제외)로 우선순위 가산 |
| 5 | 지정배차 | 없음 | 신규(`jobs.is_designated`+비번/회원번호, **지정 윈도우 5분 → 미수락 시 일반 선착순 전환**) |
| 6 | 포인트 경제 | 없음 | **충전/차감/소개비/수수료/인출** 전체 신규 |
| 7 | 회원 등급 | 단일 | 정회원/준회원(박탈)/승인대기 + 프리미엄 플래그 + 관리자 |
| 8 | 필터 | 장비만 | **지역+장비**, 알림도 조건 일치만 |
| 9 | 관리자 웹 | 언급만 | 회원승인·프리미엄명단·포인트·세무export·모니터링 |
| 10 | 운영 | — | 오류 모니터링(Sentry)·구조화 로깅(원격 디버깅 대비) |

> ⚠️ **거리/GPS 관련 v2.1 코드는 전부 폐기됩니다:** `calculate_match_score`의 거리 항, `applicant_location`, `idx_jobs_location`(GIST), 정렬 "거리순", `locationProvider` 등.

> 📌 **2026-06-14 미팅 반영:** ① **평점(관리자 점수, 기본 50·±1)** 신설 → 매칭 **2순위**(사용자엔 50점만 노출, 우선순위 용도 비공개). ② **사진 인증**(도착·작업·종료 각 1점+완비 보너스 1점) **40점 = 우선배차권**, 사진 **1년 보관 후 관리자 백업**. ③ **기종 불일치** 지원 **차단 폐지** → 안내 팝업+기록. ④ **앱 사용 가이드** 표시. ⑤ 우선배차권 **유효기간 조사 후 확정**, **우선배차권 유료 판매**(프리미엄 아님)는 1년 후 plan.

---

## 1. 앱 개요 및 기술 스택

### 1.1 앱 목적
중장비(포크레인 등) 기사 간 일감 등록·배차 매칭 플랫폼. 단일 유저 타입이 발주와 배차를 모두 수행.

### 1.2 기술 스택

| 구분 | 기술 |
|------|------|
| Frontend | Flutter (iOS / Android) |
| 상태 관리 | Riverpod / 라우팅 go_router |
| Backend / DB | Supabase (PostgreSQL + Realtime + Auth + Storage) |
| 결제 | **토스페이먼츠 가상계좌** (포인트 충전, 입금 webhook) |
| 지도 | 카카오맵 (위치 표시용 / 매칭에는 미사용) |
| 푸시 | FCM + Supabase Edge Functions |
| 스케줄러 | pg_cron |
| 오류 모니터링 | **Sentry**(또는 동급) + 구조화 로깅 |
| 관리자 | **PC 웹 (별도 산출물)** |

> PostGIS는 1차에서 **선택**입니다. 매칭에 거리를 쓰지 않으므로 지도 표시는 위경도 컬럼(`double precision`)으로 충분합니다. 향후 "지역 기반 통계/지도 밀집도"가 필요해지면 PostGIS를 도입합니다.

---

## 2. Supabase DB 스키마

### 2.1 테이블 정의

#### `profiles` — 기사 프로필 / 회원 상태

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid PK, FK → auth.users | Auth UID |
| member_no | text UNIQUE NOT NULL | 사람이 읽는 회원번호 — **6자리 숫자**(예 `204815`, 알파벳 없음·현장 소통 용이). 지정배차/고객센터 식별 |
| name | text NOT NULL | 이름 |
| phone | text UNIQUE NOT NULL | 전화번호(로그인 ID) |
| bank_account | text | 사업자 계좌번호 (매칭 후 공개 / 인출 지급) |
| business_email | text | 사업자 이메일 |
| business_info | jsonb | 사업자 등록정보 |
| license_type | text | 자격증 종류 |
| equipment_category | text FK → equipment_categories(code) | 카테고리(mini/track/tire) — `docs/13_장비_마스터데이터.md` |
| equipment_model | text | 모델코드(008/02LC/03W…). FK (equipment_category, equipment_model) → equipment_models |
| rating_sum | int DEFAULT 0 | 별점 누적합 |
| rating_count | int DEFAULT 0 | 별점 횟수 |
| point_balance | int DEFAULT 0 | 포인트 잔액(원자적 갱신은 RPC) |
| membership_status | text DEFAULT 'pending' CHECK ('pending','active','suspended') | 승인대기/정회원/준회원(박탈) |
| is_premium | boolean DEFAULT false | **프리미엄 배차인 명단 여부(비공개)** |
| admin_score | int DEFAULT 50 | **평점(매칭 2순위·관리자 ±1 조정)** — 사용자엔 50점 표시, *우선순위 용도는 비노출* |
| cert_points | int DEFAULT 0 | 사진 인증 누적 점수(40점당 우선배차권 1장·발급 시 감산) |
| completed_as_worker | int DEFAULT 0 | 수행 일감 수(통계) |
| created_at | timestamptz DEFAULT now() | |

> 평균 별점 = `rating_sum / rating_count`. 유효별점은 베이지안(2.5.1)으로 계산.

#### `equipment_categories` / `equipment_models` — 장비 마스터

> 장비 분류·모델코드의 단일 출처. 데이터·매칭 규칙 상세는 **`docs/13_장비_마스터데이터.md`**. 모델 추가는 이 테이블 시드만 수정(CHECK 하드코딩 금지).

```sql
-- 카테고리: mini(미니굴삭기) / track(굴삭기-트랙) / tire(굴삭기-타이어)
CREATE TABLE public.equipment_categories (
  code        text PRIMARY KEY,
  label       text NOT NULL,
  sort_order  int  NOT NULL
);

-- 모델: 카테고리 내 sort_order 오름차순(작은→큰 장비). 매칭 '이상(≥)' 기준값.
CREATE TABLE public.equipment_models (
  category_code text NOT NULL REFERENCES equipment_categories(code),
  code          text NOT NULL,           -- '008','02LC','03W' ...
  label         text NOT NULL,
  sort_order    int  NOT NULL,
  is_active     boolean DEFAULT true,
  PRIMARY KEY (category_code, code)
);
```

> `profiles(equipment_category, equipment_model)` 및 `jobs(required_category, required_model)`는 `(category_code, code)` 복합 FK로 무결성 보장.

#### `member_documents` — 가입 서류 5종

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid PK | |
| user_id | uuid FK → profiles.id | |
| doc_type | text CHECK ('license','equipment_reg','insurance','business_reg','photo') | 서류 종류 |
| original_path | text | 원본 파일 경로(관리자 검수용, 발주자 비공개) |
| masked_path | text | **민감정보 마스킹된 공개용 파일**(관리자 처리) |
| created_at | timestamptz DEFAULT now() | |

> Storage는 **비공개 버킷** + RPC/서명URL로만 접근. 발주자에게는 `masked_path`만 노출.

#### `jobs` — 일감

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid PK | |
| job_no | text UNIQUE NOT NULL | **표시용 일감번호** `YYMMDD-NNNN`(날짜+랜덤 4자리 **숫자**, 순차 아님 · 현장 소통/검색용) |
| poster_id | uuid FK → profiles.id NOT NULL | 발주 기사 |
| work_date | timestamptz NOT NULL | 작업 일시 |
| region_code | text NOT NULL | **지역 코드(필터용)** |
| region_name | text NOT NULL | 지역명 |
| lat / lng | double precision | 표시용 좌표(매칭 미사용) |
| address | text | 주소 |
| description | text NOT NULL | 작업 정보 |
| job_type_tags | text[] | 작업 종류 태그(가위/뿌레카/코아 등) |
| required_category | text FK → equipment_categories(code) | 요구 카테고리(**대표 옵션** — 추가 허용 장비는 `job_equipment_options`, OR 매칭) |
| required_model | text | 요구 **최소** 모델코드(NULL=카테고리 전체). FK (required_category, required_model) → equipment_models. 다중 허용 시 대표(첫) 옵션 |
| amount | int NOT NULL | 일감 금액(소개비 10% 기준) |
| payment_method | text | 직수/싸인지/직접청구/현금 |
| memo | text | |
| **is_designated** | boolean DEFAULT false | **지정배차 여부** |
| **designate_password** | text | 지정배차 비밀번호(해시 저장) |
| **designate_window_expires** | timestamptz | 지정 윈도우 만료시각(미수락 시 cron②가 일반 선착순 open 전환). status에 `designated_window` 추가 |
| **designate_target_id** | uuid FK → profiles.id | 지정 대상(회원번호로 지정 시) |
| status | text DEFAULT 'open' | (enum 아래) |
| priority_window_ends_at | timestamptz | 우선배차 윈도우 마감 |
| matched_worker_id | uuid FK → profiles.id | 배차된 기사 |
| matched_at | timestamptz | 매칭 시각 |
| photo_points | int DEFAULT 0 | 이 일감이 적립한 사진 인증 점수(재업로드 중복 적립 방지) |
| created_at | timestamptz DEFAULT now() | |

**status enum:** `open`, `priority_window`, `designated_window`, `matched`, `completed`, `cancelled_by_poster`, `cancelled_by_worker`, `expired`

#### `job_equipment_options` — 일감 허용 장비 (다중·OR 매칭)

| 컬럼 | 타입 | 설명 |
|------|------|------|
| job_id | uuid FK → jobs.id ON DELETE CASCADE | |
| category | text FK → equipment_categories(code) | 허용 카테고리 |
| min_model | text | 허용 **최소** 모델코드(이상 매칭). NULL=카테고리 전체. FK (category, min_model) → equipment_models |
| PK | (job_id, category, COALESCE(min_model,'')) | |

> 한 일감에 **여러 허용 장비**를 등록(예: 미니 035 · 중대형 02 · 중대형 03). 매칭은 **OR** — 기사 보유 장비가 옵션 중 하나와 (카테고리 일치 + 모델 ≥ min_model)이면 성립. 옵션 1개면 기존 단일 지정과 동일. `jobs.required_category/required_model`은 **대표(요약·인덱스)** 옵션으로 유지하며, 우선배차 윈도우 개시 판정(2.5.3)·발주이력·apply 매칭은 모두 이 옵션 집합(대표+추가) 기준으로 평가(옵션은 일감 생성과 동일 트랜잭션에 삽입).

#### `priority_tickets` — 우선 배차권 (v2.1 유지)

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid PK | |
| owner_id | uuid FK → profiles.id | 보유 기사 |
| source | text CHECK ('post','designated_bonus','photo_cert','admin') | 발급 출처(photo_cert=사진인증 40점) |
| source_job_id | uuid FK → jobs.id NULL | 발행 근거 일감(있을 때) |
| expires_at | timestamptz NOT NULL | 생성 후 30일 |
| used_at | timestamptz | 사용 시각(NULL=미사용) |
| created_at | timestamptz DEFAULT now() | |

#### `job_applications` — 지원

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid PK | |
| job_id | uuid FK → jobs.id | |
| applicant_id | uuid FK → profiles.id | |
| ticket_id | uuid FK → priority_tickets.id NULL | 사용한 우선배차권(일반/지정 시 NULL) |
| is_priority | boolean DEFAULT false | 우선 지원 여부 |
| effective_rating | numeric(6,4) | **베이지안 유효별점(매칭 기준 점수)** |
| poster_post_count | int DEFAULT 0 | **지원자의 직전 3개월 발주이력(우선순위용 스냅샷)** |
| equipment_mismatch | boolean DEFAULT false | **본인 인증 기종과 불일치 지원 여부**(차단 안 함·안내 후 기록, 모니터링용) |
| status | text DEFAULT 'pending' CHECK ('pending','accepted','rejected') | |
| created_at | timestamptz DEFAULT now() | |
| UNIQUE(job_id, applicant_id) | | 중복 지원 방지 |

> ⚠️ v2.1의 `applicant_location`, `score`(거리 포함)는 제거. `effective_rating` + `poster_post_count`로 대체.

#### `point_transactions` — 포인트 원장(세무·정산 핵심)

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid PK | |
| user_id | uuid FK → profiles.id | |
| type | text CHECK ('charge','vat','pg_fee','daily_fee','referral_in','referral_out','platform_fee','withdraw','admin_adjust') | 거래 유형 |
| amount | int NOT NULL | 증감(+/-) |
| balance_after | int NOT NULL | 거래 후 잔액(감사 추적) |
| ref_job_id | uuid FK → jobs.id NULL | 관련 일감 |
| ref_charge_id | uuid NULL | 관련 충전/인출 |
| memo | text | |
| created_at | timestamptz DEFAULT now() | |

#### `charges` — 충전(가상계좌)

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid PK | |
| user_id | uuid FK → profiles.id | |
| point_amount | int NOT NULL | 발급 포인트(=충전 원금) |
| vat | int NOT NULL | 부가세 10% |
| pg_fee | int NOT NULL | PG 수수료(기본 440, 설정값) — **입금액엔 미포함, 발급 후 포인트에서 차감** |
| total_deposit | int NOT NULL | **입금 요청 총액 = point + vat** (수수료 제외) |
| vaccount_no | text | 발급된 가상계좌 |
| status | text CHECK ('pending','paid','expired','cancelled') | |
| paid_at | timestamptz | 입금통보 시각 |
| created_at | timestamptz DEFAULT now() | |

#### `withdrawals` — 인출(환급) 신청

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid PK | |
| user_id | uuid FK → profiles.id | |
| amount | int NOT NULL | 인출 포인트 |
| status | text CHECK ('requested','approved','paid','rejected') | |
| bank_account | text | 지급 계좌(스냅샷) |
| processed_by | uuid | 처리 관리자 |
| created_at / processed_at | timestamptz | |

> **인출 범위(확정):** **충전금 포함 전 잔액** 인출 가능. 별도 `withdrawable_balance` 분리 불필요(단일 `point_balance` 기준). 인출은 **본인 명의 계좌 한정 + 관리자 승인 게이트 + 원장 기록**. 사업자가 **선불업(선불전자지급수단) 등록**을 진행하므로 그 전제로 구현.

#### `app_settings` — 운영 설정 상수(코드 수정 없이 정책 변경)

| key | 예시값 | 설명 |
|-----|--------|------|
| priority_window_seconds | 30 | 우선배차 윈도우 초 |
| daily_fee | 1000 | 하루 차감 포인트 |
| referral_rate | 0.10 | 소개비율 |
| platform_fee | 0 | 매칭 건당 플랫폼 수수료(추후 1000) |
| pg_fee | 440 | 충전 PG 수수료 |
| vat_rate | 0.10 | 부가세율 |
| bayes_c | 3.5 | 베이지안 사전평균 |
| bayes_m | 5 | 베이지안 가중치 |
| designated_bonus_per | 3 | 지정배차 N건당 우선배차권 1장(발주자·매칭성사 기준) |
| designated_window_seconds | 300 | **지정배차 윈도우(5분)** — 미수락 시 일반 선착순 전환 |
| admin_score_default | 50 | **평점 기본값**(관리자 ±1로 조정, 매칭 2순위) |
| photo_point_per_phase | 1 | 사진 단계(도착/작업/종료)당 점수 |
| photo_complete_bonus | 1 | 3종 완비 보너스 |
| photo_points_per_ticket | 40 | 누적 N점당 우선배차권 1장 |
| photo_retention_days | 365 | 사진 보관일(이후 관리자 장기보관 백업) |
| ticket_expiry_days | 30 | 우선배차권 유효기간 — **조사 후 확정 예정**(현재 30일 잠정) |

#### `device_tokens` / `notifications` — v2.1 유지
- `notifications.type`에 `point_low`, `membership_suspended`, `charge_paid`, `withdraw_processed`, `ticket_granted`(사진인증 우선배차권 지급) 추가.
- 사용자 알림 필터용: `profiles`에 `notify_regions text[]`, `notify_equipment jsonb`(선택 지역/장비) 추가.

#### `user_blocks` — 사용자 차단

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid PK | |
| blocker_id | uuid FK → profiles.id NOT NULL | 차단을 건 사람 |
| blocked_id | uuid FK → profiles.id NOT NULL | 차단당한 사람 |
| created_at | timestamptz DEFAULT now() | |
| UNIQUE(blocker_id, blocked_id) | | 중복 차단 방지 |

> 차단은 단방향(blocker→blocked)으로 저장하되, **효과는 양방향**(목록 비노출 + 상호 매칭 차단). 조회 시 "내가 차단했거나 나를 차단한" 관계를 모두 고려.

#### `job_photos` — 일감 사진 인증 (현장도착/작업/종료)

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid PK | |
| job_id | uuid FK → jobs.id NOT NULL | |
| uploader_id | uuid FK → profiles.id NOT NULL | 배차받은 기사 |
| phase | text CHECK ('arrival','work','done') NOT NULL | 현장도착/작업/작업종료 |
| storage_path | text NOT NULL | 비공개 버킷 경로(서명URL) |
| taken_at | timestamptz DEFAULT now() | 촬영/업로드 시각 |
| created_at | timestamptz DEFAULT now() | |

> 점수: phase당 `photo_point_per_phase`(1점), 3종 완비 시 `photo_complete_bonus`(+1) → 일감 완비=4점. 누적 `photo_points_per_ticket`(40점)마다 우선배차권 1장. **보관 `photo_retention_days`(1년) 경과분은 관리자 장기보관 백업 후 정리**(2.6 ⑦). 상세 설계 `docs/14_현장사진인증_우선배차_제안`.

#### `admin_score_log` — 평점(관리자 점수) 변경 이력(감사)

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | uuid PK | |
| user_id | uuid FK → profiles.id NOT NULL | 대상 회원 |
| admin_id | uuid FK → profiles.id | 변경한 관리자 |
| delta | int NOT NULL | 증감(+1/-1) |
| score_after | int NOT NULL | 변경 후 평점 |
| reason | text | 사유 |
| created_at | timestamptz DEFAULT now() | |

> 평점은 **운영 비공개 우선순위 레버**이므로 변경 이력을 남겨 분쟁·감사에 대비.

### 2.2 뷰 / 함수 — 정보 분리

```sql
-- 공개 기본 정보(유효별점은 계산 함수로 제공, is_premium·발주이력 비노출)
CREATE VIEW public.profiles_public AS
SELECT id, member_no, name, equipment_category, equipment_model,
       rating_sum, rating_count
FROM profiles;

-- 모델 정렬값(카테고리 내 톤급 순). 매칭 '이상(≥)' 판정에 사용.
CREATE OR REPLACE FUNCTION equipment_model_rank(p_category text, p_model text)
RETURNS int LANGUAGE sql STABLE AS $$
  SELECT sort_order FROM equipment_models
  WHERE category_code = p_category AND code = p_model;
$$;

-- 매칭 상대 연락처 (v2.1 유지)
CREATE OR REPLACE FUNCTION get_matched_contact(p_job_id uuid)
RETURNS TABLE(name text, phone text, bank_account text)
SECURITY DEFINER AS $$ ... $$;  -- v2.1과 동일

-- 매칭된 기사 서류(마스킹 버전) 열람: 발주자 전용
CREATE OR REPLACE FUNCTION get_matched_worker_documents(p_job_id uuid)
RETURNS TABLE(doc_type text, masked_url text)
SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT d.doc_type, storage_signed_url(d.masked_path)
  FROM member_documents d
  JOIN jobs j ON j.id = p_job_id AND j.status IN ('matched','completed')
  WHERE j.poster_id = auth.uid()
    AND d.user_id = j.matched_worker_id
    AND d.masked_path IS NOT NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 2.3 인덱스 (거리 GIST 제거)

```sql
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_work_date ON jobs(work_date);
CREATE INDEX idx_jobs_region ON jobs(region_code);
CREATE INDEX idx_jobs_required ON jobs(required_category, required_model);
CREATE INDEX idx_jobs_poster ON jobs(poster_id);
CREATE INDEX idx_jobs_worker ON jobs(matched_worker_id);
-- 발주이력 카운트(직전 3개월 매칭성사 일반발주)
CREATE INDEX idx_jobs_poster_matched ON jobs(poster_id, matched_at)
  WHERE status IN ('matched','completed') AND is_designated = false;

CREATE INDEX idx_tickets_owner_unused
  ON priority_tickets(owner_id, expires_at) WHERE used_at IS NULL;

CREATE INDEX idx_applications_job ON job_applications(job_id);
CREATE INDEX idx_applications_applicant ON job_applications(applicant_id);

CREATE INDEX idx_jobs_worker_date ON jobs(matched_worker_id, work_date)
  WHERE status IN ('matched','completed');
CREATE INDEX idx_jobs_poster_date ON jobs(poster_id, work_date);

CREATE INDEX idx_point_tx_user ON point_transactions(user_id, created_at DESC);
CREATE INDEX idx_notifications_recipient ON notifications(recipient_id, created_at DESC);
CREATE INDEX idx_device_tokens_user ON device_tokens(user_id);
```

### 2.4 RLS 정책 (핵심 변경점)

```sql
-- jobs SELECT: 열린/관련 일감 + 지정배차도 열람 허용(지원만 제한), 차단 관계는 비노출
CREATE POLICY "일감 열람"
  ON jobs FOR SELECT
  USING (
    poster_id = auth.uid()                    -- 내 일감
    OR matched_worker_id = auth.uid()         -- 내가 배차받은 일감
    OR id IN (SELECT job_id FROM job_applications WHERE applicant_id = auth.uid())
    OR (
      status IN ('open','priority_window')    -- 지정배차 포함 공개 일감
      AND poster_id NOT IN (                  -- 차단 양방향 비노출
        SELECT blocked_id FROM user_blocks WHERE blocker_id = auth.uid()
        UNION
        SELECT blocker_id FROM user_blocks WHERE blocked_id = auth.uid()
      )
    )
  );

-- user_blocks: 본인이 건 차단만 조회/관리
ALTER TABLE user_blocks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "본인 차단목록 관리" ON user_blocks
  FOR ALL USING (blocker_id = auth.uid()) WITH CHECK (blocker_id = auth.uid());

-- point_transactions / charges / withdrawals: 본인 조회만, 변경은 RPC
CREATE POLICY "본인 포인트내역 조회" ON point_transactions
  FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "본인 충전내역 조회" ON charges
  FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "본인 인출내역 조회" ON withdrawals
  FOR SELECT USING (user_id = auth.uid());

-- member_documents: 본인만 직접 조회. 발주자 열람은 get_matched_worker_documents RPC로만.
CREATE POLICY "본인 서류 조회" ON member_documents
  FOR SELECT USING (user_id = auth.uid());
```

> 나머지 RLS(profiles/priority_tickets/job_applications/notifications/device_tokens)는 v2.1 패턴 유지. 모든 포인트·매칭·지정배차 로직은 **SECURITY DEFINER RPC**로만 변경.

### 2.5 Database Functions

#### 2.5.1 유효별점(베이지안) — 거리 폐지

```sql
CREATE OR REPLACE FUNCTION effective_rating(p_sum int, p_count int)
RETURNS numeric AS $$
DECLARE c numeric; m numeric;
BEGIN
  SELECT (value)::numeric INTO c FROM app_settings WHERE key='bayes_c';
  SELECT (value)::numeric INTO m FROM app_settings WHERE key='bayes_m';
  RETURN ROUND(((p_sum + c*m) / (p_count + m))::numeric, 4);
END;
$$ LANGUAGE plpgsql STABLE;
```

#### 2.5.2 발주 이력 카운트 (직전 3개 캘린더월, 지정배차 제외)

```sql
CREATE OR REPLACE FUNCTION poster_recent_post_count(p_user_id uuid)
RETURNS int AS $$
  SELECT count(*)::int FROM jobs
  WHERE poster_id = p_user_id
    AND is_designated = false
    AND status IN ('matched','completed')
    AND matched_at >= date_trunc('month', now()) - interval '3 months'
    AND matched_at <  date_trunc('month', now());   -- 당월 제외, 직전 3개월
$$ LANGUAGE sql STABLE;
```

#### 2.5.3 일감 생성 트리거 (지정배차 분기 + 배차권 발급 규칙)

```sql
CREATE OR REPLACE FUNCTION on_job_created()
RETURNS TRIGGER AS $$
DECLARE v_has_holder boolean; v_win int;
BEGIN
  IF NEW.is_designated THEN
    -- 지정배차: 우선배차권 자동발급 없음. 지정 윈도우(designated_window_seconds, 기본 5분) 동안
    -- 지정자(비번/회원번호 일치)만 지원, 다른 유저는 열람만. 미수락 시 cron②가 일반 선착순(open)으로 전환.
    NEW.status := 'designated_window';
    NEW.designate_window_expires :=
      now() + (SELECT (value)::int FROM app_settings WHERE key='designated_window_seconds') * interval '1 second';
    RETURN NEW;
  END IF;

  -- 일반 발주: 등록자에게 우선배차권 1장 발급
  INSERT INTO priority_tickets(owner_id, source, source_job_id, expires_at)
  VALUES (NEW.poster_id, 'post', NEW.id, now() + interval '30 days');

  -- 조건 맞는 우선배차권 보유자 or 프리미엄 배차인 존재 여부
  SELECT EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id <> NEW.poster_id
      AND p.membership_status = 'active'
      AND (NEW.required_category IS NULL OR (
            p.equipment_category = NEW.required_category
            AND (NEW.required_model IS NULL
                 OR equipment_model_rank(p.equipment_category, p.equipment_model)
                    >= equipment_model_rank(NEW.required_category, NEW.required_model))
          ))
      AND (
        p.is_premium = true
        OR EXISTS (SELECT 1 FROM priority_tickets pt
                   WHERE pt.owner_id = p.id AND pt.used_at IS NULL AND pt.expires_at > now())
      )
  ) INTO v_has_holder;

  IF v_has_holder THEN
    SELECT (value)::int INTO v_win FROM app_settings WHERE key='priority_window_seconds';
    NEW.status := 'priority_window';
    NEW.priority_window_ends_at := now() + make_interval(secs => v_win);
  ELSE
    NEW.status := 'open';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

#### 2.5.4 우선 지원 RPC (포인트 검증 + 하루1건(수락일 기준) + 프리미엄)

핵심 변경:
- 거리/위치 인자 제거, `effective_rating`·`poster_post_count` 스냅샷 저장.
- **프리미엄 배차인은 우선배차권 없이도 지원 가능**(티켓 미차감).
- **하루 1건 = 매칭 수락일 기준**이므로 *지원* 시점이 아닌 *채택(finalize)* 시점에 최종 검증(아래 2.5.6). 지원 시에는 사전 안내만.
- 소개비/수수료 **사전 잔액 검증**(부족 시 `INSUFFICIENT_POINT`).

```sql
CREATE OR REPLACE FUNCTION apply_with_priority(
  p_job_id uuid, p_applicant_id uuid, p_force_apply boolean DEFAULT false
) RETURNS jsonb AS $$
DECLARE
  v_job jobs; v_p profiles; v_ticket uuid; v_need int; v_app uuid;
  v_eq_mismatch boolean;
BEGIN
  SELECT * INTO v_job FROM jobs WHERE id = p_job_id FOR UPDATE;
  IF v_job IS NULL THEN RAISE EXCEPTION 'JOB_NOT_FOUND'; END IF;
  IF v_job.is_designated THEN RAISE EXCEPTION 'JOB_UNAVAILABLE'; END IF;
  IF v_job.poster_id = p_applicant_id THEN RAISE EXCEPTION 'SELF_APPLY'; END IF;
  IF v_job.status <> 'priority_window' THEN RAISE EXCEPTION 'JOB_UNAVAILABLE'; END IF;
  IF EXISTS (SELECT 1 FROM job_applications WHERE job_id=p_job_id AND applicant_id=p_applicant_id)
    THEN RAISE EXCEPTION 'DUPLICATE_APPLICATION'; END IF;

  SELECT * INTO v_p FROM profiles WHERE id = p_applicant_id;
  IF v_p.membership_status <> 'active' THEN RAISE EXCEPTION 'MEMBERSHIP_SUSPENDED'; END IF;

  -- 장비 조건: 차단하지 않고 '불일치 여부'만 판정하여 기록 (안내 팝업은 클라이언트, 모니터링/제재용)
  -- (p_force_apply = 사용자가 안내 팝업에서 '그래도 지원' 확인했다는 의미)
  -- 허용 장비 옵션(대표 required_* + job_equipment_options) 중 하나라도 만족하면 일치, 아니면 불일치.
  v_eq_mismatch := NOT (
       ( v_job.required_category IS NULL
         OR ( v_p.equipment_category = v_job.required_category
              AND ( v_job.required_model IS NULL
                    OR equipment_model_rank(v_p.equipment_category, v_p.equipment_model)
                       >= equipment_model_rank(v_job.required_category, v_job.required_model) ) ) )
    OR EXISTS (
         SELECT 1 FROM job_equipment_options o
         WHERE o.job_id = v_job.id
           AND o.category = v_p.equipment_category
           AND ( o.min_model IS NULL
                 OR equipment_model_rank(v_p.equipment_category, v_p.equipment_model)
                    >= equipment_model_rank(o.category, o.min_model) ) ) );

  -- 소개비+플랫폼 수수료 사전 잔액 검증
  v_need := ceil(v_job.amount * (SELECT (value)::numeric FROM app_settings WHERE key='referral_rate'))
            + (SELECT (value)::int FROM app_settings WHERE key='platform_fee');
  IF v_p.point_balance < v_need THEN RAISE EXCEPTION 'INSUFFICIENT_POINT'; END IF;

  -- 프리미엄이 아니면 우선배차권 1장 차감
  IF NOT v_p.is_premium THEN
    UPDATE priority_tickets SET used_at = now()
    WHERE id = (SELECT id FROM priority_tickets
                WHERE owner_id=p_applicant_id AND used_at IS NULL AND expires_at>now()
                ORDER BY expires_at ASC LIMIT 1 FOR UPDATE SKIP LOCKED)
    RETURNING id INTO v_ticket;
    IF v_ticket IS NULL THEN RAISE EXCEPTION 'NO_TICKET'; END IF;
  END IF;

  INSERT INTO job_applications(job_id, applicant_id, ticket_id, is_priority,
      effective_rating, poster_post_count, equipment_mismatch, status)
  VALUES (p_job_id, p_applicant_id, v_ticket, true,
      effective_rating(v_p.rating_sum, v_p.rating_count),
      poster_recent_post_count(p_applicant_id), v_eq_mismatch, 'pending')
  RETURNING id INTO v_app;

  RETURN jsonb_build_object('application_id', v_app, 'ticket_used', v_ticket);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

#### 2.5.5 일반 지원 RPC (선착순 즉시 매칭 + 소개비 정산)

`apply_general`은 v2.1 골격 유지하되: 위치 인자 제거, 멤버십/포인트 검증 추가, 매칭 즉시 **소개비/수수료 정산**(2.5.7) 호출, 하루1건(수락일) 검증.

#### 2.5.6 우선배차 마감 처리 RPC (새 우선순위 정렬)

```sql
CREATE OR REPLACE FUNCTION finalize_priority_match(p_job_id uuid)
RETURNS jsonb AS $$
DECLARE v_job jobs; v_winner job_applications;
BEGIN
  SELECT * INTO v_job FROM jobs
  WHERE id=p_job_id AND status='priority_window' FOR UPDATE SKIP LOCKED;
  IF v_job IS NULL THEN RETURN jsonb_build_object('status','already_processed'); END IF;

  -- 우선순위: 프리미엄 → 평점(관리자) → 일감횟수(발주이력) → 별점 → 선착순
  -- (하루1건: 당일 이미 수락한 지원자는 후보에서 제외)
  SELECT a.* INTO v_winner
  FROM job_applications a
  JOIN profiles p ON p.id = a.applicant_id
  WHERE a.job_id = p_job_id AND a.is_priority AND a.status='pending'
    AND NOT EXISTS (                         -- 하루 1건(수락일 기준)
      SELECT 1 FROM jobs j2
      WHERE j2.matched_worker_id = a.applicant_id
        AND j2.matched_at::date = now()::date
    OR_PREMIUM_EXEMPT(p.is_premium))         -- (의사코드) 프리미엄은 면제
  ORDER BY
    p.is_premium DESC,                       -- 1) 프리미엄 명단 최우선
    p.admin_score DESC,                      -- 2) 평점(관리자 점수, 기본 50·±1)
    (a.poster_post_count > 0) DESC,          -- 3) 일감횟수(발주이력) 있음 우선
    a.poster_post_count DESC,                --    건수 많은 순
    a.effective_rating DESC,                 -- 4) 별점(발주자 평가)
    a.created_at ASC                         -- 선착순
  LIMIT 1;

  IF v_winner IS NULL THEN
    UPDATE jobs SET status='open', priority_window_ends_at=NULL WHERE id=p_job_id;
    RETURN jsonb_build_object('status','opened','job_id',p_job_id);
  END IF;

  UPDATE jobs SET status='matched', matched_worker_id=v_winner.applicant_id, matched_at=now()
  WHERE id=p_job_id;
  UPDATE job_applications SET status='accepted' WHERE id=v_winner.id;
  UPDATE job_applications SET status='rejected'
  WHERE job_id=p_job_id AND id<>v_winner.id AND status='pending';

  -- 탈락자 배차권 반환(만료일 최소 7일 보장)
  UPDATE priority_tickets SET used_at=NULL,
    expires_at=GREATEST(expires_at, now()+interval '7 days')
  WHERE id IN (SELECT ticket_id FROM job_applications
               WHERE job_id=p_job_id AND status='rejected' AND ticket_id IS NOT NULL);

  -- 소개비/플랫폼 수수료 정산
  PERFORM settle_referral(p_job_id, v_winner.applicant_id, v_job.poster_id);

  RETURN jsonb_build_object('status','matched','job_id',p_job_id,
    'winner_id',v_winner.applicant_id,'poster_id',v_job.poster_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

> ⚠️ 위 `OR_PREMIUM_EXEMPT`는 **의사코드**입니다. 실제로는 하루1건 제외 조건을 `(p.is_premium OR NOT EXISTS(...))` 형태로 작성합니다(구현 시 정리). 프리미엄은 하루1건 면제이므로 후보 제외 대상에서 빠져야 합니다.

#### 2.5.7 소개비/수수료 정산 (락 순서: profiles는 마지막, 포인트는 RPC 원자성)

```sql
CREATE OR REPLACE FUNCTION settle_referral(
  p_job_id uuid, p_worker uuid, p_poster uuid
) RETURNS void AS $$
DECLARE v_amount int; v_ref int; v_plat int; v_wbal int; v_pbal int;
BEGIN
  SELECT amount INTO v_amount FROM jobs WHERE id=p_job_id;
  v_ref  := ceil(v_amount * (SELECT (value)::numeric FROM app_settings WHERE key='referral_rate'));
  v_plat := (SELECT (value)::int FROM app_settings WHERE key='platform_fee');

  -- 기사 B 차감(소개비 + 플랫폼 수수료)
  UPDATE profiles SET point_balance = point_balance - (v_ref + v_plat)
  WHERE id=p_worker AND point_balance >= (v_ref + v_plat)
  RETURNING point_balance INTO v_wbal;
  IF v_wbal IS NULL THEN RAISE EXCEPTION 'INSUFFICIENT_POINT'; END IF;

  -- 발주자 A 가산(소개비)
  UPDATE profiles SET point_balance = point_balance + v_ref
  WHERE id=p_poster RETURNING point_balance INTO v_pbal;

  INSERT INTO point_transactions(user_id,type,amount,balance_after,ref_job_id)
  VALUES (p_worker,'referral_out',-v_ref,v_wbal + v_plat,p_job_id),
         (p_poster,'referral_in', v_ref,v_pbal,p_job_id);
  IF v_plat > 0 THEN
    INSERT INTO point_transactions(user_id,type,amount,balance_after,ref_job_id)
    VALUES (p_worker,'platform_fee',-v_plat,v_wbal,p_job_id);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

#### 2.5.8 지정배차 지원 RPC (비밀번호/회원번호)

```sql
CREATE OR REPLACE FUNCTION apply_designated(
  p_job_id uuid, p_applicant_id uuid, p_password text DEFAULT NULL
) RETURNS jsonb AS $$
DECLARE v_job jobs; v_p profiles; v_cnt int;
BEGIN
  SELECT * INTO v_job FROM jobs WHERE id=p_job_id AND status='open'
    AND is_designated=true FOR UPDATE SKIP LOCKED;
  IF v_job IS NULL THEN RAISE EXCEPTION 'JOB_UNAVAILABLE'; END IF;

  -- 지정 검증: 회원번호 매칭 또는 비밀번호 일치
  IF NOT (
    (v_job.designate_target_id IS NOT NULL AND v_job.designate_target_id = p_applicant_id)
    OR (v_job.designate_password IS NOT NULL AND crypt(p_password, v_job.designate_password) = v_job.designate_password)
  ) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  SELECT * INTO v_p FROM profiles WHERE id=p_applicant_id;
  IF v_p.membership_status <> 'active' THEN RAISE EXCEPTION 'MEMBERSHIP_SUSPENDED'; END IF;
  -- 지정배차는 하루1건/우선배차권 미적용

  UPDATE jobs SET status='matched', matched_worker_id=p_applicant_id, matched_at=now()
  WHERE id=p_job_id;
  INSERT INTO job_applications(job_id,applicant_id,is_priority,status)
  VALUES (p_job_id,p_applicant_id,false,'accepted');

  PERFORM settle_referral(p_job_id, p_applicant_id, v_job.poster_id);

  -- 발주자 보상: 매칭 성사된 지정배차 누적 N건당 우선배차권 1장
  SELECT count(*) INTO v_cnt FROM jobs
  WHERE poster_id=v_job.poster_id AND is_designated=true AND status IN ('matched','completed');
  IF v_cnt % (SELECT (value)::int FROM app_settings WHERE key='designated_bonus_per') = 0 THEN
    INSERT INTO priority_tickets(owner_id,source,source_job_id,expires_at)
    VALUES (v_job.poster_id,'designated_bonus',p_job_id, now()+interval '30 days');
  END IF;

  RETURN jsonb_build_object('status','matched','job_id',p_job_id,'poster_id',v_job.poster_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

> **차단 매칭 가드(공통):** `apply_with_priority`·`apply_general`·`apply_designated` 모두, 지원자와 발주자 간 차단 관계가 있으면 `BLOCKED` 예외로 거절합니다. 표준 가드:
> ```sql
> IF EXISTS (
>   SELECT 1 FROM user_blocks
>   WHERE (blocker_id = p_applicant_id AND blocked_id = v_job.poster_id)
>      OR (blocker_id = v_job.poster_id AND blocked_id = p_applicant_id)
> ) THEN RAISE EXCEPTION 'BLOCKED'; END IF;
> ```
> `finalize_priority_match`의 후보 선정에서도 동일 조건으로 차단 관계 지원자를 제외합니다.

#### 2.5.9 충전 입금 확정 / 일일 차감 / 멤버십 복구

```sql
-- 가상계좌 입금통보 webhook → 포인트 발급 후 PG 수수료 차감
-- 입금액(total_deposit)=원금+부가세. 발급은 원금(point_amount), 그 뒤 pg_fee(440) 포인트 차감.
-- 예: 30,000p 충전(입금 33,000원) → +30,000p 후 -440p → 실 +29,560p
CREATE OR REPLACE FUNCTION confirm_charge(p_charge_id uuid)
RETURNS void AS $$
DECLARE c charges; v_bal int;
BEGIN
  SELECT * INTO c FROM charges WHERE id=p_charge_id AND status='pending' FOR UPDATE;
  IF c IS NULL THEN RETURN; END IF;
  UPDATE charges SET status='paid', paid_at=now() WHERE id=p_charge_id;

  -- 1) 충전 원금 발급
  UPDATE profiles SET point_balance = point_balance + c.point_amount
  WHERE id=c.user_id RETURNING point_balance INTO v_bal;
  INSERT INTO point_transactions(user_id,type,amount,balance_after,ref_charge_id)
  VALUES (c.user_id,'charge',c.point_amount,v_bal,c.id);

  -- 2) PG 수수료 차감(사용자 부담)
  IF c.pg_fee > 0 THEN
    UPDATE profiles SET point_balance = point_balance - c.pg_fee
    WHERE id=c.user_id RETURNING point_balance INTO v_bal;
    INSERT INTO point_transactions(user_id,type,amount,balance_after,ref_charge_id)
    VALUES (c.user_id,'pg_fee',-c.pg_fee,v_bal,c.id);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 멤버십 복구: 충전 후 1000p 납부 시 정회원 전환
CREATE OR REPLACE FUNCTION recover_membership(p_user_id uuid)
RETURNS jsonb AS $$
DECLARE v_fee int; v_bal int;
BEGIN
  SELECT (value)::int INTO v_fee FROM app_settings WHERE key='daily_fee';
  UPDATE profiles SET point_balance = point_balance - v_fee, membership_status='active'
  WHERE id=p_user_id AND membership_status='suspended' AND point_balance >= v_fee
  RETURNING point_balance INTO v_bal;
  IF v_bal IS NULL THEN RAISE EXCEPTION 'INSUFFICIENT_POINT'; END IF;
  INSERT INTO point_transactions(user_id,type,amount,balance_after)
  VALUES (p_user_id,'daily_fee',-v_fee,v_bal);
  RETURN jsonb_build_object('status','active','balance',v_bal);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

> **일일 차감**은 cron(2.6 ①)에서 일괄 처리. 박탈(suspended) 상태에서는 **차감을 멈춤**(전체 차단이므로 부채 누적 없음). 복구 시 그날치 1000p만 납부.

#### 2.5.8 평점(관리자 점수) 조정 RPC — 매칭 2순위 레버

```sql
-- 관리자 전용. profiles.admin_score를 ±1 등으로 조정하고 이력 기록.
CREATE OR REPLACE FUNCTION admin_adjust_score(
  p_user_id uuid, p_delta int, p_reason text
) RETURNS int AS $$
DECLARE v_after int;
BEGIN
  -- 호출자 관리자 검증은 RLS/래퍼에서 (is_admin)
  UPDATE profiles SET admin_score = admin_score + p_delta
  WHERE id = p_user_id RETURNING admin_score INTO v_after;
  INSERT INTO admin_score_log(user_id, admin_id, delta, score_after, reason)
  VALUES (p_user_id, auth.uid(), p_delta, v_after, p_reason);
  RETURN v_after;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

> 사용자에게는 본인 `admin_score`(예 50)만 노출하고 **우선순위 2순위로 쓰인다는 사실은 비공개**. 대부분 50이라 사용자는 의미 없는 지표로 인식.

#### 2.5.9 사진 인증 등록 RPC — 적립 + 40점 시 우선배차권

```sql
-- 락 순서: jobs → profiles → (priority_tickets INSERT) → notifications
CREATE OR REPLACE FUNCTION register_job_photo(
  p_job_id uuid, p_phase text, p_storage_path text
) RETURNS jsonb AS $$
DECLARE
  v_job jobs; v_ppp int; v_bonus int; v_per int;
  v_phases int; v_newpts int; v_delta int; v_after int; v_granted int := 0;
BEGIN
  SELECT * INTO v_job FROM jobs WHERE id = p_job_id FOR UPDATE;
  IF v_job IS NULL OR v_job.matched_worker_id <> auth.uid()
    THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  INSERT INTO job_photos(job_id, uploader_id, phase, storage_path)
  VALUES (p_job_id, auth.uid(), p_phase, p_storage_path);

  SELECT (value)::int INTO v_ppp   FROM app_settings WHERE key='photo_point_per_phase';
  SELECT (value)::int INTO v_bonus FROM app_settings WHERE key='photo_complete_bonus';
  SELECT (value)::int INTO v_per   FROM app_settings WHERE key='photo_points_per_ticket';

  -- 이 일감 점수 재계산(중복 적립 방지)
  SELECT count(DISTINCT phase) INTO v_phases FROM job_photos WHERE job_id = p_job_id;
  v_newpts := v_phases * v_ppp + CASE WHEN v_phases >= 3 THEN v_bonus ELSE 0 END;
  v_delta  := v_newpts - v_job.photo_points;

  IF v_delta > 0 THEN
    UPDATE jobs SET photo_points = v_newpts WHERE id = p_job_id;
    UPDATE profiles SET cert_points = cert_points + v_delta
      WHERE id = auth.uid() RETURNING cert_points INTO v_after;
    WHILE v_after >= v_per LOOP
      INSERT INTO priority_tickets(owner_id, source, source_job_id, expires_at)
      VALUES (auth.uid(), 'photo_cert', p_job_id,
              now() + make_interval(days => (SELECT (value)::int FROM app_settings WHERE key='ticket_expiry_days')));
      v_after := v_after - v_per; v_granted := v_granted + 1;
    END LOOP;
    IF v_granted > 0 THEN
      UPDATE profiles SET cert_points = v_after WHERE id = auth.uid();
      INSERT INTO notifications(user_id, type) VALUES (auth.uid(), 'ticket_granted');
    END IF;
  END IF;

  RETURN jsonb_build_object('job_points', v_newpts, 'tickets_granted', v_granted);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 2.6 pg_cron 스케줄

```sql
-- ① 매일 새벽: 정회원 일일 1000p 차감, 부족 시 박탈
SELECT cron.schedule('deduct-daily-fee','5 0 * * *', $$
  WITH fee AS (SELECT (value)::int v FROM app_settings WHERE key='daily_fee')
  UPDATE profiles p SET
    point_balance = CASE WHEN p.point_balance >= (SELECT v FROM fee)
                         THEN p.point_balance - (SELECT v FROM fee) ELSE p.point_balance END,
    membership_status = CASE WHEN p.point_balance >= (SELECT v FROM fee)
                         THEN 'active' ELSE 'suspended' END
  WHERE p.membership_status = 'active';
  -- 차감 거래 로그/박탈 알림은 함수 버전으로 분리 권장(여기선 개념만)
$$);

-- ② 매 분: 우선배차 윈도우 마감 처리 + **지정배차 윈도우 만료(designate_window_expires < now) → status=open 일반 선착순 전환** (지정 윈도우 신규)
-- ③ 매일 자정: 지난 일감 expired (v2.1 유지)
-- ④ 매일 새벽 1시: matched→completed (v2.1 유지)
-- ⑤ 매일 09시: 배차권 만료 임박 알림 (v2.1 유지)
-- ⑥ 매일 09시: 포인트 잔액 임박(예: 3일치 미만) 경고 알림 (신규)
-- ⑦ 매일 새벽: 사진 보관 만료(photo_retention_days, 1년) 경과분 → 관리자 장기보관 백업 큐 적재 후 정리 (신규)
```

> ①은 정확한 원장 기록·박탈 알림을 위해 실제로는 **plpgsql 함수**로 작성하여 `point_transactions` insert와 FCM 트리거를 포함합니다(위 UPDATE는 개념 표현).

---

## 3. Flutter 앱 화면 구조

### 3.1 라우팅 (v2.1 + 신규)

```
/splash · /auth(/login · /signup(약관·정보·서류5종) · /pending-approval)
/main (BottomNavigationBar 5탭)
├── [탭1] /jobs           일감 목록(지역+장비 필터)
│   ├── /jobs/detail/:id  상세 + 지원(우선/일반/지정)
│   └── /jobs/create      발주(일반/지정배차 선택)
├── [탭2] /dispatch       내 배차 내역
│   └── /dispatch/detail/:id  상대정보 + 기사 서류 열람(마스킹/워터마크)
├── [탭3] /calendar       배차 캘린더
├── [탭4] /wallet         포인트 지갑(충전·내역·인출)   ← (구 /tickets 통합)
│   └── /wallet/charge · /wallet/withdraw · /tickets(우선배차권)
└── [탭5] /my             마이페이지(프로필·올린일감·지원내역·알림설정(지역/장비)·차단목록·설정)
    └── /my/blocks        차단 목록(조회/해제)
```

> v2.1의 별도 "우선배차권 탭"은 **포인트 지갑** 하위로 통합(포인트가 핵심 자산이 됨). 탭 구성은 디자인 시 재확정.

### 3.2 주요 화면 변경점
- **일감 목록:** 정렬 "거리순" 제거. **지역 필터** 추가. 지정배차 일감은 "지정" 배지 + **지정 마감 5분 카운트다운** + "지정배차건입니다 · 5분 후 일반 선착순 전환" 안내. 지정자만 지원(비번/회원번호 다이얼로그), 그 외 열람만.
- **발주 화면:** "지정배차" 토글 → 비밀번호 or 상대 회원번호 입력 + **안내(지정 기사 5분 우선권 · 미수락 시 일반 선착순 전환 · 지정배차 매칭 N(기본3)건마다 우선배차권 1장)**. 금액 입력(소개비 안내).
- **지원 버튼:** 포인트 부족 시 비활성 + "충전" CTA. 소개비/수수료 예상액 표시.
- **배차 상세:** 매칭 후 상대 연락처 + **기사 서류 5종(마스킹·워터마크·캡처경고)** 뷰어.
- **포인트 지갑:** 충전(가상계좌 발급·입금안내), 내역(충전/차감/소개비/수수료/인출), 인출 신청.
- **마이페이지 설정:** **알림 지역/장비 선택**(`notify_regions`,`notify_equipment`).

### 3.3 상태 관리 (변경)
- `locationProvider` **제거**. `regionFilterProvider`/`equipmentFilterProvider` 추가.
- `pointBalanceProvider`, `membershipStatusProvider`, `walletHistoryProvider` 추가.
- `ticketCountProvider` 유지.

### 3.4 Realtime (v2.1 유지) + `profiles.point_balance`/`membership_status` 구독으로 지갑·차단 상태 실시간 반영.

---

## 4. 핵심 비즈니스 로직 플로우

### 4.1 일반 발주 → 우선배차 매칭
```
발주(일반) → 트리거: 우선배차권 1장 발급 + (조건 보유자/프리미엄 존재 시) priority_window N초
 → 조건+알림설정 일치 기사에게 FCM
 → 우선배차권자(또는 프리미엄) "우선 지원": 멤버십·장비·포인트 검증 → (프리미엄 아니면)배차권 차감 → 지원기록(유효별점·발주이력 스냅샷)
 → N초 후 cron → finalize: [프리미엄>평점(관리자)>일감횟수>별점>선착순] 채택, 하루1건(수락일) 제외 적용
 → 매칭 확정 시 소개비 10%(B→A)+(추후)플랫폼 1000p 정산, 탈락자 배차권 반환
 → 우선지원자 없으면 open 전환 → 일반 선착순
```

### 4.2 지정배차
```
발주(지정) → 우선배차권 자동발급 없음, status=designated_window(지정 윈도우 5분·designated_window_seconds)
 → 다른 유저 열람 가능(지원 불가 · "지정배차건입니다" 안내, 거짓일감 모니터링)
 → 지정자가 비밀번호/회원번호 입력해 지원 → 즉시 매칭 → 소개비 정산
   → 매칭성사 지정배차 누적이 N(기본3) 배수면 발주자에게 우선배차권 1장 보상
 → [미수락·5분 경과] cron②가 status=open으로 전환 → 이후 일반 선착순 매칭(이 건은 일반발주로 처리)
```

### 4.3 포인트 생애주기
```
충전: 앱에서 충전요청 → charges(pending, 입금액=원금+VAT+440) → 가상계좌 발급
 → 입금통보 webhook → confirm_charge → 포인트 발급 + 원장기록
매일: cron deduct-daily-fee → 1000p 차감 / 부족 시 suspended(전체차단)
박탈중: 차감 정지, 충전만 가능 → recover_membership(1000p 납부) → active 복구
매칭: settle_referral(소개비/수수료)
인출: 사용자 신청(withdrawals) → 관리자 승인 → 지급 + 원장기록  [범위 R1 확정 필요]
```

### 4.4 회원 상태 머신
```
pending --관리자 승인--> active
active  --잔액<1000(cron)--> suspended
suspended --충전+1000p 납부--> active
(is_premium 플래그는 상태와 독립, 관리자 토글)
```

---

## 5. 캘린더 (v2.1 유지)
- 거리 관련 제거 외 변경 없음. 충돌 경고/월간 표시 동일.

## 6. FCM 푸시 (v2.1 코드 유지 + 알림 필터)
- `send-notification` 대상 산정 시 **수신자의 `notify_regions`/`notify_equipment`와 일감 조건 교집합**만 발송.
- 알림 type 추가: `point_low`, `membership_suspended`, `charge_paid`, `withdraw_processed`.

## 7. 에러 처리 표준 (v2.1 + 신규 코드)

| 신규 에러 코드 | 의미 | 사용자 메시지 |
|---|---|---|
| INSUFFICIENT_POINT | 포인트 부족 | "포인트가 부족합니다. 충전 후 이용해 주세요" |
| MEMBERSHIP_SUSPENDED | 준회원(박탈) | "정회원 복구(충전+1000p) 후 이용 가능합니다" |
| NOT_AUTHORIZED | 지정배차 비번/회원번호 불일치 등 | "이 일감을 받을 수 있는 대상이 아닙니다" |
| BLOCKED | 차단 관계 | "차단된 상대의 일감에는 지원할 수 없습니다" |
| CHARGE_NOT_FOUND / WITHDRAW_INVALID | 충전/인출 오류 | 상황별 안내 |

기존 코드(SELF_APPLY, JOB_UNAVAILABLE, NO_TICKET, SCHEDULE_CONFLICT 등)는 v2.1 유지.

> ⚠️ **`EQUIPMENT_MISMATCH` 폐지(2026-06-14 미팅):** 기종 불일치를 더 이상 **차단하지 않습니다.** 지원은 허용하되 클라이언트가 안내 팝업(본인 기종 아님 + 부적절행위 감지 시 제재 고지)을 띄우고, `job_applications.equipment_mismatch=true`로 **기록만** 합니다(모니터링·향후 제재용).

---

## 8. 개발 로드맵 및 마일스톤 (재산정)

> 포인트/결제·회원등급·지정배차·관리자웹 추가로 **v2.1 18주 → 약 24~26주**로 증가.

| Phase | 기간 | 핵심 산출물 |
|-------|------|------------|
| P1 기반 | 3주 | 회원가입(서류5종)·로그인·승인대기·앱 골격 |
| P2 일감 CRUD | 3주 | 발주(일반/지정 분기)·목록(지역/장비 필터)·상세 |
| P3 매칭 엔진 | 4주 | 우선배차권·베이지안 별점·**5단계 우선순위(평점 포함)**·finalize·지정배차·**사진 인증** |
| **P4 포인트/결제** | **4주** | 토스 가상계좌 충전·일일차감·소개비/수수료 정산·인출·원장 |
| P5 푸시 | 2주 | FCM + 알림 필터 |
| P6 캘린더 | 2주 | 월간/충돌 |
| **P7 관리자 웹** | **3주** | 회원승인·서류검토/마스킹·프리미엄명단·포인트/세무 export·모니터링 |
| P8 폴리싱/QA/배포 | 3주 | 캡처방지·워터마크·실기기·스토어 |
| 버퍼 | 1~2주 | |

> **결제/인출은 PG 계약·전자금융거래법 검토(고객/사업자 주체)** 완료가 선행되어야 P4를 마감할 수 있습니다(블로커 가능).

---

## 9. 리스크 및 해결

| 리스크 | 해결 |
|--------|------|
| 윈도우 60초 vs 30초 | `app_settings.priority_window_seconds`로 통일(**기본 30초**, 20초는 추후 변경). 문서·코드 불일치 제거 |
| 포인트 정합성 | 모든 증감은 SECURITY DEFINER RPC + `point_transactions` 원장(balance_after) + 비관적 락 |
| 동시 매칭 race | `FOR UPDATE SKIP LOCKED`, `UNIQUE(job_id,applicant_id)`, 락 순서(섹션 14, v2.1) |
| 선불충전금 규제 | 인출=**충전금 포함 전 잔액**(R1 확정). 사업자가 **선불업 등록 진행**(R4). 개발은 본인계좌 한정·관리자 승인·원장으로 대응 |
| 서버 다운/부하 | Realtime 구독 범위 최소화, RPC 단위 트랜잭션, 커넥션 풀, cron 분산 |
| 1인 원격 디버깅 | Sentry + 구조화 로깅 + RPC 에러코드 표준 |
| 캡처 방지 한계(iOS) | 워터마크+법적경고로 보완, 원본은 서버 비공개·마스킹본만 노출 |
| 지정배차 어뷰징 | 보상은 **매칭 성사 기준**(올린 횟수 아님)으로 가짜일감 무력화 |

---

## 10~15. 변경 없는 항목 (v2.1 참조)

- **10. 추후 검토 기능 후보** — v2.1 §10 유지(단 "거리/GPS 기반" 항목은 보류).
- **11. 폴더 구조** — v2.1 §11 기준 + `features/wallet`, `features/designated`, `admin-web/`(별도 레포) 추가.
- **12·13. P1/P2 개선(취소·시간충돌·번호변경·알림정리)** — v2.1 SQL 그대로 적용.
- **14. 락 순서 원칙** — v2.1 §14 유지. 포인트 RPC도 **jobs → priority_tickets → job_applications → profiles(차감/가산) → point_transactions** 순서 준수.
- **15. 마이그레이션 체크리스트** — v2.1 기준 + 신규 마이그레이션:
  `017_points.sql`(profiles 확장·point_transactions·charges·withdrawals·app_settings),
  `018_member_documents.sql`, `019_designated.sql`(jobs 컬럼·apply_designated),
  `020_matching_v3.sql`(effective_rating·poster_recent_post_count·finalize 교체),
  `021_daily_fee_cron.sql`,
  `022_user_blocks.sql`(차단 테이블·RLS·매칭 가드).

---

## 변경 이력

| 버전 | 날짜 | 내용 |
|------|------|------|
| v2.1 | 2026.05 | P0 패치 통합, P1/P2, 18주 로드맵 (거리매칭 기반) |
| v3.0 | 2026-06-04 | 3차 미팅 전면 반영 — 별점100% 베이지안, 4단계 우선순위, 프리미엄 명단, 발주이력, 지정배차, 포인트 경제(충전/차감/소개비/수수료/인출 전액), 회원등급, 지역/알림 필터, 사용자 차단, 관리자웹·세무export·모니터링, 거리/GPS 폐지, 로드맵 24~26주. 윈도우 기본 30초(20초 추후), 선불업 등록 전제 |
| v3.0 (개정) | 2026-06-14 | 미팅 반영 — **매칭 5단계**(평점 2순위 신설: `admin_score` 기본 50·관리자±1·비공개·`admin_score_log`), **사진 인증→우선배차권**(`job_photos`·`register_job_photo`, 40점, 1년 보관 후 관리자 백업·cron ⑦), **기종 불일치 차단 폐지→안내+`equipment_mismatch` 기록**, app_settings(평점·사진·`ticket_expiry_days`) 추가, 우선배차권 유효기간 조사 후 확정 |
| v3.0 (개정) | 2026-06-16 | **지정배차 윈도우 신설** — 지정 5분(`designated_window_seconds`=300) 동안 지정자만 지원·다른 유저 열람만, 미수락 시 일반 선착순(open) 전환(cron②). `jobs.designate_window_expires`·status `designated_window` 추가. 보상은 매칭성사 지정배차 3건당 1장 유지(전환 후 일반매칭은 일반발주 처리). 목업 ②/⑨/⑯ 반영 |
| v3.0 (개정) | 2026-06-16 | **식별번호 숫자화** — 일감번호 `jobs.job_no` `YYMMDD-NNNN`(랜덤 4자리 숫자), 회원번호 `member_no` 6자리 숫자. 알파벳 제거(현장 소통 용이). 문서·목업 전체 반영 |
| v3.0 (개정) | 2026-06-19 | **허용 장비 다중화** — 일감에 여러 허용 장비(`job_equipment_options`, 카테고리+최소모델) 등록·**OR 매칭**(아무거나 1대). `jobs.required_*`는 대표 옵션. apply 가드·발주이력·윈도우 판정은 옵션집합 기준. status enum `designated_window` 명시. **회원가입 승인 SLA 영업일 3일**(기능명세서). 목업 ⑨/③ 반영 |
