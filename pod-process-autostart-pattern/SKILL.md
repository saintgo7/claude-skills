---
name: pod-process-autostart-pattern
description: 'K8s pod / systemd 없는 환경에서 idempotent 프로세스 자동 시작 패턴. 사용 시점 — "no systemd", "K8s pod 자동 시작", "재시작 후 프로세스 사라짐", "supervisor 없이", "pgrep 가드", "~/.bashrc autostart", "s6 cont-init", "lifecycle.postStart". 4 옵션 비교 + idempotent 가드 + 검증.'
---

# pod-process-autostart-pattern

K8s pod / Docker container / Jupyter dev container 같이 **systemd가 없거나 사용자 권한이 부족한 환경**에서 sshd · cloudflared · supervisor · cron 대체 등 영속 프로세스를 **idempotent**하게 자동 시작하는 패턴 모음.

핵심 아이디어 두 가지:

1. **idempotent 가드** (`pgrep -f` 로 이미 떠있으면 skip)
2. **발동 시점** (셸 진입 / pod 시작 / K8s lifecycle / supervisord)

gem-llm 운영에서 sshd, cloudflared 3개 노드 터널, vLLM 듀얼 supervisor 등을 이 패턴으로 자동 기동하여 **55h 무사고 검증** 완료.

## 1. 사용 시점

- K8s pod 환경 (systemd 없음, 또는 사용자 jovyan 권한만 있음)
- Docker container — entrypoint 외 추가 영속 프로세스가 필요
- Jupyter pod / dev container 같은 임시 컨테이너
- 사용자 영역에서 sshd / cron 대체 / cloudflared / 자체 supervisor 띄우기
- pod 재시작마다 수동으로 프로세스 다시 띄우는 것이 지겨움

## 2. 4 옵션 비교

| 옵션 | 발동 시점 | 권한 | 권장 |
|---|---|---|---|
| `~/.bashrc` 가드 | 셸 진입 시 | 사용자 | 가장 간단, 인프라 변경 X |
| s6-overlay `cont-init.d` | pod 시작 시 | container | s6 이미 사용 중인 이미지 |
| supervisord | 영속적 | container | 복잡한 의존 그래프 |
| K8s `lifecycle.postStart` | pod 시작 시 | K8s admin | manifest 수정 권한 있을 때 |

선택 기준: **이미지 재빌드 권한이 없으면 `~/.bashrc` 가드, 셸 진입이 없는 환경이면 s6/lifecycle, 복잡한 의존성이면 supervisord**.

관련 skill `k8s-pod-autostart` 가 4개 패턴의 K8s 측면을 더 깊게 다룬다. 이 skill은 **idempotent 가드** + **gem-llm 검증 사례** 에 집중한다.

## 3. ~/.bashrc 가드 패턴 (가장 간단)

```bash
# === AUTOSTART_<NAME> (idempotent) ===
mkdir -p "$HOME/.local/log"
if [ -f "$HOME/.config/<name>/config" ] && \
   ! pgrep -f "<unique-process-pattern>" >/dev/null 2>&1; then
  nohup <command> >> "$HOME/.local/log/<name>.log" 2>&1 &
fi
```

핵심 4가지:

- `pgrep -f` 로 idempotent 가드 (이미 떠있으면 skip → 중복 실행 방지)
- 충분히 unique 한 패턴 (다른 프로세스와 매칭 X — 예: `cloudflared tunnel run` 전체)
- `nohup ... &` 로 백그라운드, 셸이 종료되어도 살아남음
- 로그 영속 (`~/.local/log/<name>.log`)

`AUTOSTART_<NAME>` 주석 태그를 두면 추후 `grep -q AUTOSTART_<NAME> ~/.bashrc` 로 중복 추가를 방지할 수 있다.

## 4. 셸 안 진입하는 환경 → s6-overlay

PID 1이 `s6-svscan` 인 이미지 (jupyter/datascience-notebook 등) 에서는 `/etc/cont-init.d/` 디렉토리가 pod 시작마다 실행된다.

`/etc/cont-init.d/50-cloudflared`:

```sh
#!/bin/sh
# /etc/cont-init.d/50-cloudflared
if ! pgrep -f cloudflared >/dev/null; then
  nohup cloudflared tunnel run >/var/log/cloudflared.log 2>&1 &
fi
```

권한: `chmod 755`. 파일명 앞 `NN` 으로 실행 순서 제어 (`50-cloudflared` < `60-supervisor`). 실패시 pod 부팅 실패하므로 `exit 0` 명시 권장.

## 5. supervisord (복잡한 의존성)

여러 프로세스가 의존 관계로 묶여 있다면 supervisord 가 표준.

`/etc/supervisor/conf.d/services.conf`:

```ini
[program:sshd]
command=/usr/sbin/sshd -D -f /home/jovyan/.ssh/sshd_config
autorestart=true
priority=10

[program:cloudflared]
command=/home/jovyan/.local/bin/cloudflared tunnel run
autorestart=true
priority=20
```

