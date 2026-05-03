---
name: concurrent-load-testing-pattern
description: 'API/LLM 동시성 부하 테스트 검증된 패턴. 사용 시점 — "concurrent load test", "asyncio.gather", "locust", "p50/p95/p99", "stress test", "sustainable concurrency", "키 분배". 2 도구 (locust + asyncio direct) + p99 측정 + 50/100/200 검증.'
---

# concurrent-load-testing-pattern

API/LLM 서비스 동시성 부하 테스트의 검증된 패턴 모음. 두 가지 도구 (locust, asyncio.gather 직접) 비교, p50/p95/p99 측정, 키 분배 전략, RPS 천장 발견 방법론을 포함합니다. GEM-LLM 게이트웨이 50/100/200 동접 시나리오에서 검증되었습니다 (RPS 41~46, p99 4.4~17s).

## 1. 사용 시점

- 신규 LLM/API 게이트웨이 capacity 평가
- 인프라 변경 (vLLM 버전 업, GPU 추가, 게이트웨이 튜닝) 후 회귀
- SLO 결정 (p99 < 5s 목표 시 sustainable 동접 산정)
- "RPS 천장 어디?" 질문 — 모델/하드웨어 한계 식별
- "200 동접 가능?" 질문 — UX 적합성 (p99 latency) 검증
- CI 통합 stress test (PR 머지 전 회귀 방지)

키워드: "concurrent load test", "asyncio.gather", "locust", "p50/p95/p99", "stress test", "sustainable concurrency", "키 분배", "RPS 천장".

## 2. 두 가지 도구 비교

| 도구 | 언제 쓰나 | 장점 | 단점 |
|---|---|---|---|
| **locust** | UI/대시보드 필요, 분산 부하, RPS 제어 정밀, QA가 같이 본다 | 시각화, master/worker 분산, 가중치 task | 설치/설정 무게, p99 정확도 부족 |
| **asyncio.gather** | 직접 측정, GitHub CI 통합, p99 정확, JSON/Markdown 보고서 | 의존성 적음 (httpx 만), 정확한 latency, 자동화 쉬움 | UI 없음, 분산 어려움 |

권장: **개발/CI = asyncio**, **데모/검증 보고 = locust**. 둘 다 같은 게이트웨이에 동일 조건 돌려 결과 일치 확인하면 신뢰도 상승.

## 3. asyncio 패턴 (scaling-bench)

```python
import asyncio, httpx, time, statistics, math

async def request(client, key, idx):
    t0 = time.monotonic()
    resp = await client.post(URL, headers={"Authorization": f"Bearer {key}"}, json=PAYLOAD)
    return time.monotonic() - t0, resp.status_code

async def worker(client, key, count, results):
    for i in range(count):
        elapsed, status = await request(client, key, i)
        results.append((elapsed, status))

async def main():
    keys = load_keys()
    USERS_PER_KEY = max(1, math.ceil(TARGET_CONC / len(keys)))

    async with httpx.AsyncClient(
        limits=httpx.Limits(max_connections=200, max_keepalive_connections=100),
        timeout=httpx.Timeout(60.0),
    ) as client:
        tasks = []
        results = []
        for key in keys:
            for _ in range(USERS_PER_KEY):
                tasks.append(worker(client, key, REQ_PER_USER, results))
        t_start = time.monotonic()
        await asyncio.gather(*tasks)
        total_time = time.monotonic() - t_start

    successes = [r for r in results if r[1] == 200]
    latencies = sorted([r[0] for r in successes])
    print(f"RPS: {len(successes)/total_time:.2f}")
    print(f"p50: {latencies[len(latencies)//2]*1000:.0f}ms")
    print(f"p95: {latencies[int(len(latencies)*0.95)]*1000:.0f}ms")
    print(f"p99: {latencies[int(len(latencies)*0.99)]*1000:.0f}ms")
```

전체 템플릿: `templates/scaling-bench.py.template` 참조.

## 4. locust 패턴 (locustfile.py)

```python
from locust import HttpUser, task, between
import os, random

class LLMUser(HttpUser):
    wait_time = between(1, 3)

    def on_start(self):
        self.headers = {"Authorization": f"Bearer {os.environ['KEY']}"}

    @task(50)
    def short_chat(self):
        self.client.post("/v1/chat/completions",
                         headers=self.headers,
                         json={"model": "exaone", "messages": [{"role":"user","content":"hi"}]})

    @task(30)
    def coding(self):
        self.client.post("/v1/chat/completions", headers=self.headers, json={...})

    @task(15)
    def long_context(self): ...

    @task(5)
    def streaming(self): ...
```

