#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Claude Code Web Service — 메인 설치 스크립트
# 사용법: sudo ./setup.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
step() { echo -e "\n${BLUE}=== $* ===${NC}"; }

# ── 사전 체크 ───────────────────────────────────────────────

[[ $EUID -eq 0 ]] || err "root 권한이 필요합니다: sudo ./setup.sh"

ENV_FILE="${SCRIPT_DIR}/.env"
[[ -f "$ENV_FILE" ]] || err ".env 파일이 없습니다. 먼저 cp .env.example .env 후 값을 채우세요."

# shellcheck source=/dev/null
source "$ENV_FILE"

# 필수 값 체크
[[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]] || err ".env: CLAUDE_CODE_OAUTH_TOKEN이 비어있습니다"
[[ -n "${OAUTH_ACCOUNT_UUID:-}" ]]      || err ".env: OAUTH_ACCOUNT_UUID가 비어있습니다"
[[ -n "${OAUTH_EMAIL:-}" ]]             || err ".env: OAUTH_EMAIL이 비어있습니다"
[[ -n "${DOMAIN:-}" ]]                  || err ".env: DOMAIN이 비어있습니다"
[[ -n "${BRAVE_API_KEY:-}" ]]           || err ".env: BRAVE_API_KEY가 비어있습니다"
[[ -n "${EXA_API_KEY:-}" ]]             || err ".env: EXA_API_KEY가 비어있습니다"

SERVICE_USER="${SERVICE_USER:-claudeweb}"
CLOUDCLI_PORT="${CLOUDCLI_PORT:-3001}"
NODE_VERSION="${NODE_VERSION:-22}"
UPDATE_HOUR_KST="${UPDATE_HOUR_KST:-9}"
HOME_DIR="/home/${SERVICE_USER}"

log "환경 변수 로드 완료"
log "도메인: ${DOMAIN}"
log "서비스 유저: ${SERVICE_USER}"

# ── Step 1: 시스템 패키지 ────────────────────────────────────

step "Step 1/7: 시스템 패키지 설치"

apt-get update -qq
apt-get install -y -qq tmux git curl pandoc nginx certbot python3-certbot-nginx > /dev/null 2>&1

log "tmux, git, pandoc, nginx, certbot 설치 완료"

# ── Step 2: 서비스 유저 생성 ─────────────────────────────────

step "Step 2/7: 서비스 유저 생성"

if id "${SERVICE_USER}" &>/dev/null; then
    warn "유저 ${SERVICE_USER} 이미 존재 — 건너뜀"
else
    useradd -m -s /bin/bash "${SERVICE_USER}"
    log "유저 ${SERVICE_USER} 생성 완료"
fi

# ── Step 3: Node.js + Claude Code + CloudCLI ─────────────────

step "Step 3/7: Node.js ${NODE_VERSION} + Claude Code + CloudCLI 설치"

sudo -u "${SERVICE_USER}" bash << NODEEOF
set -euo pipefail

# nvm 설치 (이미 있으면 건너뜀)
export NVM_DIR="\${HOME}/.nvm"
if [[ ! -d "\${NVM_DIR}" ]]; then
    curl -so- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi
source "\${NVM_DIR}/nvm.sh"

# Node.js 설치
if ! nvm ls ${NODE_VERSION} &>/dev/null; then
    nvm install ${NODE_VERSION}
fi
nvm use ${NODE_VERSION}
nvm alias default ${NODE_VERSION}

# Claude Code + CloudCLI
npm install -g @anthropic-ai/claude-code @siteboon/claude-code-ui 2>/dev/null

echo "node: \$(node --version)"
echo "claude: \$(claude --version 2>/dev/null || echo 'installed')"
echo "cloudcli: \$(cloudcli version 2>/dev/null || echo 'installed')"
NODEEOF

log "Node.js + Claude Code + CloudCLI 설치 완료"

# Node.js 실제 경로 찾기
NODE_BIN_DIR=$(sudo -u "${SERVICE_USER}" bash -c 'source ~/.nvm/nvm.sh && dirname $(which node)')
log "Node 바이너리 경로: ${NODE_BIN_DIR}"

# ── Step 4: Claude Code 설정 파일 배포 ───────────────────────

step "Step 4/7: Claude Code 설정 파일 배포"

# 디렉토리 생성
sudo -u "${SERVICE_USER}" mkdir -p "${HOME_DIR}/.claude"
sudo -u "${SERVICE_USER}" mkdir -p "${HOME_DIR}/workspace/documents"

# claude.json (onboarding 우회)
CLAUDE_VERSION=$(sudo -u "${SERVICE_USER}" bash -c "source ~/.nvm/nvm.sh && claude --version 2>/dev/null" || echo "2.1.37")

