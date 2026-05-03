# pod-process-autostart-pattern

K8s pod / systemd-less 환경에서 idempotent 프로세스 자동 시작 패턴.

## 구성

- `SKILL.md` — 본문 (4 옵션 비교 + idempotent 가드 + 검증)
- `templates/bashrc-autostart.template` — `~/.bashrc` 가드 블록 (가장 간단)
- `templates/s6-cont-init.template` — s6-overlay cont-init.d 스크립트
- `scripts/check-autostart.sh.template` — 모든 가드가 정상 발동했는지 검증

## 검증

gem-llm 운영에서 sshd / cloudflared 3개 노드 / supervisor.sh 자동 기동에 사용,
**55h sustained 무사고**. 가드 race 없음 (`pgrep -c` 항상 1).

## 관련 skill

- `k8s-pod-autostart` (4 패턴 K8s 측면)
- `cloudflare-tunnel-ssh-access-pattern` (사용 사례)
- `gem-llm-supervisor` (supervisor 패턴)
