---
name: prometheus-fastapi-metrics
description: 'FastAPI에 Prometheus 커스텀 메트릭(Counter/Histogram/Gauge) 추가 패턴. 사용 시점 — "prometheus 메트릭", "/metrics endpoint", "request 카운터", "latency histogram", "토큰 사용량 추적", "fastapi monitoring", "label cardinality". 미들웨어/라우트/서비스 3 위치에서 기록 + cardinality 제한 + Grafana dashboard 시작점.'
---

# prometheus-fastapi-metrics

FastAPI 앱에 Prometheus 커스텀 메트릭을 추가하는 실전 패턴.
GEM-LLM Gateway에 6 메트릭을 추가하면서 검증된 3-위치 기록 + cardinality 제한 가이드를 일반화.

## 사용 시점 (트리거)

- "prometheus 메트릭 추가", "/metrics endpoint"
- "request counter", "latency histogram", "active connection gauge"
- "토큰 사용량 추적", "도메인별 카운터"
- "fastapi monitoring", "fastapi observability"
- "label cardinality 폭발", "Prometheus 라벨 설계"
- "Grafana dashboard PromQL"

## prometheus_client 4 종 차이

| 종류 | 용도 | 예시 |
|------|------|------|
| Counter | 단조 증가 (재시작 외 감소 없음) | 요청 수, 에러 수, 처리 토큰 누계 |
| Gauge | 임의 증감 | 동시 요청 수, 큐 깊이, 메모리 사용량 |
| Histogram | 분포(buckets + sum + count) | latency, payload size |
| Summary | 분포 + quantile (서버측 계산, 비쌈) | 거의 안 씀 — Histogram + `histogram_quantile()` 권장 |

기본 4개로 충분. Summary는 라벨이 많거나 다중 인스턴스에서 quantile 합산이 필요한 경우 부정확하므로 피한다.

## /metrics endpoint (한 줄 추가)

```python
from fastapi import APIRouter, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest

router = APIRouter()

@router.get("/metrics")
async def metrics() -> Response:
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
```

`generate_latest()` 는 default REGISTRY를 직렬화. 여러 워커(gunicorn workers, uvicorn `--workers N`)면 `prometheus_client.multiprocess` 셋업 필요 (별도 dir + `PROMETHEUS_MULTIPROC_DIR` 환경변수). 단일 워커면 추가 작업 없음.

## 3-위치 기록 패턴 (핵심)

메트릭은 **요청 lifecycle에서 적절한 위치**에 두어야 한다. 한 곳에 다 몰면 (a) 라벨이 비어 있거나 (b) 책임이 흐려진다.

### 위치 1: 미들웨어 — 모든 요청 공통

```python
# gateway/middleware/logging.py
from gateway.metrics import requests_total, active_requests

class RequestLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        path_label = _label_path(request.url.path)  # 화이트리스트
        active_requests.inc()
        try:
            response = await call_next(request)
            requests_total.labels(
                method=request.method, path=path_label,
                status=str(response.status_code),
            ).inc()
            return response
        finally:
            active_requests.dec()
```

요청 단위 메트릭(요청 수, 활성 요청, total latency)은 미들웨어 한 곳에서.

### 위치 2: 라우트 — 도메인별 메트릭

```python
# gateway/routes/chat.py
from gateway.metrics import chat_completions_total, tokens_total, chat_latency_ms

def _record_chat_metrics(model, stream, status, p_tokens, c_tokens, latency_ms):
    chat_completions_total.labels(
        model=model, stream=str(stream).lower(), status=str(status),
    ).inc()
    if p_tokens:
        tokens_total.labels(model=model, kind="prompt").inc(p_tokens)
    if c_tokens:
        tokens_total.labels(model=model, kind="completion").inc(c_tokens)
    chat_latency_ms.labels(model=model).observe(float(latency_ms))
```

도메인 의미가 있는 메트릭(model, kind=prompt/completion 등 비즈니스 라벨)은 라우트에서. 미들웨어는 `model` 같은 body 필드를 모른다.

### 위치 3: 서비스 — 거부/실패 메트릭

```python
# gateway/services/quota.py
from gateway.metrics import quota_rejections_total

def _record_rejection(reason: str) -> None:
    if reason in {"daily_token_limit", "rpm_limit", "concurrent"}:  # 화이트리스트
        quota_rejections_total.labels(reason=reason).inc()
```

비즈니스 로직 분기(쿼터 거부, 검증 실패, retry 등)는 서비스 레이어에서.

## Label cardinality 제한 (가장 중요)

각 라벨 조합마다 별도 시계열이 생긴다. **시계열 폭발 = Prometheus OOM, 쿼리 슬로우, 카드 청구서 폭증**.

### 룰

