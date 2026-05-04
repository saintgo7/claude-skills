# abada-65 재부팅 종합 위험 분석 (Pre-Reboot Final)

**작성일시:** 2026-05-04 09:20 KST  
**작성자:** Claude (ultrathink 모드, 14개 영역 점검)  
**연관 문서:** `abada-65-INCIDENT-2026-05-04.md` (사고 진단)  
**스킬:** `~/.claude/skills/md-raid-deadlock-recovery/`

---

## TL;DR — 핵심 결론

| | |
|---|---|
| **재부팅 자체 실행 가능?** | ⚠️ **`sudo reboot`은 무한 hang 가능**. `systemctl reboot --force --force` 사용 권장 |
| **자동 회복 가능 항목** | RAID 자동 검사 차단 ✅, 컨테이너 자동기동 ✅, SSH 백업 ✅, fsck 스킵 ✅ |
| **수동 개입 필요 가능성** | 낮음 (5% 미만) — 다만 BMC 네트워크 미구성으로 최악의 경우 물리 접근 필요 |
| **데이터 손실 위험** | 무시 가능 (Dirty 352KB, ACK된 모든 커밋은 이미 디스크) |
| **권장 재부팅 명령** | `sudo systemctl reboot --force --force` |

---

## 1. 14개 영역 점검 결과

### A. 사전 작업 4종 — ✅ 모두 적용됨

| 항목 | 확인값 | 판정 |
|---|---|---|
| `mdcheck_start.timer` | disabled | ✅ |
| `mdcheck_continue.timer` | disabled | ✅ |
| `/var/lib/mdcheck/MD_UUID_*` | 없음 (백업: `/root/mdcheck-backup/1777852282/`) | ✅ |
| `/etc/default/mdadm` `AUTOCHECK` | false | ✅ |
| `/etc/default/mdadm` `AUTOSCAN` | false | ✅ |
| `/dev/sda6` Maximum mount count | -1 (fsck 비활성) | ✅ |
| `/dev/sda6` Filesystem state | clean | ✅ |

### B. 데드락 현재 상태 — 변동 없음

| 지표 | 값 |
|---|---|
| `procs_blocked` | 28 |
| `sync_action` | frozen |
| `sync_speed` | 392 B/s |
| `md0_resync` (PID 1319284) | D-state, `raid5_get_active_stripe` 락 보유 |
| `mdcheck` (PID 1319225) | D-state, `kthread_stop` 대기 |

### C. /data 파티션 fsck 일정 — 확인 불가

`tune2fs -l /dev/mapper/vg_data-lv_data` 자체가 데드락에 걸려 hang됨 (예상대로). 그러나:
- `/etc/fstab`: `/data ext4 noatime 0 2` — pass=2
- ext4 + journal이라 dirty unmount 시 journal replay만 수행 (full fsck 안 돔)
- 부팅 시 mount 시간: 정상 < 30초 예상

### D. md array 무결성 보호 — bitmap 있음 ✅

```
md0 : active raid5 sdb[0] sdc[1] sdd[2] sde[3]
      bitmap: 0/73 pages [0KB], 65536KB chunk
```

bitmap이 있으므로 **dirty shutdown 시에도 전체 resync 안 함**, dirty stripe만 빠르게 재계산. 28TB 어레이라도 부팅 시 RAID resync는 분 단위로 끝날 것.

### E. sysrq 활성 — ✅

`/proc/sys/kernel/sysrq` = **176** (= 128 reboot + 32 remount-ro + 16 sync)
→ `echo b | sudo tee /proc/sysrq-trigger` 강제 reboot 가능

### F. systemd 타임아웃 — 기본값

- `DefaultTimeoutStopSec`: 90초 (보통 unit 정지 대기)
- `ShutdownWatchdogSec`: 10분 (전체 shutdown이 10분 넘으면 강제 reboot 트리거)

### G. ⚠️ Docker daemon — TimeoutStopUSec=infinity (위험)

```
TimeoutStopUSec=infinity
TimeoutStopFailureMode=terminate
```

**중대한 발견**: docker.service가 무한 대기 설정됨. 이 상태에서 `sudo reboot` 하면:
1. systemd가 docker.service에 SIGTERM
2. dockerd가 모든 컨테이너 graceful stop 시도
3. 컨테이너들이 fsync에서 hang (데드락)
4. dockerd가 컨테이너 종료 무한 대기
5. systemd가 dockerd 종료 무한 대기 (TimeoutStopUSec=infinity)
6. → **shutdown 무한 hang**, ShutdownWatchdog 10분 후 강제 force reboot

