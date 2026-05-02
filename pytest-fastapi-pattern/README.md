# pytest-fastapi-pattern

pytest 로 FastAPI 통합 테스트를 작성하는 검증된 6 패턴. GEM-LLM Gateway 의 219 테스트 (220/220, 1 skip = real-vLLM toggle) 가 통과한 조합.

## 사용 시점

- "fastapi pytest", "httpx ASGITransport", "TestClient async 안 됨"
- "respx mock", "vLLM/OpenAI upstream mock"
- "lifespan test", "in-memory SQLite", "테스트 격리"
- "스트리밍 SSE 테스트"

## 설치

```bash
./install.sh pytest-fastapi-pattern
```

6 패턴 (ASGITransport / lifespan / autouse DB / respx / StaticPool / SSE chunk) + 7 함정은 [SKILL.md](SKILL.md). 표준 conftest + 스트리밍 테스트 템플릿은 [templates/](templates/).
