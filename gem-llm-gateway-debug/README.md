# gem-llm-gateway-debug

GEM-LLM Gateway (FastAPI port 8080) 디버깅 스킬.

## 사용 시점

- "Gateway 500", "QueuePool"
- "unknown_model", "401 Invalid API key"
- "스트리밍 끊김", "/v1/chat 안됨"
- "/metrics 추가", "rate limit"

## 설치

```bash
./install.sh gem-llm-gateway-debug
```

인증/quota/스트리밍 프록시 구조와 흔한 함정은 [SKILL.md](SKILL.md) 참조.
