---
name: observability-bundle
description: '통합 관측성 (3 pillar — logs/metrics/traces) FastAPI 셋업. 사용 시점 — "Sentry 추가", "OpenTelemetry 통합", "분산 추적", "에러 추적", "로그 집계 Loki", "관측성 시스템", "metrics + traces + logs". prometheus-fastapi-metrics + Sentry + OTel 결합 + Loki/Grafana stack.'
---

# observability-bundle

FastAPI 서비스에 관측성 3 pillar (metrics / logs / traces) + 에러 추적을 통합하는 실전 가이드.
`prometheus-fastapi-metrics` 가 metrics 1 pillar 만 다룬다면, 이 skill 은 logs/traces 까지 확장하고 4 도구를 한 스택으로 묶는다.

## 1. 사용 시점 + 3 pillar 개요

트리거 — "Sentry 추가", "OpenTelemetry 통합", "분산 추적 (distributed tracing)", "에러 추적", "로그 집계 (Loki/ELK)", "관측성 시스템", "metrics + traces + logs", "trace ID 로그 연결".

| Pillar  | 도구                          | 역할                                       | 데이터 모양       |
|---------|-------------------------------|--------------------------------------------|-------------------|
| Metrics | Prometheus + Grafana          | 정량 지표 (RPS, latency, errors, saturation) | 시계열 숫자        |
| Logs    | Loki + Promtail (or ELK)      | 텍스트 로그 검색 / aggregation              | 타임스탬프 + 문자열 |
| Traces  | OpenTelemetry + Tempo / Jaeger | 분산 호출 체인 (요청 → 게이트웨이 → 백엔드 → DB) | span tree         |

추가 — Sentry 는 "에러 추적 + 일부 trace" 특화. 위 3 pillar 와 보완 관계.

## 2. Metrics (Prometheus) — `prometheus-fastapi-metrics` skill 참조

기존 6 메트릭 + 추가 권장 (4 Golden Signals 커버):

- HTTP request rate (requests_total Counter)
- Latency histogram (request_duration_seconds Histogram)
- Token throughput (tokens_total Counter, LLM 게이트웨이 한정)
- Error rate (errors_total Counter, status >= 500 또는 exception)
- Saturation — CPU / memory / GPU (node_exporter, dcgm-exporter)
- Active connections (active_requests Gauge)

→ 자세한 라벨 설계 / cardinality 제한은 `prometheus-fastapi-metrics` skill 참조.

## 3. Logs (Loki) — JSON 구조화 로그

### 3.1. 통합 방법: structlog + JSON 렌더러

```python
import structlog
import logging

logging.basicConfig(format="%(message)s", level=logging.INFO)

structlog.configure(
    processors=[
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ],
    wrapper_class=structlog.stdlib.BoundLogger,
    logger_factory=structlog.stdlib.LoggerFactory(),
)

logger = structlog.get_logger()
logger.info("request_received", path=request.url.path, user_id=user.id)
```

→ 출력: `{"event": "request_received", "path": "/v1/chat", "user_id": 42, "timestamp": "...", "level": "info"}`

### 3.2. Loki + Promtail 셋업 (Docker compose)

- Promtail → 컨테이너 stdout 또는 파일 tail → Loki HTTP push
- Grafana 에서 Loki datasource 추가 → LogQL 로 검색 (`{container="gateway"} |= "error"`)

권고 — JSON 로그를 Promtail `pipeline_stages.json` 으로 파싱하면 모든 키가 Loki label/structured 필드로 활용 가능.

## 4. Traces (OpenTelemetry)

### 4.1. FastAPI 자동 instrument

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor

trace.set_tracer_provider(TracerProvider())
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(endpoint="http://tempo:4318/v1/traces"))
)