```bash
locust -f locustfile.py --host http://gw:8080 \
  --headless --users 50 --spawn-rate 5 --run-time 60s \
  --csv=report
```

전체 템플릿: `templates/locustfile.py.template` 참조.

## 5. 핵심 메트릭

- **RPS** (req/sec) — 처리량
- **TPS** (tokens/sec) — LLM 특화, completion_tokens/elapsed
- **p50 / p95 / p99 latency** — 분포 (평균은 무시. p99가 UX 결정)
- **success rate** — 안정성. 99% 미만이면 한계 도달
- **GPU util** — 외부 측정 (`nvidia-smi --query-gpu=utilization.gpu --format=csv -l 1`)
- **메모리 추이** — kv-cache, RAM leak 감지

5가지를 동시에 못 보면 부하 결과를 신뢰하지 말 것.

## 6. 키 분배 전략

| 동접 | keys × users | 권장 |
|---|---|---|
| 50 | 5×10 또는 10×5 | rate limit 회피 |
| 100 | 10×10 또는 16×7 | sustainable 권장 |
| 200 | 10×20 또는 20×10 | UX 부적합 (p99 17s) |

per_key 너무 크면 RPM 60/key 제한에 걸려 진짜 처리량 측정 불가. 가능한 한 분산. 키 N개가 부족하면 임시 admin 키 발급 후 테스트 종료 시 회수.

## 7. RPS 천장 발견 — vLLM 처리량 한계

GEM-LLM 50/100/200 결과:

| 동접 | RPS | p99 | 해석 |
|---|---|---|---|
| 50 | 43.83 | 4.2s | 여유 |
| 100 | 45.41 | 8.1s | 천장 도달 |
| 200 | 41.34 | 17.3s | 큐 적체로 저하 |

해석: vLLM 처리량 ~45 req/s는 **하드웨어 (8 B200) + 모델 크기 (32B + 30B-A3B) 조합의 한계**. 더 높이려면 멀티 노드 또는 더 작은 모델. 동접만 늘리면 큐만 길어지고 RPS는 오히려 감소.

천장 찾는 법: 동접 50 → 100 → 200 → 400 ramp. RPS가 증가 멈추거나 감소하면 직전 step이 천장.

## 8. p99 SLO 결정

- 목표 SLO: p99 < 5초 (일반 챗 UX)
- 50동접: p99 4.2s — 통과
- 100동접: p99 8.1s — 경계
- 200동접: p99 17.3s — 실패

→ **sustainable: 75~100 동접**. burst 허용은 200까지지만 5분 이상 지속 부하는 거부 (큐 적체).

SLO는 시스템 특성. 코딩 보조 (1분 응답 OK) vs 챗봇 (3초 이내) 다르므로 도메인에 맞게 설정.

## 9. 흔한 함정

- **단일 키로 부하** — RPM 60 도달 후 모두 429. 진짜 처리량 측정 불가
- **httpx 기본 connection limit 부족** — `max_connections=200` 명시
- **DB pool 한계** (case 12) — DB 커넥션 부족이 RPS 천장의 진짜 원인이었던 사례
- **p99만 보고 RPS 무시** — p99 좋아도 RPS 낮으면 capacity 부족
- **monitoring 없는 부하** — GPU util / 메모리 누수 / OOM 놓침
- **워밍업 없음** — 첫 5초 latency는 cold start. 결과에서 제외

## 10. 부하 후 정리

- `usage_log` 누적 — daily limit 영향. 테스트용 키는 reset
- DB write-lock (case 14) — `busy_timeout=30s`, WAL 모드
- vLLM KV cache — 자동 회수 (idle 60s 후). 강제 reset 필요 시 `/reset_prefix_cache`
- GPU 메모리 — `nvidia-smi` 확인. 누수 의심 시 vLLM 재시작
- log 폭증 — uvicorn access log 부하 중에는 ERROR 이상만 기록 권장

## 11. 관련 skill

- `prometheus-fastapi-metrics` — 메트릭 수집 (RPS, latency histogram)
- `quota-rate-limit-pattern` — rate limit이 부하 결과에 미치는 영향
- `llm-serving-performance-tuning` — 부하 후 튜닝 워크플로
- `gem-llm-load-test` — GEM-LLM 특화 사례 (이 skill의 출처)
- `observability-bundle` — 부하 중 통합 관측

## 템플릿

- `templates/scaling-bench.py.template` — 일반화된 asyncio 부하 도구 (KEY_LIST + per_key 자동 계산 + markdown 보고서)
- `templates/locustfile.py.template` — 표준 locust LLMUser (4 워크로드 가중치 50/30/15/5)
