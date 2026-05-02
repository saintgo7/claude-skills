# gem-llm-load-test

GEM-LLM 부하 테스트 스킬 (locust + asyncio multi-user-bench).

## 사용 시점

- "부하 테스트 돌려", "50동접 측정"
- "p99 latency 확인", "처리량 측정"
- "스케일링 한계", "throughput"
- "quota/rate-limit 시나리오"

## 설치

```bash
./install.sh gem-llm-load-test
```

locustfile 사용, multi-user-bench.py 사용, quota/rate-limit 시나리오 검증 절차는 [SKILL.md](SKILL.md) 참조.
