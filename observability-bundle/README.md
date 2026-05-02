# observability-bundle

FastAPI 서비스에 관측성 3 pillar (metrics / logs / traces) + 에러 추적을 한 번에 통합하는 가이드. Prometheus + Loki + OpenTelemetry + Sentry 결합, LGTM (Loki + Grafana + Tempo + Mimir) 스택 권장.

## 사용 시점

- "Sentry 추가", "OpenTelemetry 통합", "분산 추적", "에러 추적"
- "로그 집계 Loki", "관측성 시스템", "metrics + traces + logs"
- "trace ID 로 로그-trace 점프"

## 설치

```bash
./install.sh observability-bundle
```

3 pillar 통합 흐름, structlog + trace_id 프로세서, OTel auto-instrument, Sentry 안전 설정, LGTM Docker compose, 비용 비교는 [SKILL.md](SKILL.md). Sentry / OTel / Grafana datasource 템플릿은 [templates/](templates/).
