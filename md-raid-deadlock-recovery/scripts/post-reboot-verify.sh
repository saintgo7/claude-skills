#!/bin/bash
# md-raid-deadlock-recovery / post-reboot-verify.sh
#
# 재부팅 후 5분 내 실행. md 데드락 재발 안 했는지 + 서비스 정상 기동했는지 검증.
#
# Usage: sudo ./post-reboot-verify.sh [md_device]

set -uo pipefail
MD="${1:-md0}"
fail=0

cyan()  { echo -e "\n\033[36m=== $* ===\033[0m"; }
ok()    { echo "  ✓ $*"; }
bad()   { echo "  ✗ $*"; fail=$((fail+1)); }

cyan "[1] 호스트 부하"
load=$(awk '{print $1}' /proc/loadavg)
cores=$(nproc)
blocked=$(awk '/procs_blocked/ {print $2}' /proc/stat)
echo "    load=$load  cores=$cores  procs_blocked=$blocked"
if (( $(awk -v l="$load" -v c="$cores" 'BEGIN{print (l<c*1.5)}') )); then ok "load 정상"; else bad "load 높음"; fi
[ "${blocked:-0}" -lt 5 ] && ok "procs_blocked 정상" || bad "procs_blocked=${blocked}"

cyan "[2] RAID 상태"
cat /proc/mdstat | sed 's/^/    /'
action=$(cat /sys/block/$MD/md/sync_action 2>/dev/null || echo missing)
[ "$action" = "idle" ] && ok "sync_action=idle" || bad "sync_action=$action ← 자동 검사 다시 시작! 즉시 echo idle > /sys/block/$MD/md/sync_action"

state=$(grep -oE "\[[U_]+\]" /proc/mdstat | head -1)
[[ "$state" == *"_"* ]] && bad "디스크 누락: $state" || ok "어레이 활성: $state"

cyan "[3] /data 마운트 + 쓰기 테스트"
DATA_MOUNT="${DATA_MOUNT:-/data}"
if mountpoint -q "$DATA_MOUNT"; then
  ok "$DATA_MOUNT 마운트됨"
  if timeout 10 touch "$DATA_MOUNT/.write_test_$$" 2>/dev/null; then
    rm -f "$DATA_MOUNT/.write_test_$$"
    ok "쓰기/제거 정상"
  else
    bad "쓰기 실패 또는 hang — 다시 데드락 가능성"
  fi
else
  bad "$DATA_MOUNT 마운트 안 됨"
fi

cyan "[4] 컨테이너 자동 기동"
if command -v docker >/dev/null; then
  total=$(docker ps -a -q | wc -l)
  up=$(docker ps -q | wc -l)
  echo "    전체: $total / Up: $up"
  not_up=$(docker ps -a --format '{{.Names}} {{.Status}}' | grep -v "Up " | head -10)
  if [ -n "$not_up" ]; then
    bad "기동 안 된 컨테이너:"
    echo "$not_up" | sed 's/^/      /'
    echo "    → 운영 서비스면: docker start <name>"
  else
    ok "모두 Up"
  fi
fi

cyan "[5] cloudflared 터널 상태"
for unit in $(systemctl list-units --type=service --all | awk '/cloudflared/ {print $1}' | grep "service$"); do
  active=$(systemctl is-active "$unit" 2>/dev/null)
  [ "$active" = "active" ] && ok "$unit: active" || bad "$unit: $active"
done

cyan "[6] 핵심 도메인 헬스체크"
HEALTH_URLS="${HEALTH_URLS:-}"
if [ -z "$HEALTH_URLS" ]; then
  echo "    HEALTH_URLS 환경변수 없음 — 스킵"
  echo "    예: HEALTH_URLS='https://blog.example.com https://app.example.com' $0"
else
  for url in $HEALTH_URLS; do
    code=$(curl -sI -o /dev/null -w "%{http_code}" -m 10 "$url")
    if [[ "$code" =~ ^[23] ]]; then
      ok "$url -> $code"
    else
      bad "$url -> $code"
    fi
  done
fi

cyan "결과"
if [ "$fail" -eq 0 ]; then
  echo "  모든 점검 통과. 정상 회복."
  exit 0
else
  echo "  $fail 항목 실패. 위 ✗ 항목 확인."
  exit 1
fi
