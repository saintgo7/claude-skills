---
name: blue-green-deployment-pattern
description: 'LLM 서빙 (vLLM 등) blue/green 무중단 cutover 패턴. 사용 시점 — "vllm 버전 업그레이드", "blue green 배포", "0 다운타임 전환", "서빙 cutover", "rollback runbook", "flashinfer cache 격리". 격리 venv + 새 포트 검증 + 트래픽 전환 + rollback runbook.'
---

# blue-green-deployment-pattern

LLM 서빙 (vLLM, FastAPI Gateway 등) 의 무중단/저중단 cutover 패턴. 운영 인스턴스 (blue) 를 끄지 않은 채 새 인스턴스 (green) 를 검증하고, 트래픽을 전환하고, 실패 시 rollback 한다.

이 skill 의 핵심 명제 — cutover 는 "재시작이 아니라 두 인스턴스의 공존" 으로 풀어야 한다. 새 venv + 새 포트 + 검증 단계 + 인터랙티브 승인 + rollback runbook 이 한 묶음이다. GEM-LLM `vllm-env` → `vllm-env-020` (vLLM 0.19.1 → 0.20.x) 작업에서 도출.

## 1. 사용 시점

- "vllm 버전 업그레이드 무중단으로 가능?"
- "blue/green 배포 패턴이 LLM 서빙에 적용되나"
- "rollback 5분 안에 가능해야 함"
- "flashinfer cache 가 새 venv 와 충돌"
- "TP=4 / TP=8 풀 GPU 차지 중인데 어떻게 검증?"
- "Cloudflare Tunnel 끊김 없이 cutover"
- transformers / FastAPI / vLLM 메이저 업그레이드
- 모델 weight 교체 (Gemma → Qwen 등)

## 2. blue/green 흐름

```
[운영 (blue)]            [신규 (green)]
:8001 vLLM 0.19.1         (없음)
:8002 vLLM 0.19.1         (없음)
        |
        v
1. 격리 venv (vllm-env-NEW) 설치 + 검증
   ↓
2. 새 포트 (8003/8004) 에 green 시작 (작은 GPU 메모리 비율)
   ↓
3. 헬스체크 + smoke test (단일 chat completion)
   ↓
4. (사용자 승인) — interactive read -p
   ↓
5. blue 정지 (8001/8002 stop)
   ↓
6. green 재시작 (8001/8002 풀 GPU 비율)
   ↓
7. 부하 테스트 + 헬스체크
   ↓
8. 실패 시 rollback (blue 복귀)
```

핵심 — 1~4 단계는 운영에 영향 0. 5~7 만 다운타임 (2~5분, 모델 로딩). 8 은 안전망.

## 3. 핵심 안전 장치 5가지

### (1) 격리 venv

새 venv (`/home/jovyan/vllm-env-NEW`) 를 별도로 만든다. 기존 `vllm-env` 는 건드리지 않는다.

```bash
python3 -m venv /home/jovyan/vllm-env-020
/home/jovyan/vllm-env-020/bin/pip install vllm==0.20.0
```

이렇게 하면 의존성 충돌 (vLLM 0.20 이 transformers 4.46 요구, 기존은 4.45 등) 을 회피하고, rollback 시 옛 venv 가 그대로 남아 있다. 자세한 절차는 `vllm-bootstrap` skill 참조.

### (2) flashinfer JIT 캐시 격리 (함정)

**함정**: `~/.cache/flashinfer` 는 venv 별로 격리되지 않는다. 이전 venv 의 헤더/CUDA 경로가 cache 안에 hardcoded 되어 있어, 새 venv 에서 첫 빌드가 깨진다 (`could not find <torch/extension.h>` 등).

**해결**: cutover 직전에 캐시를 옆으로 치워 둔다.

```bash
mkdir -p _trash
mv ~/.cache/flashinfer _trash/flashinfer-cache-old-$(date +%Y%m%d)
# rollback 시 mv 로 되돌리면 옛 venv 도 빌드 안 깨진다
```

캐시는 새 venv 가 처음 부팅될 때 자동 재생성된다 (~30~60초 지연).

### (3) 인터랙티브 승인 게이트

스크립트가 자동으로 blue 를 죽이지 않게 한다.

```bash
echo ""
echo "Green smoke test passed. Ready to cutover blue → green."
read -p "Proceed with cutover? (yes/no): " confirm
[ "$confirm" = "yes" ] || { echo "Aborted by user."; exit 0; }
```

이 한 줄이 "smoke 는 통과했지만 실제 응답 품질이 이상한" 사례를 차단한다.

### (4) GPU 메모리 fence

blue 가 풀 비율 (TP=4, `--gpu-memory-utilization 0.90`) 로 8개 GPU 중 4개를 차지 중이라면, green 은 다음 4개에 작은 비율로 띄운다.

- green smoke 단계: `--gpu-memory-utilization 0.10`, TP=1 정도
- blue 정지 후: green 을 풀 비율 (`0.90`, TP=4) 로 **재시작**

