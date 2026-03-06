#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# 설치 검증 스크립트
# 사용법: sudo ./scripts/verify.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

check() {
    local desc="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        echo -e "  ${GREEN}[PASS]${NC} ${desc}"
        ((PASS++))
    else
        echo -e "  ${RED}[FAIL]${NC} ${desc}"
        ((FAIL++))
    fi
}

if [[ -f "$ENV_FILE" ]]; then
    # .env 안전성 검사
    if grep -Eq '`|\$\(' "$ENV_FILE" 2>/dev/null; then
        echo -e "  ${RED}[WARN]${NC} .env에 위험한 셸 구문이 포함되어 있습니다"
        exit 1
    fi
    source "$ENV_FILE"
fi
SERVICE_USER="${SERVICE_USER:-claudeweb}"
CLOUDCLI_PORT="${CLOUDCLI_PORT:-3001}"
DOMAIN="${DOMAIN:-}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Claude Code Web Service — 설치 검증"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "▸ 시스템"
check "서비스 유저 존재" id "${SERVICE_USER}"
check "tmux 설치됨" which tmux
check "pandoc 설치됨" which pandoc
check "nginx 실행 중" systemctl is-active nginx

echo ""
echo "▸ Node.js / Claude Code"
check "Node.js 설치됨" sudo -u "${SERVICE_USER}" bash -c 'source ~/.nvm/nvm.sh && node --version'
check "Claude Code 설치됨" sudo -u "${SERVICE_USER}" bash -c 'source ~/.nvm/nvm.sh && claude --version'
check "CloudCLI 설치됨" sudo -u "${SERVICE_USER}" bash -c 'source ~/.nvm/nvm.sh && cloudcli version'

echo ""
echo "▸ 설정 파일"
HOME_DIR=$(getent passwd "${SERVICE_USER}" 2>/dev/null | cut -d: -f6)
[[ -n "${HOME_DIR}" ]] || HOME_DIR="/home/${SERVICE_USER}"
check "~/.claude.json 존재" test -f "${HOME_DIR}/.claude.json"
check "~/.claude/settings.json 존재" test -f "${HOME_DIR}/.claude/settings.json"
check "workspace 디렉토리 존재" test -d "${HOME_DIR}/workspace/documents"
check "auto-update.sh 존재" test -x "${HOME_DIR}/auto-update.sh"

echo ""
echo "▸ 서비스"
check "claudeweb 서비스 활성화" systemctl is-enabled claudeweb
check "claudeweb 서비스 실행 중" systemctl is-active claudeweb
check "포트 ${CLOUDCLI_PORT} 리스닝" bash -c "ss -tlnp | grep -q :${CLOUDCLI_PORT}"

echo ""
echo "▸ 웹 접근"
check "로컬 HTTP 응답" curl -sf -o /dev/null "http://127.0.0.1:${CLOUDCLI_PORT}"

if [[ -n "${DOMAIN}" ]]; then
    check "도메인 HTTPS 응답" curl -sf -o /dev/null "https://${DOMAIN}" --max-time 5
fi

echo ""
echo "▸ Cron 설정"
check "자동 업데이트 cron 등록됨" bash -c "sudo -u ${SERVICE_USER} crontab -l | grep -q auto-update"
check "sudoers 설정 존재" test -f /etc/sudoers.d/claudeweb

if [[ -n "${MEM0_HOST:-}" ]]; then
    echo ""
    echo "▸ Mem0 MCP (자체 서버)"
    check "Mem0 venv 존재" test -d "${HOME_DIR}/.mcp-venv/mem0"
    check "Mem0 서버 스크립트 존재" test -f "${HOME_DIR}/.mcp-scripts/mem0_server.py"
    check "Mem0 MCP Python 의존성 설치됨" "${HOME_DIR}/.mcp-venv/mem0/bin/python3" -c "import mcp, httpx"
    check "Mem0 서버 연결 확인" curl -sf -o /dev/null --max-time 5 "${MEM0_HOST}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  결과: ${GREEN}${PASS} PASS${NC} / ${RED}${FAIL} FAIL${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ ${FAIL} -gt 0 ]]; then
    echo -e "${YELLOW}실패 항목을 확인하세요. 로그: journalctl -u claudeweb -n 50${NC}"
    exit 1
else
    echo -e "${GREEN}모든 검증 통과! 브라우저에서 접속하세요.${NC}"
fi
