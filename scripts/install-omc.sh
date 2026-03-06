#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OMC (OhMyClaudeCode) 설치 가이드 스크립트
# 사용법: sudo ./scripts/install-omc.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

[[ $EUID -eq 0 ]] || { echo -e "${RED}[✗]${NC} root 필요: sudo $0"; exit 1; }

# 토큰 로드: systemd 환경파일 우선, 없으면 .env 폴백
if [[ -f /etc/claudeweb.env ]]; then
    source /etc/claudeweb.env
elif [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    echo -e "${RED}[✗]${NC} 환경 설정을 찾을 수 없습니다. setup.sh를 먼저 실행하세요."; exit 1
fi

[[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]] || { echo -e "${RED}[✗]${NC} CLAUDE_CODE_OAUTH_TOKEN이 없습니다"; exit 1; }

SERVICE_USER="${SERVICE_USER:-claudeweb}"
HOME_DIR=$(getent passwd "${SERVICE_USER}" 2>/dev/null | cut -d: -f6)
[[ -n "${HOME_DIR}" ]] || HOME_DIR="/home/${SERVICE_USER}"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  OMC (OhMyClaudeCode) 설치${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}이 스크립트는 Claude Code 인터랙티브 세션을 열어줍니다.${NC}"
echo -e "${YELLOW}세션 안에서 아래 명령을 순서대로 타이핑하세요:${NC}"
echo ""
echo -e "  ${GREEN}1.${NC} /plugin marketplace add https://github.com/Yeachan-Heo/oh-my-claudecode"
echo -e "  ${GREEN}2.${NC} /plugin install oh-my-claudecode"
echo -e "  ${GREEN}3.${NC} /oh-my-claudecode:omc-setup"
echo -e "  ${GREEN}4.${NC} /exit"
echo ""
echo -e "${YELLOW}준비되셨으면 Enter를 누르세요...${NC}"
read -r

echo -e "${GREEN}[✓]${NC} Claude Code 인터랙티브 세션을 시작합니다..."
echo ""

# 토큰을 파일로 전달 (ps 프로세스 인자 노출 방지)
TOKEN_FILE=$(mktemp /tmp/.claude-token.XXXXXX)
echo "${CLAUDE_CODE_OAUTH_TOKEN}" > "${TOKEN_FILE}"
chmod 600 "${TOKEN_FILE}"
chown "${SERVICE_USER}:${SERVICE_USER}" "${TOKEN_FILE}"

sudo -u "${SERVICE_USER}" bash -c "
    export CLAUDE_CODE_OAUTH_TOKEN=\$(cat '${TOKEN_FILE}')
    rm -f '${TOKEN_FILE}'
    source ~/.nvm/nvm.sh
    cd ~/workspace
    claude
" || true

# 임시 파일 정리 (실패 시에도)
rm -f "${TOKEN_FILE}" 2>/dev/null

echo ""
echo -e "${GREEN}[✓]${NC} OMC 설치가 완료되었으면 서비스를 재시작합니다..."
systemctl restart claudeweb
echo -e "${GREEN}[✓]${NC} 완료! 브라우저에서 확인하세요."
