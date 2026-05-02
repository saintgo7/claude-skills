# prometheus-fastapi-metrics

FastAPI에 Prometheus 커스텀 메트릭(Counter / Histogram / Gauge)을 추가하는 실전 패턴. GEM-LLM Gateway 6 메트릭 추가 사례에서 일반화.

## 사용 시점

- "prometheus 메트릭", "/metrics endpoint", "fastapi monitoring"
- "request 카운터", "latency histogram", "토큰 사용량 추적"
- "label cardinality 폭발", "Grafana PromQL 시작점"

## 설치

```bash
./install.sh prometheus-fastapi-metrics
```

3-위치 기록 패턴(미들웨어/라우트/서비스), cardinality 제한 룰 5개, Histogram buckets 선택, 자주 쓰는 PromQL 6개, 흔한 함정 7개는 [SKILL.md](SKILL.md). metrics 정의 / 미들웨어 기록 템플릿은 [templates/](templates/).