같은 프로세스가 메모리를 키울 수 없으므로 한 번 stop / start 가 필요하다 (이게 다운타임의 본질).

### (5) Rollback runbook

cutover 가 실패한 즉시 (사용자가 "아니 이상해" 라고 말하는 순간) 실행할 명령을 한 파일에 미리 적어 둔다.

```bash
# rollback.sh
kill -TERM $(cat _logs/vllm-NEW.pid) 2>/dev/null || true
mv _trash/flashinfer-cache-old-* ~/.cache/flashinfer 2>/dev/null || true
~/vllm-env/bin/python -m vllm.entrypoints.openai.api_server \
    --port 8001 --model ... &
```

승인 게이트 후 10초 안에 결정해야 하는 상황에서, 명령을 새로 짜면 늦다.

## 4. 단계별 검증 게이트

각 단계 후 다음을 통과해야 진행:

| 단계 | 검증 명령 | 통과 조건 |
|---|---|---|
| venv 설치 | `python -c "import vllm; print(vllm.__version__)"` | 버전 출력 |
| 의존성 | `pip check` | 충돌 0 |
| green 부팅 | `curl :8003/v1/models` | HTTP 200 |
| smoke | `curl :8003/v1/chat/completions ...` | 응답 본문 OK |
| cutover 후 | 모든 컴포넌트 + Gateway 헬스 | 4/4 200 |
| 부하 | locust 50동접 60초 | 100% 성공, p99 < 10s |

검증 실패 시 다음 단계로 절대 넘어가지 않는다 (`set -e` + early exit).

## 5. 실측 다운타임

GEM-LLM 0.19 → 0.20 검증:

- blue stop → green 재시작 = 2~5분 (모델 로딩)
- Cloudflare Tunnel 은 살아 있고, FastAPI Gateway 도 살아 있음
- 사용자가 보는 증상: Gateway 가 upstream 으로 502 / 503 일시 (재시도 권장 응답 포함 가능)

진정한 0 다운타임 (0초) 은 두 인스턴스를 동시에 풀 GPU 로 띄울 수 있는 환경에서만 가능 — 단일 노드 8xGPU 에서 TP=4 두 개 = 8 GPU 동시 사용 불가하면 어차피 stop/start 필요.

## 6. cutover 절차 표준 10단계

`scripts/cutover.sh.template` 가 이 순서로 동작:

1. 사전 점검 (blue 헬스, 디스크, GPU 여유)
2. flashinfer cache 격리 (`_trash/` 로 mv)
3. green start (작은 GPU 비율, 새 포트)
4. 헬스체크 + smoke
5. 사용자 승인 게이트 (`read -p`)
6. blue stop
7. green 풀 비율 재시작 (운영 포트로)
8. 헬스체크 + 부하 테스트
9. 종합 검증 (4 컴포넌트 + Gateway + 외부 도메인)
10. 실패 시 rollback 호출

## 7. 흔한 함정

- flashinfer cache 미정리 → green 빌드 실패 (가장 흔함)
- GPU 메모리 부족 — blue + green 동시에 풀 GPU 차지 시도
- Gateway `upstream_map` 미변경 — 포트가 바뀌었는데 Gateway 가 옛 포트로 라우팅
- DB 마이그레이션 동시 진행 — cutover 와 분리하라 (각각 독립 rollback)
- rollback 시간 부족 — 사용자 승인 후 "아니 이상해" 까지 10초 안에 결정 가능해야 함
- Cloudflare Tunnel 재로딩 시도 — 끊김. 포트만 바꿀 거면 Tunnel 은 손대지 말 것
- pid 파일 분실 — green 의 PID 를 `_logs/vllm-NEW.pid` 에 명시적으로 기록

## 8. 적용 가능 영역

- vLLM 버전 업그레이드 (0.19 → 0.20, 0.20 → 0.21)
- 모델 교체 (Gemma → Qwen, 7B → 70B)
- transformers / torch 메이저 업그레이드
- FastAPI Gateway 의존성 업그레이드 (0 다운 가능 — 포트만 바꾸면 됨)
- PostgreSQL 마이그레이션 cutover (별도 패턴 필요 — `postgres-migration-from-sqlite` 참조)

## 9. 관련 skill

- `vllm-bootstrap` — 격리 venv + 의존성 매트릭스
- `vllm-tool-calling` — parser 호환성 회귀 검증 (cutover 후 tool 호출 깨짐 사례)
- `gem-llm-supervisor` — 서비스 start/stop/status 로 blue/green 모두 관리
- `dependency-vulnerability-fix` — cutover 와 동시에 진행하지 말 것 (별개 작업)
- `bash-cli-best-practices` — cutover/rollback 스크립트 안전 패턴
- `deployment-checklist` — cutover 전 56 항목 점검

## 10. 템플릿

- `scripts/cutover.sh.template` — 10단계 표준 cutover (변수: `<service_name>`, `<old_venv>`, `<new_venv>`, `<port_blue>`, `<port_green>`)
- `scripts/rollback.sh.template` — 즉시 rollback (blue 복귀)

변수만 치환하면 vLLM 외에도 적용 가능.
