#!/usr/bin/env bash
# K8s pod 자동 시작 훅 설치 — (1) s6 cont-init + (2) ~/.bashrc 일회성 듀얼.
#
# 사용:
#   install-hooks.sh <service-name> <supervisor-path> [healthz-url] [boot-delay]
#   install-hooks.sh --uninstall <service-name>
#
# 예:
#   install-hooks.sh my-app /home/user/my-app/scripts/supervisor.sh \
#                    http://localhost:8080/healthz 60
#
# 동작:
#   1) /etc/cont-init.d 가 쓰기 가능하면 cont-init 훅 설치 (overlay FS, ephemeral)
#   2) ~/.bashrc 에 일회성 훅 블록 추가 (백업 후) — flock + /proc/1 stamp + $PS1 체크

set -euo pipefail

MARKER_BEGIN_TPL="# >>> %s autostart >>>"
MARKER_END_TPL="# <<< %s autostart <<<"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEMPLATE="$SCRIPT_DIR/../templates/cont-init-hook.sh"
TS=$(date +%Y%m%d-%H%M%S)
BASHRC="${HOME}/.bashrc"

usage() { sed -n '2,12p' "$0"; exit 1; }

uninstall() {
  local SERVICE="$1"
  local MARKER_BEGIN MARKER_END DST_HOOK
  MARKER_BEGIN=$(printf "$MARKER_BEGIN_TPL" "$SERVICE")
  MARKER_END=$(printf "$MARKER_END_TPL" "$SERVICE")
  DST_HOOK="/etc/cont-init.d/03-${SERVICE}"

  echo "[install-hooks] uninstall '$SERVICE'"
  if [ -e "$DST_HOOK" ] && [ -w "/etc/cont-init.d" ]; then
    rm -f "$DST_HOOK"
    echo "  - removed $DST_HOOK"
  fi
  if grep -q "$MARKER_BEGIN" "$BASHRC" 2>/dev/null; then
    cp "$BASHRC" "$BASHRC.bak.$TS"
    awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
      $0 ~ b {skip=1; next}
      $0 ~ e {skip=0; next}
      !skip
    ' "$BASHRC" > "$BASHRC.new" && mv "$BASHRC.new" "$BASHRC"
    echo "  - removed bashrc block (backup: $BASHRC.bak.$TS)"
  fi
  echo "[install-hooks] done"
}

if [ "${1:-}" = "--uninstall" ]; then
  [ -z "${2:-}" ] && usage
  uninstall "$2"; exit 0
fi

[ $# -lt 2 ] && usage

SERVICE="$1"
SUPERVISOR="$2"
HEALTHZ_URL="${3:-http://localhost:8080/healthz}"
BOOT_DELAY="${4:-5}"
PROJECT_ROOT="$(dirname "$(dirname "$SUPERVISOR")")"
LOG_DIR="$PROJECT_ROOT/_logs"
DST_HOOK="/etc/cont-init.d/03-${SERVICE}"
MARKER_BEGIN=$(printf "$MARKER_BEGIN_TPL" "$SERVICE")
MARKER_END=$(printf "$MARKER_END_TPL" "$SERVICE")

mkdir -p "$LOG_DIR"
echo "[install-hooks] install '$SERVICE'"
echo "  supervisor : $SUPERVISOR"
echo "  healthz    : $HEALTHZ_URL"

# (1) s6 cont-init
if [ -d /etc/cont-init.d ] && [ -w /etc/cont-init.d ]; then
  if [ ! -f "$TEMPLATE" ]; then
    echo "  - WARN: template $TEMPLATE not found, skip cont-init"
  else
    sed -e "s|<SERVICE>|$SERVICE|g" \
        -e "s|<PROJECT_ROOT>|$PROJECT_ROOT|g" \
        -e "s|<SUPERVISOR>|$SUPERVISOR|g" \
        -e "s|<BOOT_DELAY>|$BOOT_DELAY|g" \
        "$TEMPLATE" > "$DST_HOOK"
    chmod 0755 "$DST_HOOK"
    echo "  - cont-init installed: $DST_HOOK (ephemeral on overlay FS)"
  fi
else
  echo "  - skip cont-init: /etc/cont-init.d not writable (non-s6 image or non-root)"
fi

# (2) bashrc 일회성 훅
if grep -q "$MARKER_BEGIN" "$BASHRC" 2>/dev/null; then
  echo "  - bashrc hook already present, skip"
else
  cp "$BASHRC" "$BASHRC.bak.$TS"
  cat >> "$BASHRC" <<EOF

$MARKER_BEGIN
if [ -n "\$PS1" ] && [ -x "$SUPERVISOR" ]; then
  (
    LOCK="/tmp/${SERVICE}-autostart.lock"
    STAMP="/tmp/${SERVICE}-autostart.stamp"
    if [ ! -f "\$STAMP" ] || [ "\$(stat -c %Y /proc/1 2>/dev/null)" != "\$(cat "\$STAMP" 2>/dev/null)" ]; then
      (
        flock -n 9 || exit 0
        code=\$(curl -s -m 2 -o /dev/null -w "%{http_code}" "$HEALTHZ_URL" 2>/dev/null || echo 000)
        if [ "\$code" != "200" ]; then
          echo "[$SERVICE] stack down, auto-starting (background)..."
          setsid nohup bash "$SUPERVISOR" start \\
            >> "$LOG_DIR/bashrc-autostart.log" 2>&1 < /dev/null &
        fi
        stat -c %Y /proc/1 2>/dev/null > "\$STAMP"
      ) 9>"\$LOCK"
    fi
  )
fi
$MARKER_END
EOF
  echo "  - bashrc hook installed (backup: $BASHRC.bak.$TS)"
fi

echo "[install-hooks] done"
