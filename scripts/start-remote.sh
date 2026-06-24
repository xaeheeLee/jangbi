#!/usr/bin/env bash
# 전중배 원격 작업 시작 — 아침에 맥에서 1회 실행.
# 이 터미널 창은 닫지 마세요(닫으면 세션이 종료됩니다).
#
# 사용: bash scripts/start-remote.sh
set -uo pipefail

PROJECT="$HOME/Desktop/project/jangbinara"
SESSION_NAME="전중배 dev"

echo "▶ 전중배 원격 세션 준비"

# 1) Tailscale 실행 확인 (회사망↔집망 연결용)
TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
if [ -x "$TS" ]; then
  if "$TS" status >/dev/null 2>&1; then
    echo "  ✅ Tailscale 연결됨"
  else
    echo "  ⚠️  Tailscale 미연결 — 메뉴바 아이콘에서 로그인/연결하세요."
  fi
else
  echo "  ⚠️  Tailscale 미설치 — 'brew install --cask tailscale' 후 로그인하세요."
fi

# 2) 잠자기 방지 (디스플레이/시스템/디스크). 이 스크립트가 끝나면 자동 해제.
caffeinate -dimsu &
CAFFEINATE_PID=$!
trap 'kill "$CAFFEINATE_PID" 2>/dev/null; echo; echo "■ 잠자기 방지 해제, 세션 종료"' EXIT
echo "  ✅ 잠자기 방지 시작 (caffeinate, PID $CAFFEINATE_PID)"

# 3) 리모트 컨트롤 세션 열기 (폰/브라우저에서 접속)
cd "$PROJECT/app" || cd "$PROJECT"
echo "  ▶ 리모트 세션 여는 중... (QR/세션URL이 표시되면 폰 Claude 앱에서 접속)"
echo
claude remote-control --name "$SESSION_NAME"
