#!/usr/bin/env bash
# setup-tunnel.sh — Cloudflare Tunnel 1-shot 셋업
#
# 사용:
#   ./setup-tunnel.sh <tunnel-name> <hostname> <local-port>
#
# 예:
#   ./setup-tunnel.sh my-app app.example.com 8080
#
# 사전 조건:
#   1. Cloudflare 계정 + 도메인이 Cloudflare DNS로 위임됨
#   2. `cloudflared tunnel login` 한 번 실행해 ~/.cloudflared/cert.pem 보유
#
# 동작:
#   - cloudflared 설치 확인 (없으면 안내만, 자동 설치는 안 함)
#   - tunnel 생성 (이미 있으면 재사용)
#   - DNS 라우팅 등록
#   - ~/.cloudflared/config-<tunnel>.yml 생성
#   - foreground 실행 (Ctrl-C 종료)
#
# 안전:
#   - rm -rf 사용 안 함
#   - 기존 config 파일은 .bak으로 백업

set -euo pipefail

# ── 인자 ───────────────────────────────────────────────────────────────────
if [ $# -ne 3 ]; then
  echo "Usage: $0 <tunnel-name> <hostname> <local-port>"
  echo "Example: $0 my-app app.example.com 8080"
  exit 1
fi

TUNNEL_NAME="$1"
HOSTNAME="$2"
LOCAL_PORT="$3"

CF_DIR="${HOME}/.cloudflared"
CONFIG_FILE="${CF_DIR}/config-${TUNNEL_NAME}.yml"

# ── 1. cloudflared 설치 확인 ───────────────────────────────────────────────
if ! command -v cloudflared >/dev/null 2>&1; then
  echo "ERROR: cloudflared not found in PATH."
  echo ""
  echo "Install:"
  echo "  Linux (sudo):  curl -L -o cloudflared.deb \\"
  echo "                   https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
  echo "                 sudo dpkg -i cloudflared.deb"
  echo "  Linux (user):  curl -L -o ~/.local/bin/cloudflared \\"
  echo "                   https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
  echo "                 chmod +x ~/.local/bin/cloudflared"
  echo "  macOS:         brew install cloudflared"
  exit 1
fi

echo "[1/5] cloudflared: $(cloudflared --version 2>&1 | head -1)"

# ── 2. cert.pem 확인 ───────────────────────────────────────────────────────
if [ ! -f "${CF_DIR}/cert.pem" ]; then
  echo "ERROR: ${CF_DIR}/cert.pem not found."
  echo "Run 'cloudflared tunnel login' first (one-time browser OAuth)."
  exit 1
fi

echo "[2/5] cert.pem present"

# ── 3. tunnel 생성 (이미 있으면 재사용) ───────────────────────────────────
if cloudflared tunnel list 2>/dev/null | awk '{print $2}' | grep -qx "${TUNNEL_NAME}"; then
  echo "[3/5] Tunnel '${TUNNEL_NAME}' already exists — reusing"
  TUNNEL_UUID=$(cloudflared tunnel list 2>/dev/null \
    | awk -v n="${TUNNEL_NAME}" '$2==n {print $1}' | head -1)
else
  echo "[3/5] Creating tunnel '${TUNNEL_NAME}'..."
  cloudflared tunnel create "${TUNNEL_NAME}"
  TUNNEL_UUID=$(cloudflared tunnel list 2>/dev/null \
    | awk -v n="${TUNNEL_NAME}" '$2==n {print $1}' | head -1)
fi

if [ -z "${TUNNEL_UUID:-}" ]; then
  echo "ERROR: failed to resolve tunnel UUID"
  exit 1
fi
echo "       UUID: ${TUNNEL_UUID}"

CREDS_FILE="${CF_DIR}/${TUNNEL_UUID}.json"
if [ ! -f "${CREDS_FILE}" ]; then
  echo "ERROR: credentials file ${CREDS_FILE} missing"
  exit 1
fi

# ── 4. DNS 라우팅 ──────────────────────────────────────────────────────────
echo "[4/5] Routing DNS: ${HOSTNAME} → ${TUNNEL_NAME}"
cloudflared tunnel route dns "${TUNNEL_NAME}" "${HOSTNAME}" || \
  echo "       (DNS may already be routed — continuing)"

# ── 5. config.yml 생성 ────────────────────────────────────────────────────
if [ -f "${CONFIG_FILE}" ]; then
  cp "${CONFIG_FILE}" "${CONFIG_FILE}.bak"
  echo "[5/5] Backed up existing config → ${CONFIG_FILE}.bak"
fi

cat > "${CONFIG_FILE}" <<EOF
tunnel: ${TUNNEL_UUID}
credentials-file: ${CREDS_FILE}

ingress:
  - hostname: ${HOSTNAME}
    service: http://localhost:${LOCAL_PORT}
  - service: http_status:404
EOF

echo "       Wrote ${CONFIG_FILE}"
echo ""
echo "── Starting tunnel (Ctrl-C to stop) ──────────────────────────────────"
echo "Test from another shell:"
echo "  curl -s -m 5 -o /dev/null -w \"%{http_code}\\n\" https://${HOSTNAME}/"
echo ""
exec cloudflared tunnel --config "${CONFIG_FILE}" run "${TUNNEL_NAME}"
