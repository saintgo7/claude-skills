# fastapi-async-patterns

FastAPI + asyncio + httpx + SQLAlchemy async 의 검증된 6 패턴 모음. GEM-LLM Gateway (50~200 동접) 에서 통과한 조합을 일반화.

## 사용 시점

- "async 패턴", "sse 스트리밍 fastapi", "asyncio Semaphore"
- "fastapi lifespan", "Depends DI", "background task"
- "httpx async stream", "sqlalchemy async session"

## 설치

```bash
./install.sh fastapi-async-patterns
```

6 패턴 (streaming proxy / lifespan / DI / Semaphore / async DB / background task) 의 함정과 시작 체크리스트는 [SKILL.md](SKILL.md). streaming proxy / lifespan 표준 템플릿은 [templates/](templates/).
