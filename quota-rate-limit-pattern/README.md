# quota-rate-limit-pattern

API 게이트웨이의 3계층 quota/rate-limit 패턴 (slowapi RPM + asyncio.Semaphore concurrent + DB daily). GEM-LLM Gateway 50/100/200 동접 부하에서 검증.

## 사용 시점

- "rpm 제한", "daily token limit", "concurrent 한도"
- "429 quota exceeded", "rate-limit 설계"
- "slowapi", "asyncio Semaphore"

## 설치

```bash
./install.sh quota-rate-limit-pattern
```

3계층의 시간 단위/상태 저장/적합성 비교, 거부 reason code, Prometheus 통합, 분산 한계는 [SKILL.md](SKILL.md) 참조.
