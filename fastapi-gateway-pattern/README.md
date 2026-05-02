# fastapi-gateway-pattern

FastAPI로 OpenAI 호환 LLM 게이트웨이를 구축하는 검증된 패턴 (vLLM/TGI/llama.cpp/sglang 백엔드).

## 사용 시점

- "openai 호환 게이트웨이", "vllm 앞단"
- "api key 인증", "rate limit fastapi"
- "스트리밍 sse 프록시", "quota 시스템"
- "sqlalchemy pool 설정"

## 설치

```bash
./install.sh fastapi-gateway-pattern
```

인증/라우팅/quota/streaming/usage logging 5계층 구조와 50동접 검증된 SQLAlchemy pool 설정은 [SKILL.md](SKILL.md) 참조.