FastAPIInstrumentor.instrument_app(app)
HTTPXClientInstrumentor().instrument()
SQLAlchemyInstrumentor().instrument(engine=engine)
```

### 4.2. 결과

- 요청별 trace ID 자동 부여 (W3C Trace Context 헤더 `traceparent` 전파)
- 백엔드 호출 (vLLM, 다른 서비스) 도 자동 trace
- DB 쿼리 자동 trace (SQL 텍스트, duration 캡처)
- Grafana Tempo 에서 호출 체인 시각화 (Service Graph, Flame Graph)

### 4.3. 주의

- BatchSpanProcessor 는 워커 종료 시 flush 필요 → FastAPI lifespan 에서 `provider.shutdown()`
- 라이브러리별 instrument 패키지 따로 설치 (`opentelemetry-instrumentation-fastapi`, `-httpx`, `-sqlalchemy`)
- Sampling 0.1 (10%) 권장 — 100% sampling 은 백엔드 부담

## 5. Sentry (에러 추적)

```python
import os
import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.sqlalchemy import SqlalchemyIntegration

sentry_sdk.init(
    dsn=os.environ["SENTRY_DSN"],
    integrations=[FastApiIntegration(), SqlalchemyIntegration()],
    traces_sample_rate=0.1,           # 10% 만 trace
    send_default_pii=False,           # 개인정보 X (이메일, IP 자동 수집 차단)
    environment=os.environ.get("ENV", "production"),
    release=os.environ.get("APP_VERSION", "unknown"),
)
```

특징:
- unhandled exception 자동 캡처 (stack trace + local 변수)
- breadcrumbs (직전 N 개 로그/HTTP/DB 자동 첨부)
- alert / 그룹화 / 이슈 추적 UI 내장
- OTel 과 trace ID 공유 가능 (`sentry-trace` 헤더)

## 6. 통합 스택: LGTM (Loki + Grafana + Tempo + Mimir/Prometheus)

Docker compose 예시 (요약):

```yaml
services:
  prometheus:
    image: prom/prometheus
    volumes: [./prometheus.yml:/etc/prometheus/prometheus.yml]
  loki:
    image: grafana/loki:latest
    ports: ["3100:3100"]
  tempo:
    image: grafana/tempo:latest
    command: ["-config.file=/etc/tempo.yaml"]
    ports: ["3200:3200", "4318:4318"]   # OTLP HTTP
  promtail:
    image: grafana/promtail:latest
    volumes: [/var/log:/var/log, ./promtail.yml:/etc/promtail/config.yml]
  grafana:
    image: grafana/grafana
    ports: ["3000:3000"]
    environment:
      GF_AUTH_ANONYMOUS_ENABLED: "true"
    volumes: [./grafana-datasources.yml:/etc/grafana/provisioning/datasources/ds.yml]
```

→ Grafana datasource 자동 provisioning 은 `templates/grafana-loki-config.yml.template` 참조.

## 7. trace ID 연결 (logs ↔ traces)

3 pillar 통합의 핵심 — 로그에서 trace 점프, trace 에서 로그 점프.

```python
import structlog
from opentelemetry import trace as otel_trace

def add_trace_id(_, __, event_dict):
    span = otel_trace.get_current_span()
    ctx = span.get_span_context() if span else None
    if ctx and ctx.trace_id:
        event_dict["trace_id"] = format(ctx.trace_id, "032x")
        event_dict["span_id"] = format(ctx.span_id, "016x")
    return event_dict

