# llm-serving-performance-tuning

LLM 서빙 (vLLM + FastAPI Gateway) 성능 튜닝 6단계 워크플로. GEM-LLM 50/100/200 동접 부하 (1282~1440 tok/s, p99 4.2~17.3s) 검증.

## 사용 시점

- "처리량 향상", "p99 latency 개선", "tok/s 측정"
- "동접 100 vs 200", "scaling bottleneck"
- "vLLM 큐 적체", "GPU 활용률", "DB pool"

## 설치

```bash
./install.sh llm-serving-performance-tuning
```

6단계 (측정 → 분류 → vLLM → Gateway → DB → 재측정), 병목 분류표, 흔한 함정은 [SKILL.md](SKILL.md) 참조.