cat > "${HOME_DIR}/.claude.json" << CJSON
{
  "hasCompletedOnboarding": true,
  "lastOnboardingVersion": "${CLAUDE_VERSION}",
  "oauthAccount": {
    "accountUuid": "${OAUTH_ACCOUNT_UUID}",
    "emailAddress": "${OAUTH_EMAIL}",
    "organizationUuid": "${OAUTH_ORG_UUID:-}"
  }
}
CJSON
chown "${SERVICE_USER}:${SERVICE_USER}" "${HOME_DIR}/.claude.json"
chmod 600 "${HOME_DIR}/.claude.json"
log "claude.json 생성 완료"

# MCP settings.json 생성
SETTINGS_FILE="${HOME_DIR}/.claude/settings.json"

# 기본 MCP 서버 설정
cat > "${SETTINGS_FILE}" << 'MCPBASE'
{
  "mcpServers": {
    "brave-search": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-brave-search"],
      "env": {
MCPBASE

# Brave API Key 삽입
cat >> "${SETTINGS_FILE}" << MCPBRAVE
        "BRAVE_API_KEY": "${BRAVE_API_KEY}"
MCPBRAVE

cat >> "${SETTINGS_FILE}" << 'MCPMID1'
      }
    },
    "exa-search": {
      "command": "npx",
      "args": ["-y", "exa-mcp-server"],
      "env": {
MCPMID1

# Exa API Key 삽입
cat >> "${SETTINGS_FILE}" << MCPEXA
        "EXA_API_KEY": "${EXA_API_KEY}"
MCPEXA

cat >> "${SETTINGS_FILE}" << MCPMID2
      }
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "${HOME_DIR}/workspace/documents"]
    }
MCPMID2

# 선택: Supabase MCP
if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
    cat >> "${SETTINGS_FILE}" << MCPSUPA
    ,"supabase": {
      "command": "npx",
      "args": ["-y", "supabase-mcp-server"],
      "env": {
        "SUPABASE_URL": "${SUPABASE_URL}",
        "SUPABASE_SERVICE_ROLE_KEY": "${SUPABASE_SERVICE_ROLE_KEY}"
      }
    }
MCPSUPA
    log "Supabase MCP 추가"
fi

# 선택: 자체 Mem0 MCP
if [[ -n "${MEM0_API_URL:-}" ]]; then
    cat >> "${SETTINGS_FILE}" << MCPMEM0
    ,"mem0": {
      "command": "uvx",
      "args": ["mem0-mcp"],
      "env": {
        "MEM0_API_URL": "${MEM0_API_URL}",
        "MEM0_API_KEY": "${MEM0_API_KEY:-}",
        "MEM0_DEFAULT_USER_ID": "${MEM0_USER_ID:-pm-default}"
      }
    }
MCPMEM0
    log "Mem0 MCP 추가 (자체 서버: ${MEM0_API_URL})"
fi

# JSON 닫기
cat >> "${SETTINGS_FILE}" << 'MCPEND'
  }
}
MCPEND

chown "${SERVICE_USER}:${SERVICE_USER}" "${SETTINGS_FILE}"
chmod 600 "${SETTINGS_FILE}"
log "MCP settings.json 생성 완료"

# ── Step 5: systemd 서비스 ───────────────────────────────────

step "Step 5/7: systemd 서비스 등록"

cat > /etc/systemd/system/claudeweb.service << SVCEOF
[Unit]
Description=Claude Code Web UI (CloudCLI)
After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}

# Claude Code OAuth 인증
Environment=CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN}

# Node.js PATH
Environment=PATH=${NODE_BIN_DIR}:/usr/local/bin:/usr/bin:/bin
Environment=NODE_ENV=production
Environment=HOME=${HOME_DIR}

ExecStart=${NODE_BIN_DIR}/cloudcli --host 127.0.0.1 --port ${CLOUDCLI_PORT}
WorkingDirectory=${HOME_DIR}/workspace

Restart=unless-stopped
RestartSec=5
TimeoutStopSec=10

# 보안 하드닝
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=${HOME_DIR}
ReadWritePaths=/tmp
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable claudeweb
systemctl start claudeweb

# 시작 확인 (최대 15초 대기)
for i in $(seq 1 15); do
    if systemctl is-active --quiet claudeweb; then
        log "claudeweb 서비스 시작 완료"
        break
    fi
    sleep 1
done

if ! systemctl is-active --quiet claudeweb; then
    err "서비스 시작 실패. 로그 확인: journalctl -u claudeweb -n 50"
fi

# ── Step 6: Nginx 설정 ──────────────────────────────────────

step "Step 6/7: Nginx 리버스 프록시 설정"