1. **Path는 화이트리스트** — `/v1/chat/completions/abc123` 같은 동적 path를 그대로 라벨로 쓰면 무한히 늘어남.
   ```python
   _KNOWN_PATHS = {"/healthz", "/readyz", "/metrics", "/v1/models", "/v1/chat/completions"}

   def _label_path(path: str) -> str:
       if path in _KNOWN_PATHS:
           return path
       if path.startswith("/admin"):
           return "/admin/*"
       return "other"
   ```

2. **Model은 known set만** — `upstream_map.keys()` 같은 고정 집합. 사용자 입력 그대로 라벨 X.

3. **Status code는 그룹화** — 200, 400, 429, 500 정도. `4xx`/`5xx`로 더 줄여도 됨. 단, **status text(`Bad Request` 등) 는 절대 라벨 X**.

4. **User ID, IP, Request ID는 라벨 X** — 카운터/히스토그램 라벨이면 시계열 폭발. 로그 / trace에 남기고, 메트릭은 집계 단위만.

5. **Reason은 enum** — quota rejection reason처럼 알려진 문자열만 통과. 자유 문자열이면 화이트리스트로 거른다.

### 카운트 추정

라벨 종류 곱이 시계열 수.
- `requests_total{method,path,status}`: 5 method × 8 path × 5 status = **200 series**. 안전.
- `chat_completions_total{model,stream,status}`: 2 model × 2 stream × 5 status = **20 series**. 매우 안전.
- 잘못된 예: `requests_total{path=<full URL>}` — endpoint 100k = **100k series**. 사망.

대략 **인스턴스당 10k series 이하** 권장 (Prometheus 운영 가이드 일반치).

## Histogram buckets 선택

기본 buckets(`.005, .01, .025, …, 10`)는 ms 단위 latency에 맞지 않음. 서비스 SLO 기준으로 직접 정의.

```python
# 50ms ~ 30s — LLM/외부 API gateway
chat_latency_ms = Histogram(
    "chat_latency_ms",
    "Chat completion latency (ms)",
    ["model"],
    buckets=(50, 100, 200, 500, 1000, 2000, 5000, 10000, 30000),
)

# 1ms ~ 1s — 일반 REST API
api_latency_ms = Histogram(
    "api_latency_ms",
    "API latency (ms)",
    ["route"],
    buckets=(1, 5, 10, 25, 50, 100, 250, 500, 1000),
)
```

원칙:
- bucket 수 8~12 (너무 많으면 cardinality, 너무 적으면 quantile 부정확).
- SLO 경계(예: P99 < 2000ms)가 bucket 경계에 있으면 정확도 ↑.
- 단위는 메트릭 이름에 포함 (`_ms`, `_seconds`).

## Gauge 활용 패턴

```python
active_requests = Gauge("active_requests", "Currently active requests")

# 미들웨어 / try-finally 로 안전하게
active_requests.inc()
try:
    ...
finally:
    active_requests.dec()  # 예외에도 반드시 dec
```

활용 예: 동시 요청, 큐 깊이, 워커 풀 사이즈, 마지막 cron 실행 timestamp(`Gauge.set_to_current_time()`).

## 자주 쓰는 PromQL (Grafana 시작점)

```promql
# 초당 요청 수 (RPS)
rate(requests_total[5m])

# 5xx 비율
sum(rate(requests_total{status=~"5.."}[5m]))
  / sum(rate(requests_total[5m]))

# P50/P95/P99 latency
histogram_quantile(0.50, sum(rate(chat_latency_ms_bucket[5m])) by (le, model))
histogram_quantile(0.95, sum(rate(chat_latency_ms_bucket[5m])) by (le, model))
histogram_quantile(0.99, sum(rate(chat_latency_ms_bucket[5m])) by (le, model))

# 분당 토큰 throughput (model 별)
sum by (model) (rate(tokens_total{kind="completion"}[1m])) * 60

# 동시 활성 요청 (현재값)
active_requests

# 거부율 (reason 별)
sum by (reason) (rate(quota_rejections_total[5m]))
```

Grafana dashboard 시작은 위 6개 query를 패널로 만들면 충분. SLO/alert는 5xx 비율 + P99 latency 두 개부터.

## Grafana 대시보드 시작점

[templates/grafana-dashboard.json.template](templates/grafana-dashboard.json.template) 가 8 패널 starter dashboard. `<service>` placeholder를 자기 메트릭 prefix로 sed 치환 후 Grafana에 import.

```bash
# 예: gateway_* 메트릭이라면
sed 's/<service>/gateway/g' \
  prometheus-fastapi-metrics/templates/grafana-dashboard.json.template \
  > grafana-dashboard.json
# Grafana → Dashboards → Import → Upload JSON file
```

8 패널 PromQL 한 줄 요약 (schemaVersion 38, datasource 변수 `${DS_PROMETHEUS}`):