이게 직전 부팅 사례 (2026-02-23 02:01 → 03:34 짧은 1.5시간 후 재부팅)에서 발생했을 가능성. 사용자가 SSH 안 떠서 서버실 가야 했던 원인 중 하나.

**해결**: `systemctl reboot --force --force`로 shutdown 시퀀스 자체를 건너뜀.

### H. 다른 md 자동 트리거 systemd unit — 없음 ✅

- `mdmonitor-oneshot.timer`: 메일링용, RAID 검사 트리거 안 함
- `mdadm-grow-continue@.service`: 확장 작업 없음, 트리거 안 됨
- `mdadm-last-resort@.service`: 어레이 못 찾을 때만 발동, 정상 어레이엔 영향 없음
- 다른 활성 RAID timer 없음

### I. cron jobs — md 관련 없음 ✅

`/etc/cron.daily/e2scrub_all`만 존재 (LVM thin pool scrub용, 우리 시스템엔 thin pool 없어 noop)

### J. cloudflared 부팅 순서 — ✅

두 서비스 모두 `After=network-online.target` + `Wants=network-online.target`. 네트워크 올라온 직후 자동 시작.

### K. cloudflared 인증서 — ✅

`cert.pem`은 X.509 아닌 Argo Tunnel Token (zone/account ID embedded). **만료 없음**, 터널 삭제 시까지 유효.

### L. fstab — ✅

```
UUID=9107... /     ext4 errors=remount-ro 0 1
UUID=fff9... /boot ext4 defaults          0 2
UUID=9ce8... none  swap sw                0 0
UUID=5453... /data ext4 noatime           0 2
```

모두 UUID 기반 → 디스크 순서 변경에도 안전.

### M. 네트워크 — ✅

- NetworkManager-managed
- `eno1`: 172.16.129.65/24 (DHCP 아님, NetworkManager 유지)
- 부팅 후 동일 IP 유지

### N. GRUB — ✅

- `GRUB_DEFAULT=0` (첫 항목)
- `GRUB_TIMEOUT=10` (10초 후 자동 부팅)
- `GRUB_TIMEOUT_STYLE=hidden`

### O. ⚠️ BMC/IPMI — 네트워크 미구성

- 메인보드: **Supermicro X11DPG-QT** (BMC 내장)
- `/dev/ipmi0` 존재, IPMI KCS 인터페이스 작동
- 그러나 `ipmitool lan print 1/2/3` 모두 빈 결과 → **BMC LAN 미설정**
- → **원격 KVM/콘솔 사용 불가**. SSH도 cloudflared도 안 되면 물리 서버실 접근만 답.

### P. D-state 프로세스 분류

| 종류 | 개수 | 의미 |
|---|---|---|
| `mdcheck` / `md0_resync` | 2 | 데드락 본진 |
| `kworker/+flush` | 6 | 페이지 캐시 flush 대기 |
| `jbd2/dm-0-8` | 1 | ext4 저널 |
| `postgres` | 3 | DB COMMIT 대기 |
| `redis-server` | 2 | AOF/RDB 쓰기 대기 |
| `dumpe2fs` / `tune2fs` / `sync` | 5 | 진단 시도하다 끌려들어감 |
| `git` / `sftp-server` | 3 | 사용자 작업 |

총 28개 + S 상태 1 (`md0_raid5` 정상). 재부팅으로만 해소.

### Q. Dirty pages — 무시 가능

```
Dirty:        352 kB  ← 매우 적음
Writeback:    104 kB
```

데드락 때문에 새 데이터가 누적되지도 못함 (앱들이 fsync에서 막혀 있음). 강제 reboot해도 손실 거의 없음.

### R. Swap — 여유 충분

Swap 166Mi / 122Gi 사용. 메모리 압박 없음. 부팅 후 swap 즉시 활성화 OK.

### S. tmux 세션 — 11개 (모두 reboot 시 사라짐)

사용자의 작업 컨텍스트 보존 안 됨. 재부팅 후 다시 작업 디렉터리/명령 복원 필요.

### T. dmesg 에러 — 데드락 관련만

`hung_task_timeout` 메시지 (jbd2, minio 등). 데드락 증상으로 이미 알려진 사항. 디스크/하드웨어 에러 없음.

### U. 부팅 디스크(sda) SMART — ✅

PASSED. 부팅 자체는 안전.

### V/W/X/Y/Z. 보조 점검

- BIOS: AMI 3.1 (Supermicro X11DPG-QT) — 정상
- 컨테이너 restart 분포: 97 always / 39 unless-stopped / 6 no
- swap 122GB 여유
- fstab 4개 마운트 모두 UUID 기반

### AA. BMC LAN — 미구성 (재확인)