cat > "/etc/nginx/sites-available/${DOMAIN}" << NGXEOF
server {
    listen 80;
    server_name ${DOMAIN};

    # certbot이 HTTPS 리다이렉트를 자동 추가합니다
    location / {
        proxy_pass http://127.0.0.1:${CLOUDCLI_PORT};
        proxy_http_version 1.1;

        # WebSocket 지원 (claudecodeui 필수)
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # 표준 프록시 헤더
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # 타임아웃 (WebSocket 장시간 연결)
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;

        # 버퍼 크기
        proxy_buffer_size 128k;
        proxy_buffers 8 256k;
    }
}
NGXEOF

# 심볼릭 링크 (이미 있으면 덮어쓰기)
ln -sf "/etc/nginx/sites-available/${DOMAIN}" "/etc/nginx/sites-enabled/${DOMAIN}"

# default 사이트 비활성화 (충돌 방지)
rm -f /etc/nginx/sites-enabled/default

nginx -t || err "Nginx 설정 오류"
systemctl reload nginx
log "Nginx 설정 완료"

# TLS (Let's Encrypt)
warn "TLS 인증서를 발급합니다. DNS가 이 서버 IP를 가리키고 있어야 합니다."
echo ""
read -rp "  지금 certbot으로 TLS를 설정할까요? (y/N): " do_cert
if [[ "${do_cert}" =~ ^[Yy]$ ]]; then
    certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos --email "${OAUTH_EMAIL}" || warn "certbot 실패 — 나중에 수동 실행: sudo certbot --nginx -d ${DOMAIN}"
    log "TLS 인증서 발급 완료"
else
    warn "TLS 건너뜀. 나중에 실행: sudo certbot --nginx -d ${DOMAIN}"
fi

# ── Step 7: 자동 업데이트 cron ───────────────────────────────

step "Step 7/7: 매일 자동 업데이트 설정 (KST ${UPDATE_HOUR_KST}:00)"

# KST → UTC 변환
UPDATE_HOUR_UTC=$(( (UPDATE_HOUR_KST - 9 + 24) % 24 ))

# 업데이트 스크립트 생성
cat > "${HOME_DIR}/auto-update.sh" << 'UPDEOF'
#!/usr/bin/env bash
set -euo pipefail
LOG_TAG="claude-update"
logger -t "$LOG_TAG" "Starting auto-update..."

export NVM_DIR="${HOME}/.nvm"
source "${NVM_DIR}/nvm.sh"

# Claude Code 업데이트
npm update -g @anthropic-ai/claude-code 2>&1 | logger -t "$LOG_TAG" || true

# CloudCLI 업데이트
npm update -g @siteboon/claude-code-ui 2>&1 | logger -t "$LOG_TAG" || true

logger -t "$LOG_TAG" "claude: $(claude --version 2>/dev/null || echo 'unknown')"
logger -t "$LOG_TAG" "cloudcli: $(cloudcli version 2>/dev/null || echo 'unknown')"
logger -t "$LOG_TAG" "Update complete. Restarting service..."

# 서비스 재시작 (sudoers 필요)
sudo /bin/systemctl restart claudeweb 2>&1 | logger -t "$LOG_TAG" || true

logger -t "$LOG_TAG" "Service restarted."
UPDEOF
chown "${SERVICE_USER}:${SERVICE_USER}" "${HOME_DIR}/auto-update.sh"
chmod +x "${HOME_DIR}/auto-update.sh"

# sudoers — claudeweb 유저가 서비스 재시작만 가능하도록
cat > /etc/sudoers.d/claudeweb << SUDOEOF
${SERVICE_USER} ALL=(ALL) NOPASSWD: /bin/systemctl restart claudeweb
SUDOEOF
chmod 440 /etc/sudoers.d/claudeweb

# crontab 설정
CRON_LINE="${UPDATE_HOUR_UTC} 0 * * * ${HOME_DIR}/auto-update.sh"
(sudo -u "${SERVICE_USER}" crontab -l 2>/dev/null | grep -v "auto-update.sh" || true; echo "${CRON_LINE}") | sudo -u "${SERVICE_USER}" crontab -

log "매일 KST ${UPDATE_HOUR_KST}:00 (UTC ${UPDATE_HOUR_UTC}:00) 자동 업데이트 설정 완료"

# ── 완료 ─────────────────────────────────────────────────────

step "설치 완료!"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Claude Code Web Service가 실행 중입니다.${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  로컬 접속:   ${BLUE}http://127.0.0.1:${CLOUDCLI_PORT}${NC}"
echo -e "  외부 접속:   ${BLUE}https://${DOMAIN}${NC}"
echo ""
echo -e "  서비스 상태: ${YELLOW}sudo systemctl status claudeweb${NC}"
echo -e "  로그 확인:   ${YELLOW}journalctl -u claudeweb -f${NC}"
echo -e "  업데이트 로그: ${YELLOW}journalctl -t claude-update${NC}"
echo ""
echo -e "${YELLOW}  [다음 단계] OMC 설치:${NC}"
echo -e "  ${BLUE}sudo ./scripts/install-omc.sh${NC}"
echo ""
