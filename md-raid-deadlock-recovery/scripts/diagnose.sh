#!/bin/bash
# md-raid-deadlock-recovery / diagnose.sh
#
# Linux md/raid stripe-cache 데드락 패턴 자동 감지.
# 7개 지표를 동시에 보고 모두 일치하면 데드락으로 판정.
#
# Usage: sudo ./diagnose.sh [md_device]
#        기본 md_device = md0

set -uo pipefail
MD="${1:-md0}"
COLOR_R='\033[31m'; COLOR_G='\033[32m'; COLOR_Y='\033[33m'; COLOR_N='\033[0m'
hits=0

ok()    { echo -e "  ${COLOR_G}OK${COLOR_N}    $*"; }
warn()  { echo -e "  ${COLOR_Y}WARN${COLOR_N}  $*"; hits=$((hits+1)); }
crit()  { echo -e "  ${COLOR_R}CRIT${COLOR_N}  $*"; hits=$((hits+2)); }

echo "=== md-raid-deadlock 진단 ($MD) ==="
echo

# 1) load avg vs core count
load=$(awk '{print $1}' /proc/loadavg)
cores=$(nproc)
ratio=$(awk -v l="$load" -v c="$cores" 'BEGIN{printf "%.1f", l/c}')
echo "[1] load average / cores"
if (( $(awk -v r="$ratio" 'BEGIN{print (r>2)}') )); then
  crit "load=$load, cores=$cores (ratio=${ratio}x, 정상은 1x 이하)"
else
  ok "load=$load, cores=$cores (ratio=${ratio}x)"
fi
echo

# 2) iowait
iowait=$(top -bn1 | grep "Cpu(s)" | sed 's/.*,\s*\([0-9.]*\)\s*wa.*/\1/')
echo "[2] iowait%"
if (( $(awk -v w="$iowait" 'BEGIN{print (w>20)}') )); then
  crit "iowait=${iowait}% (정상은 한 자리수)"
else
  ok "iowait=${iowait}%"
fi
echo

# 3) procs_blocked
blocked=$(awk '/procs_blocked/ {print $2}' /proc/stat)
echo "[3] D-state 프로세스 (procs_blocked)"
if [ "${blocked:-0}" -ge 10 ]; then
  crit "procs_blocked=$blocked (정상은 0~3)"
elif [ "${blocked:-0}" -ge 5 ]; then
  warn "procs_blocked=$blocked"
else
  ok "procs_blocked=$blocked"
fi
echo

# 4) sync_action
if [ -r "/sys/block/$MD/md/sync_action" ]; then
  action=$(cat /sys/block/$MD/md/sync_action)
  speed=$(cat /sys/block/$MD/md/sync_speed 2>/dev/null || echo 0)
  echo "[4] sync_action / sync_speed"
  if [ "$action" = "frozen" ] && [ "$speed" -lt 10000 ]; then
    crit "sync_action=$action, sync_speed=${speed}B/s — 사실상 정지"
  elif [ "$action" != "idle" ] && [ "$speed" -lt 100000 ]; then
    warn "sync_action=$action, sync_speed=${speed}B/s"
  else
    ok "sync_action=$action, sync_speed=${speed}B/s"
  fi
else
  warn "/sys/block/$MD/md/sync_action 없음 — md device 확인"
fi
echo

# 5) per-disk in_flight
echo "[5] 디스크별 in_flight"
all_zero=1
for d in $(ls /sys/block/ | grep -E "^sd[a-z]$|^nvme"); do
  inflight=$(awk '{print $9}' /sys/block/$d/stat 2>/dev/null || echo 0)
  echo "    $d: $inflight"
  [ "$inflight" -ne 0 ] && all_zero=0
done
if [ "$all_zero" -eq 1 ] && [ "${blocked:-0}" -ge 10 ]; then
  crit "모든 디스크 in_flight=0인데 ${blocked}개가 D-state — 디스크는 idle이나 RAID 레이어가 잠김"
fi
echo

# 6) md resync 커널 스레드 stack
resync_pid=$(pgrep -f "${MD}_resync" 2>/dev/null | head -1)
if [ -n "$resync_pid" ]; then
  echo "[6] ${MD}_resync 커널 스택 (PID $resync_pid)"
  stack=$(cat /proc/$resync_pid/stack 2>/dev/null | head -3)
  echo "$stack" | sed 's/^/    /'
  if echo "$stack" | grep -q "raid5_get_active_stripe\|raid6_get_active_stripe"; then
    crit "stripe cache 락에 걸림 — 데드락 시그니처 일치"
  fi
fi
echo

# 7) SMART 빠른 체크 (selected disks)
echo "[7] SMART overall (sd[a-z] 첫 4개만)"
for d in $(ls /sys/block/ | grep "^sd[a-z]$" | head -4); do
  result=$(sudo smartctl -H "/dev/$d" 2>/dev/null | grep "overall-health" | awk -F: '{print $2}' | xargs)
  if [ "$result" = "PASSED" ]; then
    echo "    $d: PASSED"
  else
    warn "    $d: $result"
  fi
done

echo
echo "=== 결과 ==="
if [ "$hits" -ge 4 ]; then
  echo -e "${COLOR_R}데드락 패턴 매우 강함 (score=$hits)${COLOR_N}"
  echo "→ pre-reboot-harden.sh 실행 후 reboot. SKILL.md 3장 참고."
  exit 2
elif [ "$hits" -ge 2 ]; then
  echo -e "${COLOR_Y}의심 (score=$hits)${COLOR_N} — 30분 모니터링 권장"
  exit 1
else
  echo -e "${COLOR_G}정상 (score=$hits)${COLOR_N}"
  exit 0
fi