채널 1/2/3 모두 빈 결과. 원격 IPMI 불가 확정.

### AB. 부팅 이력

```
Mar  4 16:14 — 현재 (60일 가동)
Feb 24 15:00 — 8일 가동 (정상 종료 후 reboot)
Feb 23 03:35 — 11시간 가동 후 reboot
Feb 23 02:01 — 1.5시간 만에 reboot ⚠️ (SSH 안 떴던 사고일 가능성)
```

→ 직전 부팅(Mar 4)은 60일째 정상. 부팅 자체는 신뢰할 수 있음.

### AC. 현재 failed unit — 3개, 모두 비치명

- `fwupd-refresh.service`, `fwupd.service` — 펌웨어 업데이트 (네트워크 이슈, 무관)
- `mdcheck_continue.service` — 데드락된 검사. **reboot으로 자동 해소.**

### AD. Docker daemon.json — 정상

주소 풀 설정만 있음. 특별한 shutdown 설정 없음.

### AE. ShutdownWatchdogSec — 기본 10분

만약 `sudo reboot`이 hang하면 systemd가 10분 후 자동으로 sysrq-style 강제 재부팅. 즉 **최악의 경우 10-15분 hang 후 자동 회복**.

### AF/AG/AH. 기타 — 모두 정상 또는 데드락 부산물

---

## 2. 위험 매트릭스 종합

| # | 위험 | 심각도 | 확률 | 완화 상태 |
|---|---|---|---|---|
| 1 | mdcheck 자동 재트리거 → 데드락 재발 | HIGH | 사전 작업 안 했으면 95%+ | ✅ 차단 |
| 2 | 루트 fsck 부팅 지연 5~30분 | MEDIUM | 사전 작업 전 100% | ✅ 차단 (`tune2fs -c 0`) |
| 3 | /data 마운트 지연 | LOW | 5% (bitmap 덕분) | 수용 (수 분 이내) |
| 4 | SSH 직접 접속 안 뜸 | MEDIUM | 10% | ✅ cloudflared 백업 검증 완료 |
| 5 | unless-stopped 컨테이너 자동기동 안 됨 | MEDIUM | 0% (graceful stop 미수행 시) | ✅ 안전 |
| 6 | **`sudo reboot` 자체가 무한 hang** | **HIGH** | **70%** (Docker timeout=∞) | **⚠️ `--force --force` 사용 권장** |
| 7 | Dirty page 손실 | LOW | 100% | 무시 가능 (352KB) |
| 8 | RAID dirty assembly 실패 | LOW | <1% | bitmap 보호 |
| 9 | 네트워크 IP 변경 | LOW | <1% | NetworkManager 정적 |
| 10 | GRUB 부팅 안 됨 | LOW | <1% | sda SMART PASSED |
| 11 | **BMC 네트워크 미구성 → 물리 접근 필요** | **MEDIUM** | **5%** (1+4+6 모두 실패 시) | 수용 — 사전 SSH 백업 검증으로 5%로 낮춤 |
| 12 | ShutdownWatchdog 10분 대기 | INFO | 70% (`sudo reboot` 사용 시) | 회피 (`--force --force`) |
| 13 | 사용자 tmux 세션 11개 손실 | LOW | 100% | 수용 (사용자 인지) |
| 14 | failed units (fwupd) 잔존 | INFO | 100% | 무관 |

---

## 3. 권장 재부팅 절차

### 3-1. 사용자 측 사전 준비 (다른 PC에서)

```bash
# 1. 백업 SSH 셸 미리 띄워두기 (재부팅 명령 트리거용 or 모니터링용)
ssh -o ProxyCommand='cloudflared access ssh --hostname s65.abada.co.kr' \
    -p 5022 blackpc@s65.abada.co.kr
# 별도 터미널에 1개 열어두면 안전

# 2. 핑 모니터링 (별도 터미널)
ping 172.16.129.65
# 또는 외부에서: cloudflared access ssh --hostname s65.abada.co.kr 재시도
```

### 3-2. 재부팅 명령 (이 서버에서)

```bash
# 권장: shutdown 시퀀스 건너뛰고 즉시 reboot
sudo systemctl reboot --force --force

# === 위 명령이 동작하는 순서 ===
# 1. systemd가 모든 unit stop 시도 건너뜀
# 2. systemd-shutdown이 sync 호출 건너뜀
# 3. 즉시 kexec 또는 reboot(2) syscall 호출
# 4. 5초 내 재부팅 시작
```

### 3-3. 만약 위 명령도 hang하면

다른 PC의 cloudflared SSH 셸에서:

