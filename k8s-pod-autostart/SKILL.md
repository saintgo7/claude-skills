---
name: k8s-pod-autostart
description: 'K8s pod / 컨테이너 환경에서 systemd/cron 없이 서비스 자동 시작. 사용 시점 — "재부팅 후 자동 시작", "systemd 없음", "k8s pod 자동 기동", "s6-overlay 훅", ".bashrc 자동 시작", "컨테이너 cont-init", "cron 없는 환경". 4가지 패턴: s6 cont-init, .bashrc one-shot, watchdog, livenessProbe-driven.'
---

# k8s-pod-autostart

K8s pod / 일반 컨테이너 / JupyterHub spawner 등 **systemd · cron · initctl이 없는 환경**에서 컨테이너 부팅 또는 재기동 시점에 사용자 서비스를 자동으로 띄우는 패턴 모음.

전통적인 리눅스에서는 `systemctl enable my.service` 한 줄이면 끝나지만, K8s pod는 PID 1이 보통 `s6-svscan` / `tini` / `dumb-init`이고 `/etc/systemd`도 없다. cron도 없는 경우가 많다. 이 skill은 그런 환경에서 검증된 4가지 자동 시작 패턴과 트레이드오프를 정리한다.

## 사용 시점 (트리거)

- "파드 재부팅 후 서비스 자동 시작 어떻게 해야 하나" 질문
- `systemctl: command not found`, `crontab: command not found`
- PID 1이 `s6-svscan` / `tini` / `dumb-init` (jupyter/datascience-notebook, code-server 이미지 등)
- 컨테이너 이미지 재빌드 권한이 없는 운영 환경
- `/etc/cont-init.d` 디렉토리는 있는데 활용법을 모를 때
- 파드 재시작 시 vLLM / FastAPI / DB 등이 같이 안 살아나서 매번 수동 기동

## K8s pod 환경 진단

먼저 어떤 자동 시작 수단이 가능한지 확인한다.

```bash
# PID 1이 무엇인가? (s6-svscan / tini / dumb-init / bash)
ps -p 1 -o comm=

# systemd / cron / initctl 부재 확인
which systemctl cron crond initctl 2>&1

# s6-overlay 훅 디렉토리?
ls -la /etc/cont-init.d /etc/services.d 2>&1

# /etc 쓰기 권한? (보통 root이면 가능, non-root user면 불가)
[ -w /etc/cont-init.d ] && echo "writable" || echo "read-only"

# HOME 마운트가 PVC인가? (.bashrc 패턴이 영구 보존되는지 결정)
mount | grep "$HOME"
```

PID 1이 `s6-svscan`이면 (1) cont-init 패턴이 1순위. PID 1이 `tini`/`dumb-init`이면 cont-init이 없으므로 (2)/(3)/(4)로 간다.

## 4가지 패턴 비교

| 패턴 | 시점 | 영구성 | 신뢰성 | 사용 |
|---|---|---|---|---|
| (1) s6 cont-init | 컨테이너 부팅 직후 (PID 1 시작 직후) | overlay FS = ephemeral | 높음 | 이미지 빌드 시 COPY |
| (2) ~/.bashrc 일회성 | 인터랙티브 로그인 | persistent (HOME 마운트 시) | 중간 | 운영자 첫 로그인까지 대기 |
| (3) watchdog daemon | 무한 루프 + sleep | 별도 프로세스 필요 | 높음 | 또 다른 자동 시작 필요 (chicken-and-egg) |
| (4) K8s livenessProbe-driven | healthz 실패 시 K8s가 재시작 | 클러스터 수준 | 가장 높음 | livenessProbe + initContainer 조합 |

핵심 트레이드오프:
- **(1)은 무인 자동화는 되지만 overlay FS라 사라지는 게 함정.** 이미지에 굽거나 install 스크립트로 매번 다시 심어야 한다.
- **(2)는 영구적이지만 "사람이 SSH 들어오기 전까지" 안 켜진다.** 무인 서버 야간 자동 시작 용도로는 불충분.
- **(3)은 강력하지만 watchdog 자체의 자동 시작이 또 필요하다.** 결국 (1) 또는 (4)와 조합해야 한다.
- **(4)가 정공법.** Deployment/StatefulSet 매니페스트를 고칠 수 있을 때만 가능.

## (1) s6 cont-init 훅

