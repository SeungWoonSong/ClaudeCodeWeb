#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Claude Code Web Service 완전 삭제
# 사용법: sudo ./scripts/uninstall.sh
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

[[ $EUID -eq 0 ]] || { echo -e "${RED}[✗]${NC} root 필요: sudo $0"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

SERVICE_USER="${SERVICE_USER:-claudeweb}"
DOMAIN="${DOMAIN:-claude.yourdomain.com}"

echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  Claude Code Web Service 완전 삭제${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}삭제 대상:${NC}"
echo "  - systemd 서비스: claudeweb"
echo "  - Linux 유저: ${SERVICE_USER} (홈 디렉토리 포함)"
echo "  - Nginx 설정: ${DOMAIN}"
echo "  - sudoers: /etc/sudoers.d/claudeweb"
echo ""
echo -e "${RED}⚠ /home/${SERVICE_USER}/workspace의 문서가 모두 삭제됩니다!${NC}"
echo ""
read -rp "정말 삭제하시겠습니까? (yes를 정확히 입력): " confirm

if [[ "${confirm}" != "yes" ]]; then
    echo "취소됨."
    exit 0
fi

echo ""

# 서비스 중지/삭제
if systemctl is-active --quiet claudeweb 2>/dev/null; then
    systemctl stop claudeweb
    echo -e "${GREEN}[✓]${NC} 서비스 중지"
fi
systemctl disable claudeweb 2>/dev/null || true
rm -f /etc/systemd/system/claudeweb.service
systemctl daemon-reload
echo -e "${GREEN}[✓]${NC} systemd 서비스 삭제"

# Nginx 설정 삭제
rm -f "/etc/nginx/sites-enabled/${DOMAIN}"
rm -f "/etc/nginx/sites-available/${DOMAIN}"
nginx -t 2>/dev/null && systemctl reload nginx
echo -e "${GREEN}[✓]${NC} Nginx 설정 삭제"

# sudoers 삭제
rm -f /etc/sudoers.d/claudeweb
echo -e "${GREEN}[✓]${NC} sudoers 삭제"

# 유저 삭제 (홈 디렉토리 포함)
if id "${SERVICE_USER}" &>/dev/null; then
    # crontab 삭제
    crontab -u "${SERVICE_USER}" -r 2>/dev/null || true
    # 유저 + 홈 삭제
    userdel -r "${SERVICE_USER}" 2>/dev/null || true
    echo -e "${GREEN}[✓]${NC} 유저 ${SERVICE_USER} 및 홈 디렉토리 삭제"
fi

echo ""
echo -e "${GREEN}[✓]${NC} 완전 삭제 완료."
echo -e "${YELLOW}참고: certbot 인증서는 삭제하지 않았습니다.${NC}"
echo -e "${YELLOW}  필요 시: sudo certbot delete --cert-name ${DOMAIN}${NC}"