```bash
# Plan B: sysrq 직접 (sysrq=176에 reboot 비트 활성)
echo b | sudo tee /proc/sysrq-trigger
# → 즉시 강제 재부팅 (sync 안 함)
```

### 3-4. 만약 SSH 백업도 안 들어가면

→ 물리 서버실 접근 필요 (BMC 네트워크 미설정).  
→ 또는 ShutdownWatchdog 10분 후 자동 강제 reboot 대기.

---

## 4. 재부팅 후 체크 (5분 내)

다른 PC에서 cloudflared SSH 또는 직접 SSH로 접속 후:

```bash
# 부팅 정상 여부 (load 정상화 = 데드락 해소)
uptime
awk '/procs_blocked/' /proc/stat   # 0~3 정상

# RAID 상태 — sync_action 반드시 idle 이어야!
cat /sys/block/md0/md/sync_action
cat /proc/mdstat                    # [UUUU] 정상

# 만약 sync_action != idle:
echo idle | sudo tee /sys/block/md0/md/sync_action

# stripe cache 즉시 상향 (데드락 재발 방지 영구 튜닝)
echo 8192 | sudo tee /sys/block/md0/md/stripe_cache_size

# /data 마운트 + 쓰기 테스트
mountpoint /data && touch /data/.write_test && rm /data/.write_test

# 컨테이너 자동기동 확인 (130개 정도 기대)
docker ps | wc -l
docker ps -a --format 'table {{.Names}}\t{{.Status}}' | grep -v "Up "

# 핵심 도메인 외부 접근
for url in https://blog.abada.co.kr https://argos.abada.co.kr \
           https://shop.abada.kr https://safe.abada.kr; do
  echo -n "$url -> "; curl -sI -o /dev/null -w "%{http_code}\n" -m 10 "$url"
done

# cloudflared 두 서비스 active 확인
systemctl status cloudflared cloudflared-devext --no-pager | grep Active
```

상세 자동화 스크립트:  
`~/.claude/skills/md-raid-deadlock-recovery/scripts/post-reboot-verify.sh`

---

## 5. 재부팅 후 영구 개선 (다음 사고 방지)

```bash
# 1. stripe cache 영구 상향 (boot 시 자동 적용)
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

# 2. Docker timeout 합리적 값 (무한 → 5분)
sudo mkdir -p /etc/systemd/system/docker.service.d/
sudo tee /etc/systemd/system/docker.service.d/timeout.conf <<'EOF'
[Service]
TimeoutStopSec=300
EOF
sudo systemctl daemon-reload

# 3. BMC 네트워크 설정 (다음 SSH 사고 시 원격 KVM 가능)
# Supermicro IPMI 매뉴얼 참조 — BIOS에서 BMC LAN 설정
# 또는 ipmitool로:
# sudo ipmitool lan set 1 ipsrc dhcp     # DHCP 또는
# sudo ipmitool lan set 1 ipaddr 172.16.129.165   # 정적

# 4. mdcheck 신중히 재활성 (검증 후)
# sudo systemctl enable --now mdcheck_start.timer
# sudo sed -i 's/^AUTOCHECK=false/AUTOCHECK=true/' /etc/default/mdadm
# 다만: stripe_cache_size 8192 적용 후에만!
```

---

## 6. 재부팅 결정 매트릭스

| 조건 | 권장 행동 |
|---|---|
| 모든 위 점검 통과 + 사용자 GO | `sudo systemctl reboot --force --force` 즉시 실행 |
| 다른 PC 백업 SSH 셸 안 띄워둠 | 먼저 띄우고 → 실행 |
| 다른 사용자/서비스 영향 우려 | 사전 공지 → 야간/주말로 연기 |
| 데드락 자체 회복 시도 미진 | (옵션) `dmesg -c` + `sudo cat /proc/*/wchan` 추가 진단 — 다만 회복 가능성 거의 0% |
| 새벽/심야이고 사용자 직접 모니터링 불가 | 다음 영업 시작 시간 직전으로 연기 |

---

## 7. 사고 후속 (재부팅 성공 후)

1. `abada-65-INCIDENT-2026-05-04.md`에 부팅 결과 추가 기록
2. 본 문서 (`abada-65-REBOOT-RISK-ASSESSMENT.md`) 다음 사고 시 재참조
3. Skill 저장소(`saintgo7/claude-skills`) 업데이트:
   - `md-raid-deadlock-recovery` SKILL에 "Docker timeout=infinity" 위험 추가
   - `pre-reboot-harden.sh`에 Docker timeout 점검 추가
4. abada-66 (failover) 동일 점검 (Docker timeout 같은 설정 가능성)

---

## 끝