PID 1이 `s6-svscan`인 이미지(`jupyter/datascience-notebook`, `linuxserver.io` 류, `lscr.io/linuxserver/*`)에서 사용.

설치 위치: `/etc/cont-init.d/03-<service>` (실행 권한 필수).

훅 본체는 `templates/cont-init-hook.sh` 참조. 핵심 흐름:

1. PVC가 마운트될 때까지 대기 (스택 바이너리가 PVC에 있으면 mount race 방지).
2. GPU 드라이버 / 네트워크 인터페이스 등 외부 의존성 안정화 대기 (sleep 60).
3. `setsid nohup` 으로 서비스 시작을 백그라운드 분리. cont-init 스크립트는 즉시 `exit 0`.

**주의**:
- cont-init 스크립트가 `exit != 0`이면 컨테이너 부팅 자체가 멈춘다. 마지막에 반드시 `exit 0`.
- shebang은 `#!/command/with-contenv bash` 권장 (s6의 환경 변수 inherit).
- `/etc/cont-init.d/`는 컨테이너 overlay FS다. **파드 재생성 시 사라진다.** 영구화 옵션:
  - 가장 깔끔: 자체 이미지를 빌드해 `COPY ./hook /etc/cont-init.d/03-<service>`.
  - 차선: PVC에 hook 사본을 두고 부팅 후 매번 `cp` 하는 install 스크립트를 (2) 패턴으로 호출.

## (2) ~/.bashrc 일회성 hook

HOME이 PVC로 마운트되어 영속적인 환경(JupyterHub, code-server, 일반 dev pod)에서 사용. 사용자가 처음 SSH/터미널을 열 때 서비스가 죽어 있으면 살린다.

핵심 요건 4가지:
- **`$PS1` 체크**: non-interactive shell(scp, ssh-with-command 등)에서는 절대 실행 금지.
- **flock**: 동일 부팅 사이클에서 동시 다중 로그인 다중 실행 방지.
- **부팅 사이클 stamp**: `/proc/1` mtime을 비교해 한 부팅 사이클당 1회만 실행. (`/tmp`는 보통 컨테이너 재기동마다 비워지므로 stamp 자체가 자연 만료된다.)
- **healthz 사전 체크**: 이미 떠 있으면 skip.

`~/.bashrc`에 추가하는 정확한 형식 (변수 `PROJECT_ROOT`, `SUPERVISOR`, `HEALTHZ_URL`, `SERVICE` 치환):

```bash
# >>> <SERVICE> autostart >>>
# 인터랙티브 로그인 시 스택이 내려가 있으면 자동 기동.
if [ -n "$PS1" ] && [ -x "<SUPERVISOR>" ]; then
  (
    LOCK="/tmp/<SERVICE>-autostart.lock"
    STAMP="/tmp/<SERVICE>-autostart.stamp"
    # 같은 부팅 사이클에서 한 번만 실행
    if [ ! -f "$STAMP" ] || [ "$(stat -c %Y /proc/1 2>/dev/null)" != "$(cat "$STAMP" 2>/dev/null)" ]; then
      (
        flock -n 9 || exit 0
        code=$(curl -s -m 2 -o /dev/null -w "%{http_code}" "<HEALTHZ_URL>" 2>/dev/null || echo 000)
        if [ "$code" != "200" ]; then
          echo "[<SERVICE>] 스택이 내려가 있어 자동 기동합니다 (백그라운드)..."
          setsid nohup bash "<SUPERVISOR>" start \
            >> "<LOG_DIR>/bashrc-autostart.log" 2>&1 < /dev/null &
        fi
        stat -c %Y /proc/1 2>/dev/null > "$STAMP"
      ) 9>"$LOCK"
    fi
  )
fi
# <<< <SERVICE> autostart <<<
```

`scripts/install-hooks.sh`가 이 블록을 자동으로 만들어 `.bashrc`에 추가한다.

## (3) watchdog daemon

별도 프로세스가 무한 루프로 healthz를 폴링하고 죽으면 살린다.

```bash
# /usr/local/bin/<service>-watchdog.sh
#!/bin/bash
while true; do
  code=$(curl -s -m 2 -o /dev/null -w "%{http_code}" "$HEALTHZ_URL" || echo 000)
  if [ "$code" != "200" ]; then
    setsid nohup bash "$SUPERVISOR" start </dev/null >>"$LOG" 2>&1 &
  fi
  sleep 30
done
```

