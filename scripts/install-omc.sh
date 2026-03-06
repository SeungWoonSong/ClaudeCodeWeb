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
[[ -f "$ENV_FILE" ]] || { echo -e "${RED}[✗]${NC} .env 파일이 없습니다"; exit 1; }
source "$ENV_FILE"

SERVICE_USER="${SERVICE_USER:-claudeweb}"
HOME_DIR="/home/${SERVICE_USER}"

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

sudo -u "${SERVICE_USER}" bash -c "
    export CLAUDE_CODE_OAUTH_TOKEN='${CLAUDE_CODE_OAUTH_TOKEN}'
    source ~/.nvm/nvm.sh
    cd ~/workspace
    claude
"

echo ""
echo -e "${GREEN}[✓]${NC} OMC 설치가 완료되었으면 서비스를 재시작합니다..."
systemctl restart claudeweb
echo -e "${GREEN}[✓]${NC} 완료! 브라우저에서 확인하세요."
