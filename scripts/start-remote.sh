#!/usr/bin/env bash
# 전중배 원격 작업 시작 — 아침에 맥에서 1회 실행.
# 이 터미널 창은 닫지 마세요(닫으면 세션이 종료됩니다).
#
# 사용: bash scripts/start-remote.sh
set -uo pipefail

PROJECT="$HOME/Desktop/project/jangbinara"
SESSION_NAME="전중배 dev"

echo "▶ 전중배 원격 세션 준비"

# 1) 네트워크: Remote Control 은 Anthropic 서버를 경유(맥은 아웃바운드만)하므로
#    회사망↔집망이 달라도 그대로 연결됨. Tailscale·포트포워딩 불필요.

# 2) 잠자기 방지 (디스플레이/시스템/디스크). 이 스크립트가 끝나면 자동 해제.
caffeinate -dimsu &
CAFFEINATE_PID=$!
trap 'kill "$CAFFEINATE_PID" 2>/dev/null; echo; echo "■ 잠자기 방지 해제, 세션 종료"' EXIT
echo "  ✅ 잠자기 방지 시작 (caffeinate, PID $CAFFEINATE_PID)"

# 3) 리모트 컨트롤 세션 열기
#    --spawn same-dir: 폰 세션이 '이 실제 작업 폴더'에서 열린다(gitignore된 dart_define.json·
#    빌드 캐시 그대로 사용). worktree 모드면 키 파일이 없어 Supabase 연결이 끊김.
#    같은 claude.ai 계정이면 폰 Claude 앱 Code 탭에 세션이 자동으로 뜸 → 탭해서 연결.
#    "Ready" 에서 멈춘 듯 보여도 정상(접속 대기 서버). 이 창은 닫지 말 것.
cd "$PROJECT" || exit 1
echo "  ▶ 리모트 세션 여는 중... ('Ready' 표시 = 정상, 폰/웹 접속 대기)"
echo "    → 폰 Claude 앱 Code 탭에 '$SESSION_NAME' 가 뜨면 탭해서 연결 (QR 불필요)"
echo
claude remote-control --name "$SESSION_NAME" --spawn same-dir
