# 장비나라 (포크레인 배차 매칭 앱) — 프로젝트 자료

전국 중장비(포크레인) 배차 매칭 모바일 앱 개발 프로젝트.

## 📂 폴더 구조

```
jangbi_nara_project/
├── README.md                            # 이 문서
├── HANDOFF.md                           # ⭐ 로컬 작업 시작 시 가장 먼저 읽을 문서
│
├── docs/                                # 핵심 문서
│   ├── 01_dev_plan_v2.1.md              # ⭐ 최종 개발 계획서 (메인 참조)
│   ├── 02_meeting_agenda_v1.2.md        # 2차 미팅 어젠다 + 견적 (내부용)
│   ├── 03_architecture_review.md        # 초기 아키텍처 검토 (참고용)
│   ├── 04_dev_environment_cost.md       # 개발 환경 + 비용 구성
│   ├── 05_conversation_summary.md       # ⭐ 전체 대화 요약 및 의사결정 기록
│   └── 06_customer_pre_brief_v1.0.md    # 고객 사전 배포용 압축본
│
├── mockups/                             # UI 목업
│   └── jangbi_nara_mockup_v1.3.html     # 11개 화면 인터랙티브 목업
│
└── archive/                             # 구 버전 (참고용)
    ├── proposal_v3.pptx                 # 1차 미팅 PPT
    ├── dev_plan_v1.md                   # 초기 계획서
    ├── dev_plan_v2.0.md                 # v2.0 계획서 (v2.1로 대체됨)
    └── dev_plan_supplement.md           # 보완 문서 (v2.1에 통합됨)
```

## 🚀 빠른 시작

### 로컬 Claude (Claude Code)에게 작업 인계 시

1. **HANDOFF.md** 전체 읽기 (5~10분)
2. **docs/05_conversation_summary.md** 읽기 (의사결정 맥락)
3. **docs/01_dev_plan_v2.1.md** 정독 (개발 시 메인 참조)
4. **docs/02_meeting_agenda_v1.2.md** 로 미해결 항목 파악
5. **mockups/jangbi_nara_mockup_v1.3.html** 브라우저로 열어 UI 확인

### 개발 시작

```bash
# 1. Flutter 프로젝트 생성
flutter create app --org com.jangbinara --platforms ios,android
cd app

# 2. 패키지 설치 (HANDOFF.md 참조)
flutter pub get

# 3. Supabase 프로젝트 생성
# https://supabase.com 에서 새 프로젝트 + PostGIS 활성화

# 4. 마이그레이션 적용
# docs/01_dev_plan_v2.1.md 의 SQL 순서대로
```

## 🎯 현재 단계

- ✅ 1차 미팅 완료
- ✅ 2차 미팅 자료 준비 완료
- ✅ UI 목업 11개 화면 완성
- ⏳ **2차 미팅 진행 예정**
- ⏳ 미팅 후 v2.2 계획서 작성
- ⏳ 확정 견적 + 계약서
- ⏳ Phase 1 개발 착수

## 📌 주요 결정사항 요약

| 항목 | 결정 |
|------|------|
| 앱 이름 | 장비나라 |
| 기술 스택 | Flutter + Supabase + Riverpod |
| 메인 색상 | `#002F6C` 진한 네이비 |
| 폰트 | Pretendard Variable |
| 개발 기간 | 24주 (1차 출시) |
| 1차 출시 범위 | 매칭 + 캘린더 + 푸시 + 회원관리 |
| 1차 제외 | 채팅 / 작업일지 / 정산 / 결제 |

## 📞 다음 단계

1. 2차 미팅 — 미해결 12개 항목(Q1~Q12) 확정
2. 미팅 결과 반영하여 v2.2 계획서 작성
3. 확정 견적 + 계약서 작성
4. Flutter + Supabase 환경 셋업
5. Phase 1 (1~4주차) 개발 착수

자세한 내용은 **HANDOFF.md** 참조.
