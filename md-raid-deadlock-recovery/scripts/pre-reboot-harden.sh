#!/bin/bash
# md-raid-deadlock-recovery / pre-reboot-harden.sh
#
# 데드락 상태에서 안전 재부팅 전 4가지 사전 작업:
#   3-A. mdcheck 자동 재시작 차단 (timer disable + MD_UUID 파일 제거 + AUTOCHECK=false)
#   3-B. 루트 fsck mount-count 비활성 (부팅 시간 단축)
#   3-C. SSH 백업 경로 점검 (cloudflared 자동시작 확인)
#   3-D. 컨테이너 restart 정책 분포
#
# 모든 작업은 / 파티션 위에서만 일어남 → md 데드락과 무관, 안전.
# sync_action은 절대 변경하지 않음 (변경 시 셸이 같이 잠김).
#
# Usage: sudo ./pre-reboot-harden.sh

set -uo pipefail
TS=$(date +%s)

cyan()  { echo -e "\n\033[36m=== $* ===\033[0m"; }
ok()    { echo "  ✓ $*"; }
warn()  { echo "  ⚠ $*"; }

# ---------------------------------------------------------
cyan "3-A. mdcheck 자동 재시작 차단"

systemctl stop    mdcheck_start.timer mdcheck_continue.timer 2>/dev/null || true
systemctl disable mdcheck_start.timer mdcheck_continue.timer 2>/dev/null || true
ok "mdcheck timer stop + disable"

if ls /var/lib/mdcheck/MD_UUID_* >/dev/null 2>&1; then
  mkdir -p /root/mdcheck-backup/$TS
  cp -av /var/lib/mdcheck/. /root/mdcheck-backup/$TS/ >/dev/null
  rm -f /var/lib/mdcheck/MD_UUID_* /var/lib/mdcheck/.md-check-*
  ok "MD_UUID/.md-check 파일 백업 후 제거 (백업: /root/mdcheck-backup/$TS/)"
else
  ok "/var/lib/mdcheck에 트리거 파일 없음 (이미 정리됨)"
fi

if [ -f /etc/default/mdadm ]; then
  cp /etc/default/mdadm /etc/default/mdadm.bak.$TS
  sed -i 's/^AUTOCHECK=true/AUTOCHECK=false/; s/^AUTOSCAN=true/AUTOSCAN=false/' /etc/default/mdadm
  grep -E "^AUTOCHECK|^AUTOSCAN" /etc/default/mdadm | sed 's/^/    /'
  ok "/etc/default/mdadm AUTOCHECK/AUTOSCAN=false (백업: /etc/default/mdadm.bak.$TS)"
fi

# ---------------------------------------------------------
cyan "3-B. 루트 fsck mount-count 점검"

ROOT_DEV=$(findmnt -no SOURCE /)
echo "  / = $ROOT_DEV"
mc=$(tune2fs -l "$ROOT_DEV" 2>/dev/null | awk -F: '/Maximum mount count/ {print $2}' | xargs || echo unknown)
state=$(tune2fs -l "$ROOT_DEV" 2>/dev/null | awk -F: '/Filesystem state/ {print $2}' | xargs || echo unknown)
echo "  state=$state, max mount count=$mc"
if [ "$state" = "clean" ] && [ "$mc" != "-1" ] && [ "$mc" -ge 0 ] 2>/dev/null && [ "$mc" -le 5 ]; then
  tune2fs -c 0 "$ROOT_DEV" >/dev/null
  ok "tune2fs -c 0 적용 (다음 부팅 fsck 스킵, 5~30분 단축)"
else
  ok "fsck 회피 불필요 (이미 -1이거나 state≠clean — fsck 진행 권장)"
fi

# ---------------------------------------------------------
cyan "3-C. SSH 백업 경로 점검"

systemctl is-enabled ssh 2>/dev/null | sed 's/^/    ssh.service: /'
for cf in $(systemctl list-units --type=service --all | awk '/cloudflared/ {print $1}' | grep -v "service$" | head; \
            systemctl list-units --type=service --all | awk '/cloudflared/ {print $1}' | head); do
  systemctl is-enabled "$cf" 2>/dev/null | sed "s|^|    $cf: |"
done

echo "  --- ssh ProxyCommand 라우트 ---"
grep -B1 "ssh://" /etc/cloudflared/*.yml /home/*/.cloudflared/*.yml 2>/dev/null | \
  grep -E "hostname|ssh://" | sed 's/^/    /' | head -10

echo
warn "다른 PC에서 'ssh -o ProxyCommand=\"cloudflared access ssh --hostname <host>\" ...' 실접속 1회 검증할 것"

# ---------------------------------------------------------
cyan "3-D. 컨테이너 자동기동 정책 분포"

if command -v docker >/dev/null; then
  docker ps -a --format '{{.Names}}' | while read c; do
    docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$c" 2>/dev/null
  done | sort | uniq -c | sort -rn | sed 's/^/    /'

  no_restart=$(docker ps -a --format '{{.Names}} {{.HostConfig.RestartPolicy.Name}}' 2>/dev/null | awk '$2=="no" || $2==""')
  if [ -n "$no_restart" ]; then
    echo
    warn "다음 컨테이너는 부팅 후 자동 기동 안 됨 (운영 컨테이너인지 확인):"
    echo "$no_restart" | sed 's/^/      /'
  fi
fi

# ---------------------------------------------------------
cyan "사전 작업 완료"

cat <<'EOF'
다음 단계:
  1. 다른 PC에서 백업 SSH 실접속 1회 검증 (위 cloudflared ProxyCommand)
  2. 사용자 GO 사인 후:
       sudo reboot
  3. 만약 reboot이 hang하면 (다른 PC에서 cloudflared SSH 들어가서):
       echo b | sudo tee /proc/sysrq-trigger
  4. 부팅 후 post-reboot-verify.sh 실행
EOF
