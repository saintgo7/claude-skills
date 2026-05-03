---
name: k8s-cron-alternatives
description: 'K8s pod / 컨테이너 환경 (cron/systemd 미설치)에서 정기 작업 5가지 대체 패턴. 사용 시점 — "cron 없는 환경", "k8s 정기 작업", "watchdog daemon", "k8s CronJob", "external scheduler", "@reboot 대체". in-pod watchdog + K8s CronJob + external scheduler + s6-cron + supervisord.'
---

# k8s-cron-alternatives — K8s/컨테이너 환경 정기 작업 대체 패턴

K8s pod 또는 일반 컨테이너 이미지에는 `crond`/`systemd`/`anacron`이 거의 없다. 그렇다고 정기 작업(daily backup, weekly CVE scan, 5분 health check)이 사라지지는 않는다. 이 skill은 **5가지 검증 가능한 대체 패턴**을 정리한다.

GEM-LLM (3노드 K8s + Cloudflare Tunnel) 운영에서는 cron이 없어 `autostart` / `backup` / `cve-watcher` 모두 supervisor.sh를 통해 수동 호출하고 있다. 이 skill은 그 사례를 일반화한다.

---

## 1. 사용 시점

다음 중 하나라도 해당하면 이 skill을 본다.

- pod / 컨테이너 안에서 daily / weekly / N분 주기 작업이 필요한데 `crond`가 없음
- `s6-overlay` 환경 (`/etc/cont-init.d`, `/etc/services.d`) — 부팅 hook은 있지만 주기 hook이 없음
- 호스트 cron은 있는데 pod 내부 작업을 어떻게 트리거할지 막막
- `@reboot`로 한 번은 돌렸는데 그 후 주기 실행을 못 함
- 클러스터 admin 권한이 없어 `kind: CronJob`을 직접 못 박음

---

## 2. 환경 진단

먼저 **현재 컨테이너에 무엇이 있고 무엇이 없는지** 확인한다.

```bash
# PID 1 — s6-svscan / tini / dumb-init / bash 중 하나
ps -p 1 -o comm=

# cron / systemd / upstart 미설치 여부
which crond cron systemctl initctl 2>/dev/null
ls /etc/cron.d /etc/cron.daily 2>/dev/null

# s6-overlay 여부 (있으면 (4) s6-cron 패턴 가능)
ls /etc/cont-init.d /etc/services.d 2>/dev/null

# K8s pod 여부 (CronJob 권장)
ls /var/run/secrets/kubernetes.io/serviceaccount 2>/dev/null
cat /etc/hostname  # pod name 패턴이면 K8s

# 호스트 접근 가능 여부 (external scheduler 후보)
mount | grep -E "(nodename|hostname)"
```

진단 결과에 따라 패턴 선택이 달라진다.

| 진단 | 권장 패턴 |
|---|---|
| K8s pod + cluster admin O | (2) K8s CronJob |
| K8s pod + cluster admin X | (1) in-pod watchdog |
| s6-overlay 컨테이너 | (4) s6-cron 또는 (1) |
| 일반 Docker + 호스트 접근 O | (3) external scheduler |
| 다중 프로세스 컨테이너 | (5) supervisord |

---

## 3. 5가지 대체 패턴 비교

| # | 패턴 | 정기 가능 | 영구성 | 신뢰성 | 권한 요구 | 적합 |
|---|---|---|---|---|---|---|
| 1 | in-pod watchdog daemon | O | container life | 중 | 컨테이너 내부만 | 즉시 도입 |
| 2 | K8s CronJob | O | 클러스터 영구 | 상 | cluster admin | 권장 (영구) |
| 3 | external scheduler (호스트 cron + ssh) | O | 외부 영구 | 상 | 호스트 root | hybrid |
| 4 | s6-cron 추가 설치 | O | container life | 중 | 이미지 빌드 | s6-overlay 사용 시 |
| 5 | supervisord (cron-like) | O | container life | 중 | 컨테이너 내부 | 다중 프로세스 |

핵심 트레이드오프 — **컨테이너 life**(재생성 시 사라짐) vs **클러스터 영구**(manifest로 박혀 있음). watchdog/s6-cron/supervisord는 모두 "컨테이너가 살아있는 동안만" 동작하므로 pod 재생성 정책과 함께 본다.

---

## 4. (1) In-pod watchdog daemon — 즉시 도입

가장 단순. Python(또는 bash) 무한 루프 + 1분 sleep + cron 표현식 매칭.

핵심 패턴:

```python
# templates/watchdog-daemon.py.template 참조
JOBS = [
    ("backup-db", "0 3 * * *",  "bash /home/jovyan/myapp/scripts/backup-db.sh"),
    ("cve-watch", "0 9 * * 1",  "bash /home/jovyan/myapp/scripts/cve-watcher.sh"),
    ("health",    "*/5 * * * *", "bash /home/jovyan/myapp/scripts/health-check.sh"),
]
while True:
    now = datetime.datetime.now()
    for name, cron, cmd in JOBS:
        if should_run(cron, now) and not_already_fired_this_minute(name, now):
            subprocess.Popen(cmd, shell=True)
    time.sleep(60 - now.second)  # next-minute alignment
```

**장점**
- cron 미설치 환경에서 **즉시** 동작 (Python만 있으면 됨)
- 외부 의존성 0
- JOBS 리스트만 편집하면 추가/제거 즉시 반영

**단점 / 함정**
- watchdog 자체의 자동 시작 필요 → `k8s-pod-autostart` skill 조합 (s6 cont-init 또는 `.bashrc` one-shot)
- 동일 분 내 중복 실행 방지 로직 필요 (`last_fired` dict, 위 템플릿에 포함)
- pod 재생성 시 `last_fired` 초기화 → 부팅 직후 분 boundary와 겹치면 1회 추가 실행 가능
- multi-replica 환경에서는 모든 pod이 동시 실행 → **반드시 leader election 또는 파일/DB 락 추가**

전체 구현은 `templates/watchdog-daemon.py.template` 참조 — `*/5`, `1-5`, `0,15,30` 모두 지원.

---

## 5. (2) K8s CronJob — 권장 (영구)

클러스터 admin이 manifest를 적용한다. **진짜 cron**.

```yaml
# templates/cronjob-manifest.yaml.template 참조
apiVersion: batch/v1
kind: CronJob
metadata:
  name: gem-llm-backup
spec:
  schedule: "0 3 * * *"          # UTC; k8s 1.27+ 는 timeZone 필드 사용
  timeZone: "Asia/Seoul"         # KST 그대로 표기 가능
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: my-app:latest
            command: ["bash", "/home/jovyan/myapp/scripts/backup-db.sh"]
```

**장점**
- 클러스터 수준 영구 — pod 재생성과 무관
- `concurrencyPolicy: Forbid`로 동시 실행 방지 자동 처리
- `successfulJobsHistoryLimit` / `failedJobsHistoryLimit`로 로그 보관
- 멀티 노드에서도 정확히 1번만 실행 (kube-controller-manager가 보장)

**단점 / 함정**
- `kubectl apply` 권한 + cluster admin 협업 필요
- **timeZone 필드**는 k8s 1.27+ — 이전 버전은 schedule 자체를 UTC 기준으로 작성
- Job pod이 메인 앱 pod과 다른 컨테이너 → **메인 pod의 파일 시스템 접근 불가** (PVC 공유 or 별도 이미지에 스크립트 포함)
- `startingDeadlineSeconds` 미설정 시 controller 일시 정지 후 누적 만회 → 부하 폭주 가능

GEM-LLM의 경우 `/home/jovyan/myapp` 경로는 pod 내부 ephemeral이라 PVC 마운트가 우선 필요.

---

## 6. (3) External scheduler (호스트 cron + ssh)

호스트 머신(또는 별도 jump 서버)에 cron이 살아있다면 거기서 ssh로 트리거.

```bash
# 호스트의 /etc/crontab
0 3 * * * root ssh user@pod-ip "bash /home/jovyan/myapp/scripts/backup-db.sh" >> /var/log/backup.log 2>&1
0 9 * * 1 root kubectl exec -n llm gem-llm-pod -- bash /home/jovyan/myapp/scripts/cve-watcher.sh
```

**장점**
- 가장 단순 (호스트 cron만 있으면 됨)
- pod 자체에 변경 0 — 컨테이너 이미지 수정 불필요

**단점**
- 호스트 root 또는 sudo 권한 필요
- ssh key / kubeconfig 관리 부담
- pod IP 변경 시(restart/reschedule) 깨짐 → ServiceName 또는 `kubectl exec -l label=` 권장
- 네트워크 정책으로 막혀 있을 가능성 (Cloudflare Tunnel 환경에서 흔함)

---

## 7. (4) s6-cron 추가 설치 — s6-overlay 환경

PID 1이 `s6-svscan`이라면 s6 생태계의 `s6-cron`(또는 `fcron`/`scron`)을 service로 추가.

```bash
# Dockerfile 또는 cont-init.d 한 번 실행
apt-get install -y --no-install-recommends bcron   # 또는 fcron, scron

# /etc/services.d/cron/run
#!/usr/bin/execlineb -P
exec s6-cron -f -c /etc/cron.d/jobs

# /etc/cron.d/jobs
0 3 * * * jovyan bash /home/jovyan/myapp/scripts/backup-db.sh
0 9 * * 1 jovyan bash /home/jovyan/myapp/scripts/cve-watcher.sh
```

**장점**
- s6 supervision 트리에 자연스럽게 편입 (자동 재시작)
- 진짜 cron 표현식 (DAY-OF-WEEK 별칭 등 모두 지원)

