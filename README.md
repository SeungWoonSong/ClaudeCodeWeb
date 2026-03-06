# Claude Code Web Service

PM이 브라우저에서 Claude Code + OhMyClaudeCode로 문서를 작성할 수 있는 웹 서비스.

## 아키텍처

```
[PM 브라우저] → HTTPS → [Nginx + TLS] → [cloudcli :3001] → [Claude Code CLI]
                                                              ├── OMC (멀티에이전트)
                                                              ├── Brave + Exa (웹 검색)
                                                              ├── Filesystem MCP
                                                              ├── Mem0 (메모리)
                                                              ├── Supabase MCP
                                                              └── pandoc (md→docx)
```

## 사전 준비

### 1. OAuth 토큰 생성 (로컬 PC에서 1회)

**브라우저가 있는 PC**에서 실행 (서버가 아님):

```bash
# Claude Code가 설치된 로컬 PC에서
claude setup-token
```

출력되는 `sk-ant-oat01-...` 토큰을 안전하게 저장.

### 2. 계정 정보 추출 (같은 PC에서)

```bash
cat ~/.claude.json | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(json.dumps(d.get('oauthAccount'), indent=2))"
```

출력:
```json
{
  "accountUuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "emailAddress": "your@email.com",
  "organizationUuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

### 3. DNS 설정

Vercel (또는 DNS 프로바이더)에서:
- `claude.yourdomain.com` → A 레코드 → 서버 공인 IP

### 4. API 키 준비

- [Brave Search API Key](https://api.search.brave.com/app/keys)
- [Exa API Key](https://dashboard.exa.ai/api-keys)
- (선택) Supabase URL + Service Role Key
- (선택) 자체 Mem0 서버 URL + Key

## 설치 (서버에서)

```bash
# 1. 레포 클론
git clone <this-repo> ~/ClaudeCodeWeb
cd ~/ClaudeCodeWeb

# 2. 환경 변수 설정
cp .env.example .env
nano .env    # 사전 준비에서 확보한 값들을 채우기

# 3. 설치 실행 (~15분)
sudo ./setup.sh

# 4. 검증
sudo ./scripts/verify.sh

# 5. OMC 설치
sudo ./scripts/install-omc.sh
```

## 설치 후 확인

1. 브라우저에서 `https://claude.yourdomain.com` 접속
2. cloudcli 초기 비밀번호 설정 (첫 접속 시)
3. 채팅창에서 테스트:
   - `안녕` → Claude 응답 확인
   - `최근 ISMS-P 가이드라인 검색해줘` → Brave/Exa 검색 동작 확인
   - `/deep` → OMC 동작 확인 (설치 후)

## .docx 변환

Claude가 만든 문서를 Word로 변환:

```bash
# 서버에서 (또는 Claude에게 요청)
pandoc /home/claudeweb/workspace/documents/문서.md -o 문서.docx

# 또는 Claude에게 직접:
# "이 문서를 workspace/documents/output.docx로 pandoc 변환해줘"
```

## 운영

### 서비스 관리

```bash
# 상태 확인
sudo systemctl status claudeweb

# 로그 실시간 확인
journalctl -u claudeweb -f

# 수동 재시작
sudo systemctl restart claudeweb
```

### 자동 업데이트

매일 오전 9시 (KST) 자동으로:
- Claude Code CLI 업데이트
- CloudCLI 업데이트
- 서비스 재시작 (~30초 중단)

```bash
# 업데이트 로그 확인
journalctl -t claude-update

# 수동 업데이트
sudo -u claudeweb /home/claudeweb/auto-update.sh
```

### OAuth 토큰 갱신 (1년 주기)

```bash
# 로컬 PC에서
claude setup-token

# 서버에서 .env 수정 후
sudo nano /etc/systemd/system/claudeweb.service
# → CLAUDE_CODE_OAUTH_TOKEN 값 교체
sudo systemctl daemon-reload
sudo systemctl restart claudeweb
```

## 삭제

```bash
sudo ./scripts/uninstall.sh
```

## 파일 구조

```
ClaudeCodeWeb/
├── .env.example          # 환경 변수 템플릿
├── .env                  # 실제 환경 변수 (git 미추적)
├── setup.sh              # 메인 설치 스크립트
├── README.md
└── scripts/
    ├── install-omc.sh    # OMC 설치 가이드
    ├── verify.sh         # 설치 검증
    └── uninstall.sh      # 완전 삭제
```

## 주의사항

- `CLAUDE_CODE_OAUTH_TOKEN`과 `ANTHROPIC_API_KEY`를 **동시에 설정하지 마세요** (충돌)
- OAuth 토큰 유효기간: **1년** (갱신 필요)
- `claude setup-token`은 **브라우저가 있는 PC에서만** 실행 가능
- Max 구독 1개로 **동시 다중 세션 사용 시** rate limit 주의