| # | 패널 | PromQL |
|---|------|--------|
| 1 | Request rate | `sum by (status) (rate(<service>_requests_total[5m]))` |
| 2 | Chat completions rate | `sum by (model) (rate(<service>_chat_completions_total[5m]))` |
| 3 | Latency p50/p95/p99 | `histogram_quantile(0.50\|0.95\|0.99, sum by (le, model) (rate(<service>_chat_latency_ms_bucket[5m])))` |
| 4 | Token throughput | `sum by (kind) (rate(<service>_tokens_total[5m]))` |
| 5 | Active requests (gauge) | `<service>_active_requests` |
| 6 | Quota rejections | `sum by (reason) (rate(<service>_quota_rejections_total[5m]))` |
| 7 | 5xx error rate | `sum(rate(<service>_requests_total{status=~"5.."}[5m])) / clamp_min(sum(rate(<service>_requests_total[5m])), 1e-9)` |
| 8 | GPU util (외부 exporter) | `nvidia_smi_utilization_gpu_ratio * 100` 또는 `DCGM_FI_DEV_GPU_UTIL` |

8번 패널은 nvidia_gpu_exporter 또는 DCGM 같은 외부 의존이 있어야 채워진다 (없으면 빈 패널).

## 흔한 함정

1. **Cardinality 폭발** — 라벨에 user_id, request_id, full URL 넣음. → `/metrics` 응답이 MB 단위로 부풀고 Prometheus가 죽는다. 화이트리스트 필수.

2. **누락된 label 디폴트** — `Counter.labels()` 호출 없이 `.inc()` 하면 에러. 또는 일부 라벨만 채우면 빈 문자열 series가 생긴다. **모든 라벨을 명시**하거나 `Counter` 정의 시 라벨을 안 두거나, 둘 중 하나.

3. **try-finally 누락 (Gauge)** — `inc()` 후 예외 시 `dec()` 안 하면 active_requests가 양수로 누적. 미들웨어에서 반드시 `try: ... finally: dec()`.

4. **Multi-worker 누락** — `uvicorn --workers 4`에서 각 프로세스가 자기 메모리에 카운트. `/metrics` scrape마다 다른 값. **단일 워커**로 운영하거나 `prometheus_client.multiprocess` 모드 셋업.

5. **Race condition은 거의 없음** — `Counter`/`Gauge`/`Histogram`은 thread-safe. 단, 카운터 값을 읽어 분기 판단(예: rate limit)하면 **데이터 레이스**. 메트릭은 관측용이지 제어용이 아님.

6. **Label 이름 변경** — Prometheus 시계열 ID = (이름 + 라벨 set). 라벨 추가/삭제는 새 시계열을 만든다. 기존 알림/대시보드가 깨질 수 있어 변경은 신중하게.

7. **Histogram buckets 변경** — bucket을 바꾸면 과거 데이터와 percentile 계산이 어긋남. 처음에 SLO 기준으로 잘 정하고 가급적 유지.

## GEM-LLM 사례 (참조)

GEM-LLM Gateway에 추가한 6개 메트릭:

```python
gateway_requests_total            # Counter [method, path, status]      — 미들웨어
gateway_chat_completions_total    # Counter [model, stream, status]     — 라우트
gateway_tokens_total              # Counter [model, kind=prompt/completion] — 라우트
gateway_chat_latency_ms           # Histogram [model], 9 buckets        — 라우트
gateway_active_requests           # Gauge (no labels)                   — 미들웨어
gateway_quota_rejections_total    # Counter [reason]                    — 서비스
```

5회 chat 호출 후 `/metrics` 측정 (qwen2.5-coder-32b):
- `gateway_chat_completions_total{model="qwen2.5-coder-32b",stream="false",status="200"} 5`
- `gateway_tokens_total{kind="prompt",model="qwen2.5-coder-32b"} 적산값`
- `gateway_chat_latency_ms_count{model="qwen2.5-coder-32b"} 5`
- `gateway_chat_latency_ms_sum` / count = 평균 latency

라벨 조합 총 시계열 수: ~50 (cardinality 안전).

전체 정의는 [templates/metrics.py.template](templates/metrics.py.template), 미들웨어 기록은 [templates/middleware-record.py.template](templates/middleware-record.py.template) 참고.

## 확장 포인트

- **다중 워커** — `prometheus_client.multiprocess` + shared dir.
- **Push gateway** — short-lived job (cron, batch). 일반 서버는 pull(scrape)이 정석.
- **OpenTelemetry 메트릭** — Prometheus exporter로 동일하게 노출되지만, 분산 trace 통합이 필요할 때.
- **Alertmanager** — Prometheus rule로 5xx 비율, P99 latency, scrape 실패 알림.