structlog.configure(processors=[
    add_trace_id,
    structlog.processors.TimeStamper(fmt="iso"),
    structlog.processors.JSONRenderer(),
])
```

Grafana 워크플로:
1. Loki 검색 → 에러 로그 발견
2. JSON 의 `trace_id` 클릭 → Tempo 자동 점프 (datasource derived field 설정)
3. Tempo span 에서 "View Logs" → Loki 자동 검색 (`{trace_id="..."}`)

## 8. 비용 / 부하 영향

| 항목       | 상대 부하                                       | 비고                                          |
|------------|------------------------------------------------|-----------------------------------------------|
| Prometheus | 1 MB/s 스크레이프 (label cardinality 제한 시)   | 카디널리티 1 만 이상 → 메모리 폭발            |
| Loki       | 로그 양 비례 (1 GB/day 흔함, JSON 은 더 큼)     | label 적게 (`container`, `level` 정도)         |
| OTel       | 0.1 sampling 으로 요청당 +1% latency, +0.5% CPU | 100% sampling 은 Tempo 디스크 폭발            |
| Sentry     | 에러 시에만 전송 → 거의 무시할 수준              | 무료 5 K events/month, 그 이상 유료 ($26+/mo) |

권고 — 셀프 호스트 LGTM 은 단일 노드 4 vCPU / 8 GB / 100 GB SSD 로 1 K RPS 까지 OK.

## 9. Sampling 전략 — 100 % 는 함정

| 데이터    | 권장 sample          | 이유                                              |
|-----------|----------------------|---------------------------------------------------|
| Metrics   | 100 % (집계 자체가 sampling) | Prometheus 는 모든 요청을 카운트하지 시계열을 보존 X |
| Logs      | 100 % (구조화 후 ERROR/WARN 만 영구 보관) | grep 가능성 유지, INFO 는 N 일 후 삭제              |
| Traces    | 1 ~ 10 % (head-based) 또는 tail-based   | 100 % 는 Tempo 디스크 폭발                          |
| Sentry    | 모든 exception + 0.1 performance trace | 에러는 빠짐없이, perf 는 일부만                     |

tail-based sampling — OTel collector 에서 "에러 발생 trace 만 100 % 보관 + 정상 trace 1 %" 정책이 가능. 운영 안정화 후 도입 권장.

## 10. 흔한 함정

1. **structlog 와 stdlib logging 동시 사용** — 둘 중 하나로 통일. 혼용하면 JSON / 평문 로그가 섞여 Loki 파싱 실패.
2. **OTel 미들웨어 순서** — `FastAPIInstrumentor.instrument_app(app)` 은 라우터 추가 *전* 호출. 후에 추가하면 일부 라우트가 trace 안 됨.
3. **Sentry traces_sample_rate 1.0** — 트래픽 많은 서비스는 Sentry quota 즉시 소진. 0.05 ~ 0.1 권장.
4. **trace_id 누락 로그** — `add_trace_id` 프로세서가 structlog 체인 *맨 앞* 에 와야 다른 프로세서에서도 접근 가능.
5. **Loki label cardinality 폭발** — `user_id`, `request_id` 를 label 로 쓰면 안 됨 (structured field 로). label 은 5 ~ 10 개 이하.
6. **OTel + uvicorn workers > 1** — provider 가 워커별로 따로 생성 → 메모리 N 배. gunicorn `--preload` 로 마스터에서 init 하면 fork 후 공유.
7. **Sentry send_default_pii=True 기본값 X** — 현행 SDK 기본은 False 지만, 명시적으로 끄는 것이 감사/법무에 유리.

## 11. 알림 규칙 (Alertmanager / Grafana Alerting)

```yaml
groups:
  - name: api-slo
    rules:
      - alert: HighErrorRate
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[5m]))
            / sum(rate(http_requests_total[5m])) > 0.01
        for: 5m
        labels: {severity: page}
        annotations: {summary: "5xx error rate > 1 % for 5 m"}

      - alert: HighLatencyP99
        expr: |
          histogram_quantile(0.99,
            sum(rate(http_request_duration_seconds_bucket[5m])) by (le)) > 1.0
        for: 10m
        labels: {severity: warn}

      - alert: SaturationGPU
        expr: avg(DCGM_FI_DEV_GPU_UTIL) > 90
        for: 15m
        labels: {severity: warn}
```

Sentry 는 자체 alert rule (새 이슈 / 회귀 / 빈도 임계) → Slack webhook 별도 설정.

## 12. 통합 체크리스트

- [ ] `/metrics` endpoint 노출 (Prometheus scrape)
- [ ] structlog + JSON 렌더러 + trace_id 프로세서 추가
- [ ] OTel TracerProvider + FastAPI/httpx/SQLAlchemy instrument
- [ ] Sentry init (DSN 환경변수, sample rate 0.1)
- [ ] LGTM Docker compose 기동 + Grafana datasource provisioning
- [ ] 알림 규칙 — error rate > 1%, p99 latency > 1 s, Sentry 새 이슈 → Slack
- [ ] 대시보드 — RED (Rate / Error / Duration) + USE (Util / Sat / Errors) + 요청-trace 점프

## 13. 관련 skill

- `prometheus-fastapi-metrics` — metrics pillar 상세
- `fastapi-async-patterns` — lifespan / async context 에서 OTel/Sentry shutdown
- `gem-llm-overview` — LGTM 운영 사례 (참조)
- `deployment-checklist` — 배포 전 모니터링 영역 항목
