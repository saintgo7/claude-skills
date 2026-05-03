# concurrent-load-testing-pattern

API/LLM 동시성 부하 테스트 검증된 패턴 (locust + asyncio.gather 직접). GEM-LLM 50/100/200 동접 시나리오에서 검증 (RPS 41~46, p99 4.4~17s).

## 사용 시점

- "concurrent load test", "asyncio.gather", "locust"
- "p50/p95/p99", "stress test", "RPS 천장"
- "sustainable concurrency", "키 분배"

## 설치

```bash
./install.sh concurrent-load-testing-pattern
```

2 도구 비교, 키 분배 전략, RPS 천장 발견 방법론, p99 SLO 결정, 부하 후 정리 체크리스트는 [SKILL.md](SKILL.md) 참조.
