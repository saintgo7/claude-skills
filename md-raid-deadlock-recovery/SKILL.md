---
name: md-raid-deadlock-recovery
description: 'Linux md (mdadm) RAID5/6 stripe-cache 데드락 진단 + 안전 재부팅 + 재발 방지 절차. 사용 시점 — "load average 폭증인데 CPU는 idle", "iowait 40%+", "/data 컨테이너 모두 hang", "Prisma/SQL COMMIT 무한 대기", "procs_blocked 20+", "sync_action frozen인데 진행 안 됨", "mdcheck/md0_resync D-state", "raid5_get_active_stripe + kthread_stop 데드락", "RAID 검사 중 시스템 멈춤". 디스크는 정상(SMART PASSED)이지만 md 커널 스레드가 stripe cache 락에서 멈춰 있는 패턴 — 재부팅이 유일 회복. 단, 재부팅 전에 mdcheck 자동 재트리거 + fsck + SSH 백업 + 컨테이너 자동기동을 모두 점검해야 데드락 재발과 접속 두절을 막을 수 있음. abada-65 (Xeon Gold 5215, 28TB RAID5, 136 컨테이너) 2026-05-04 사고 검증.'
---

# md-raid-deadlock-recovery

Linux md/raid 드라이버 stripe-cache 데드락 → 안전 재부팅 → 재발 방지 절차.

## 1. 사용 시점

**모든 조건이 동시에 보이면 이 skill:**

```bash
uptime                              # load avg가 코어 수의 2~3배 이상
top -bn1 | grep Cpu                 # iowait 40%+, idle 50%+
awk '/procs_blocked/' /proc/stat    # 20+ (정상은 0~3)
cat /sys/block/md0/md/sync_action   # frozen 또는 check
cat /sys/block/md0/md/sync_speed    # 0~1KB/s (사실상 정지)
for d in sd[a-z]; do
  echo "$d: $(awk '{print $9}' /sys/block/$d/stat)"
done                                # 전부 0 → 디스크는 idle인데 IO가 안 감
sudo cat /proc/$(pgrep md._resync)/stack
# raid5_get_active_stripe ← 락 보유
# kthread_stop          ← 종료 시도가 같이 잠김
```

증상: `/data` (md array) 위 모든 fsync/COMMIT이 hang. 컨테이너는 "running"이지만 새 쓰기 0. SMART는 PASSED.

## 2. 절대 시도하지 말 것

| 시도 | 결과 |
|---|---|
| `echo idle > /sys/block/md0/md/sync_action` | mdcheck가 이미 시도하다 잠김. 또 하면 그 셸도 같이 잠김 |
| `sudo mdadm --stop /dev/md0` | mount busy로 거절 |
| `kill -9 <D-state PID>` | D-state는 SIGKILL 못 받음 |
| `sudo sync` | hang |
| `sudo umount /data` | mount busy |
| `sudo systemctl stop docker` | 컨테이너 종료 시 fsync 대기로 매우 길어지거나 hang |
| `sudo systemctl stop mdcheck_continue.service` | 데드락된 서비스라 hang |

→ **재부팅이 유일한 회복 수단.** 단 그냥 reboot하면 부팅 후 동일 데드락 재발 또는 SSH 못 들어가서 서버실 가야 함.

## 3. 4가지 위험 점검 (재부팅 전 필수)

### 3-A. RAID 자동 재검사 차단 (필수)

```bash
# scripts/pre-reboot-harden.sh가 자동 실행
sudo systemctl stop mdcheck_start.timer mdcheck_continue.timer
sudo systemctl disable mdcheck_start.timer mdcheck_continue.timer

TS=$(date +%s)
sudo mkdir -p /root/mdcheck-backup/$TS
sudo cp /var/lib/mdcheck/MD_UUID_* /var/lib/mdcheck/.md-check-* /root/mdcheck-backup/$TS/ 2>/dev/null
sudo rm -f /var/lib/mdcheck/MD_UUID_* /var/lib/mdcheck/.md-check-*

sudo cp /etc/default/mdadm /etc/default/mdadm.bak.$TS
sudo sed -i 's/^AUTOCHECK=true/AUTOCHECK=false/; s/^AUTOSCAN=true/AUTOSCAN=false/' /etc/default/mdadm
```

차단 안 하면: 부팅 직후 mdcheck_continue가 `MD_UUID_*` 파일 보고 자동 재시작 → 동일 stripe cache 락에서 재데드락.

### 3-B. 루트 파티션 fsck 사전 스킵 검토

```bash
sudo tune2fs -l /dev/$(findmnt -no SOURCE / | xargs basename) | \
  grep -E "Mount count|Maximum mount count|Filesystem state"
# Maximum mount count = 1 같이 작은 값이면 매 부팅 fsck → 부팅 5~30분 추가
# 'clean' 상태이면 안전하게 스킵 가능:
sudo tune2fs -c 0 /dev/sda6
```

부팅 시간이 길면 그동안 SSH 접속 불가 → 사용자가 서버실 가야 하는 사고로 이어짐 (실제 사례).

### 3-C. SSH 백업 경로 검증 (필수)

직접 SSH(port 22/5022)가 안 떴을 때를 대비해 **Cloudflare Tunnel SSH 우회 경로**가 살아있는지 확인:

```bash
# 서버 측: cloudflared 자동 시작 확인
systemctl is-enabled cloudflared cloudflared-*.service
grep -A1 "ssh://" /etc/cloudflared/config.yml /home/*/.cloudflared/config.yml 2>/dev/null

# 다른 PC에서 실제 접속 테스트 (재부팅 전 반드시 1회):
ssh -o ProxyCommand='cloudflared access ssh --hostname <ssh-tunnel-host>' \
    -p 5022 <user>@<ssh-tunnel-host>
```

`cloudflare-tunnel-ssh-access-pattern` skill의 ProxyCommand 패턴 참고.

### 3-D. 컨테이너 자동기동 정책 점검

```bash
docker ps -a --format '{{.Names}}' | xargs -I{} \
  docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' {} 2>/dev/null | \
  sort | uniq -c | sort -rn

# 'always' / 'unless-stopped' = 자동기동 OK
# 'no' = 부팅 후 수동 docker start 필요. 운영 컨테이너인지 확인
docker ps -a --format '{{.Names}} {{.HostConfig.RestartPolicy.Name}}' | awk '$2=="no"'
```

권장: 명시적 `docker stop`을 일괄 실행하지 말 것 (`unless-stopped`도 stopped 처리됨). 그냥 `sudo reboot`로 dockerd가 SIGTERM 보내게 하면 모두 자동 기동.

## 4. 재부팅 절차

```bash
# 위 4가지 사전 점검 통과 후:
sudo reboot

# reboot 명령 자체가 hang하면 (다른 PC에서 cloudflared SSH 들어가서):
echo b | sudo tee /proc/sysrq-trigger   # 즉시 강제재부팅
# (CONFIG_MAGIC_SYSRQ + /proc/sys/kernel/sysrq=1 필요)
```

## 5. 재부팅 후 즉시 검증

```bash
# scripts/post-reboot-verify.sh가 자동 실행
uptime                                          # load < 코어수
awk '/procs_blocked/' /proc/stat                # 0~3
cat /sys/block/md0/md/sync_action               # idle (반드시!)
cat /proc/mdstat                                # [UUUU] 4/4 active
mountpoint /data && touch /data/.write_test && rm /data/.write_test
docker ps -a --format 'table {{.Names}}\t{{.Status}}' | grep -v "Up "
# 자동기동 안 된 운영 컨테이너 있으면: docker start <name>
```

핵심 도메인 health check:
```bash
for url in https://blog.example.com https://app.example.com; do
  echo -n "$url -> "
  curl -sI -o /dev/null -w "%{http_code}\n" -m 10 "$url"
done
```

## 6. 근본 원인 + 영구 튜닝

`raid5_get_active_stripe` ↔ `kthread_stop` 데드락은 Linux md/raid5 드라이버의 알려진 패턴. 트리거:

1. mdcheck 진행 중 (정합성 검사) sync_action 동시 변경
2. 매우 큰 array(28TB+) + 작은 stripe cache(256 기본)
3. 백그라운드 IO 부하 동시 발생

**영구 완화:**
```bash
# stripe cache 키우기 (기본 256 → 8192)
echo 8192 | sudo tee /sys/block/md0/md/stripe_cache_size

# 영구 적용용 systemd unit (예시)
sudo tee /etc/systemd/system/md-tune.service <<'EOF'
[Unit]
Description=Tune md array params at boot
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo 8192 > /sys/block/md0/md/stripe_cache_size'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable md-tune.service

# mdcheck 재활성화는 신중히 (한 번 검증 끝난 후):
# sudo systemctl enable --now mdcheck_start.timer
# sudo sed -i 's/^AUTOCHECK=false/AUTOCHECK=true/' /etc/default/mdadm
```

## 7. 자산

| 파일 | 용도 |
|---|---|
| `scripts/diagnose.sh` | 데드락 패턴 자동 감지 (load/iowait/sync_action/in_flight/stack) |
| `scripts/pre-reboot-harden.sh` | 3-A + 3-B 자동화 (mdcheck disable, MD_UUID 정리, AUTOCHECK=false, fsck mount-count 0) |
| `scripts/post-reboot-verify.sh` | 5장 검증 (load, sync_action, /data 쓰기, 컨테이너 헬스) |
| `case-studies/abada-int-65-2026-05-04.md` | 실제 사고 인시던트 노트 (진단 evidence + procs/stack/SMART) |

## 8. 데이터 손실 평가

- `in_flight=0` → 디스크에 보내진 IO 없음 → 이미 디스크에 쓰인 데이터 안전
- hang된 COMMIT 트랜잭션은 미커밋 상태로 롤백 (사용자 재시도 필요)
- 페이지 캐시에 dirty인데 못 flush한 데이터는 재부팅 시 손실 가능 (대부분 컨테이너는 fsync로 critical 데이터 즉시 내림 → 영향 작음)
- mismatch_cnt 누적치는 별건. RAID5 단독으로는 어느 쪽이 정답인지 못 가림 → `repair` 자동 실행 금지(데이터 손상 가능). 백업 검증 후 결정.

## 9. 관련 skill

- `cloudflare-tunnel-ssh-access-pattern` — 백업 SSH 경로 (3-C)
- `production-postmortem-pattern` — 사고 후 postmortem 작성
- `deployment-checklist` — 운영 점검 체크리스트