장점: (1)/(2)와 달리 운영 중 service crash도 복구.
**한계: watchdog 자체의 자동 시작이 또 필요하다.** chicken-and-egg. 결국:
- (1) cont-init이 watchdog을 띄움
- 또는 (4) K8s sidecar 컨테이너로 watchdog만 분리 운영

## (4) K8s livenessProbe-driven

매니페스트(Deployment/StatefulSet)를 고칠 수 있는 경우의 정공법.

```yaml
spec:
  template:
    spec:
      initContainers:
        - name: bootstrap-service
          image: <same-image>
          command: ["/bin/bash", "-c", "<SUPERVISOR> start"]
      containers:
        - name: app
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 120
            periodSeconds: 30
            failureThreshold: 3
          readinessProbe:
            httpGet: { path: /healthz, port: 8080 }
            initialDelaySeconds: 60
```

- `initContainer`: 본 컨테이너 시작 전 1회 service start.
- `livenessProbe`: 실패 누적 시 K8s가 컨테이너 자체를 재시작 → PID 1 재시작 → (1)/(2) 훅이 재발동.

**가장 신뢰성 높음.** 단, 운영팀이 매니페스트를 못 만지면 적용 불가.

## 추천 조합 — (1) + (2) 듀얼

이미지 재빌드 권한이 없고 매니페스트도 못 고치는 일반 운영 환경의 권장안:

1. **install-hooks.sh로 (1) cont-init + (2) bashrc 둘 다 심는다.**
2. cont-init이 살아 있으면 무인 자동 시작 OK. 운영자 로그인 불필요.
3. cont-init이 overlay FS와 함께 사라졌어도 운영자 첫 로그인 시 (2) bashrc 훅이 살림.
4. 양쪽 다 안 되면 수동으로 `bash <SUPERVISOR> start`.

이 조합은 PID 1이 s6-svscan + HOME이 PVC인 일반 노트북/데이터 사이언스 이미지에서 검증된 패턴이다.

## 검증

설치 후 dry-run:

```bash
# (1) cont-init 훅 권한 확인
ls -la /etc/cont-init.d/03-<service>
# rwx 하나 이상 있는지 (실행 비트 누락이 흔한 함정)

# (2) bashrc 훅 추가 확인
grep -A1 "<SERVICE> autostart" ~/.bashrc

# (2) 일회성 stamp 동작 확인 — 새 셸 두 번 열어도 두 번째는 skip
bash -lc 'true'
cat /tmp/<SERVICE>-autostart.stamp
# 두 번째 셸은 stamp가 있어 skip되어야 함

# 실서비스 healthz
curl -s http://localhost:8080/healthz
```

파드 재생성 시뮬레이션이 위험한 운영 환경에서는 다음으로 대용:

```bash
# 서비스 강제 종료 후 새 셸 → (2) 자동 기동 확인
bash <SUPERVISOR> stop
rm -f /tmp/<SERVICE>-autostart.stamp   # stamp 강제 만료
bash -lc 'true'    # 새 셸이 발동시켜야 함
sleep 30 && curl -s http://localhost:8080/healthz
```

## 흔한 함정

- **cont-init 실행 비트 누락**: `chmod +x` 또는 `install -m 0755`. 권한 없으면 s6가 그냥 skip.
- **flock 미사용**: 동시 다중 SSH 세션이 supervisor를 동시 N번 띄워 포트 바인드 실패 race.
- **`$PS1` 체크 누락**: scp / `ssh host cmd` / VS Code remote의 보조 셸에서 `.bashrc`가 비대화형으로 실행되며 매번 supervisor가 발동되는 사고.
- **stamp를 PVC에 두기**: stamp는 `/tmp` (컨테이너 ephemeral)에 둬야 한다. PVC에 두면 파드 재생성 후에도 남아 있어 자동 기동이 영영 발동 안 함.
- **cont-init에서 동기 service start**: cont-init이 끝날 때까지 PID 1이 다른 cont-init을 못 돌린다. 반드시 `setsid nohup ... &`로 분리.
- **cont-init 마지막 `exit 0` 누락**: service start가 실패하면 컨테이너 부팅 자체가 막힐 수 있음.

## 파일

- `scripts/install-hooks.sh` — `<service-name> <start-command>` 받아서 (1)+(2) 양쪽 설치, `--uninstall` 지원
- `templates/cont-init-hook.sh` — s6 cont-init 표준 형식 (sleep + setsid nohup start)