**단점**
- 이미지 빌드 단계에서만 추가 가능 → 운영 중 컨테이너에는 적용 어려움
- s6-overlay 미사용 컨테이너에는 무의미

---

## 8. (5) supervisord (cron-like)

다중 프로세스 컨테이너에서 supervisord를 PID 1로 쓴다면, supervisord 자체에는 cron 기능이 없으므로 **wrapper 스크립트 + supervisord program**으로 구성.

```ini
# /etc/supervisor/conf.d/scheduler.conf
[program:scheduler]
command=python3 /home/jovyan/myapp/scripts/watchdog-daemon.py
autostart=true
autorestart=true
stderr_logfile=/var/log/scheduler.err
stdout_logfile=/var/log/scheduler.out
```

즉, **supervisord는 (1) watchdog 패턴의 영구화 수단**이다. supervisord 자체가 주기성을 제공하지는 않는다. 다중 앱 + cron-like 조합이 필요할 때만 의미가 있음.

---

## 9. 추천 조합 (GEM-LLM 사례)

GEM-LLM 운영 현황 — 3노드 K8s, cluster admin 권한 제한, supervisor.sh가 모든 운영 명령의 entrypoint.

- **즉시 (단기)**: (1) watchdog daemon + `k8s-pod-autostart` skill의 cont-init hook 등록
  - `supervisor.sh start-watchdog` 으로 수동 기동 → bashrc one-shot 또는 s6 cont-init으로 자동화
- **영구 (중장기)**: (2) K8s CronJob — cluster admin과 PVC 공유 협업
  - 현재 `supervisor.sh backup-db` / `supervisor.sh cve-watch` 수동 호출 → CronJob으로 영구화

조합 권고:

```
즉시 도입 (오늘) ────► (1) watchdog + autostart hook
            │
            ▼  (1~2주 검증 후)
영구화 ───────────► (2) CronJob with PVC + concurrencyPolicy: Forbid
```

---

## 10. 흔한 함정

1. **Watchdog 자체의 부팅 자동 시작 (chicken-and-egg)** — watchdog이 backup을 부팅 후 자동 실행해 주지만, watchdog 자신은 누가 띄워주는가? `k8s-pod-autostart` skill의 cont-init hook 또는 supervisord와 반드시 조합.
2. **Pod 재생성 시 watchdog state 손실** — `last_fired`가 메모리에만 있으면 재시작 직후 동일 분 boundary에서 중복 실행 가능. 영구화하려면 파일(`/home/jovyan/state/watchdog.json`)에 직렬화.
3. **Multi-replica 동시 실행** — Deployment replicas=2 이상일 때 watchdog이 모든 pod에서 돌면 backup이 N번 실행. 파일 락 (`flock /tmp/job.lock`) 또는 K8s lease object 사용.
4. **Timezone 혼선 (UTC vs KST)** — K8s CronJob의 `schedule`은 기본 UTC. `timeZone: Asia/Seoul`은 1.27+. watchdog의 `datetime.datetime.now()`는 **컨테이너 TZ env 따라감** → `TZ=Asia/Seoul` 명시 필수.
5. **작업 시간 누적 drift** — 10분 걸리는 작업을 `time.sleep(60)`으로 5분 간격 체크하면 점점 밀림. 다음 분 boundary로 정렬하는 sleep 사용 (위 템플릿 참조).
6. **K8s CronJob `startingDeadlineSeconds` 누락** — controller 일시 중단 후 복구 시 누락된 모든 job을 한꺼번에 실행. 반드시 명시 (예: 300).
7. **Cron 표현식 0=Sunday 7=Sunday 양쪽 허용** — Python `isoweekday() % 7` 변환 필요 (월=1, 일=0).
8. **컨테이너 재시작 vs pod 재생성 구분** — `restartPolicy: Always`로 재시작되면 watchdog state 유지(파일), pod 재생성이면 PVC가 없는 한 손실.

---

## 11. 관련 skill

- `k8s-pod-autostart` — 부팅 시 watchdog 자동 시작 (s6 cont-init / `.bashrc` one-shot / livenessProbe)
- `bash-cli-best-practices` — backup/cve-watch 스크립트 안전 패턴 (`set -euo pipefail`, `flock`)
- `gem-llm-supervisor` — 실제 사례 (`supervisor.sh backup-db` / `cve-watch` 수동 호출)
- `dependency-vulnerability-fix` — cve-watcher가 호출하는 스캔 파이프라인

---

## 12. 템플릿 인덱스

- `templates/watchdog-daemon.py.template` — Python 무한 루프 + 5필드 cron 매칭 + 분 boundary 정렬 + 파일 로그
- `templates/cronjob-manifest.yaml.template` — K8s CronJob 표준 (timeZone, concurrencyPolicy, history limit, deadline 모두 포함)