이 skill의 범위는 **외부 supervisord 없이 가벼운 가드**까지. 복잡한 경우 supervisord 또는 s6-rc 사용 권장.

## 6. K8s lifecycle.postStart

manifest 수정 권한이 있다면 가장 깔끔하다.

```yaml
lifecycle:
  postStart:
    exec:
      command:
        - /bin/sh
        - -c
        - |
          /usr/sbin/sshd -f /home/jovyan/.ssh/sshd_config
          nohup cloudflared tunnel run >> /var/log/cloudflared.log 2>&1 &
```

주의: `postStart` 는 **blocking** — 빠르게 끝나야 하므로 모든 명령은 `&` 또는 `nohup` 으로 백그라운드.

## 7. 검증

```bash
# 새 셸 진입해 가드 발동 확인
bash -lc 'pgrep -af sshd; pgrep -af cloudflared'

# 또는 직접 PID 추적
ps -ef | grep -E '(sshd|cloudflared)' | grep -v grep

# 가드 자체 테스트 (이미 떠있으면 두 번째 실행 시 skip 되는가)
bash ~/.bashrc; bash ~/.bashrc
pgrep -c -f cloudflared    # 1 이어야 함 (2 이면 가드 실패)
```

`scripts/check-autostart.sh.template` 에 패턴별 검증 스크립트가 있다.

## 8. 영속화 — 어디에 두느냐

- 영속 볼륨 (`~/`, `/home/<user>/`) 안에 두기 (pod 재시작 후에도 살아남음)
- `/tmp` 는 절대 X (재시작 시 사라짐)
- SSH host key (`/etc/ssh/ssh_host_*`), TLS 인증서, cloudflared 토큰 모두 영속 볼륨
- 로그도 영속 볼륨 (`~/.local/log/`) — `/var/log` 는 컨테이너 ephemeral

K8s 에서는 PVC mount path 안에 둔다. JupyterHub 의 경우 `/home/jovyan/` 이 보통 PVC.

## 9. 흔한 함정 (8 표)

| 증상 | 원인 | 해결 |
|---|---|---|
| 가드 중복 (셸 진입 마다 재추가) | bashrc 여러 번 추가됨 | `grep -q AUTOSTART_<NAME>` 후 한 번만 |
| 새 셸 진입 안 함 | nohup 없음 / cron 호출 등 | s6 또는 lifecycle.postStart |
| pgrep 매칭 너무 광범위 | 패턴이 너무 짧음 (`cloud`) | full command path 사용 |
| 로그 디렉토리 없음 | `mkdir -p` 누락 | 가드 앞에 `mkdir -p` 추가 |
| host key 매번 새로 생성 | tmpfs 에 둠 | 영속 볼륨으로 이동 |
| `~/.bashrc` 가 sourcing 안 됨 | non-login 셸만 진입 | `~/.profile` 에도 sourcing 추가 |
| pod 만 재시작 (셸 진입 X) | autostart 안 됨 | s6/lifecycle 사용 |
| sshd 거부 (Permission denied) | 권한 (chmod) 잘못 | `~/.ssh` 700, sshd_config 600 |

## 10. gem-llm 검증 사례

| 자동 시작 대상 | 패턴 | 가드 |
|---|---|---|
| sshd (cloudflare tunnel SSH access) | `~/.bashrc` | `pgrep -f "/usr/sbin/sshd .*jovyan"` |
| cloudflared (3 노드 별 터널) | `~/.bashrc` | `pgrep -f "cloudflared tunnel run <UUID>"` |
| supervisor.sh (vLLM 듀얼 + gateway + admin-ui) | `~/.bashrc` | `pgrep -f "supervisor.sh"` |
| vLLM Qwen Coder | supervisor.sh 내부 | `pgrep -f "vllm serve.*Qwen"` |

55h sustained 운영, 가드 race 없음 (`pgrep -c` 결과 항상 1), 로그 회전도 안정.

## 11. 디버그

- 가드 발동 안 함: `bash -x ~/.bashrc 2>&1 | tail -30` 으로 if 분기 확인
- nohup 즉시 종료: `tail ~/.local/log/<name>.log` (대개 권한 / 누락된 환경 변수)
- pgrep 잘못 매칭: 더 specific 패턴 (`pgrep -f "exact full command"`)
- pod 만 재시작 (셸 X): s6 cont-init 으로 마이그레이션
- `pgrep -c -f <pat>` 가 2 이상: 가드가 race / 중복 → 가드 자체 logic 검토

## 12. 관련 skill

- `k8s-pod-autostart` — K8s 4 패턴 비교 (s6 / .bashrc / watchdog / livenessProbe)
- `cloudflare-tunnel-ssh-access-pattern` — autostart 사용 사례 (sshd + cloudflared)
- `k8s-cron-alternatives` — cron 없는 환경 스케줄링
- `gem-llm-supervisor` — supervisor.sh 패턴 (vLLM 듀얼 + gateway)
