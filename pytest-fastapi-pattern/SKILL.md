---
name: pytest-fastapi-pattern
description: 'pytest로 FastAPI 통합 테스트 작성 패턴. 사용 시점 — "fastapi pytest", "httpx ASGITransport", "respx mock", "lifespan test", "스트리밍 테스트", "테스트 격리". in-memory SQLite + autouse fixture + lifespan + httpx async client + respx (upstream mock) 패턴 + 219개 검증 테스트 사례.'
---

# pytest-fastapi-pattern

FastAPI 앱에 pytest 통합 테스트를 붙일 때, *공식 문서가 권하는 `TestClient`* 만 따라가면 sync/async 가 섞여 lifespan 이 안 돌고, in-memory SQLite 가 테스트 사이에 새고, upstream HTTP 호출은 mock 이 안 잡힌다. 아래 6 패턴은 GEM-LLM Gateway (FastAPI + SQLAlchemy async + httpx upstream) 의 219 테스트가 220/220 (1 skip = real-vLLM toggle) 으로 통과한 조합이다.

## 사용 시점

- "FastAPI pytest 처음", "테스트 격리 안 됨"
- "httpx ASGITransport", "TestClient async 안 됨"
- "respx", "upstream mock", "vLLM mock", "OpenAI API mock"
- "in-memory SQLite test", "테스트마다 DB 초기화"
- "lifespan test 에서 안 돔", "startup 미실행"
- "SSE 스트리밍 테스트", "async chunk 검증"
- "rate limiter 테스트 누설", "fakeredis"

## 6 패턴 한눈에

| # | 패턴 | 도구 | 해결하는 문제 |
|---|---|---|---|
| 1 | httpx.AsyncClient + ASGITransport | `httpx`, `pytest-asyncio` | TCP 안 띄우고 in-process async 호출 |
| 2 | Lifespan in tests | `asgi-lifespan` 또는 ASGITransport | startup/shutdown 실제 실행 |
| 3 | autouse DB fixture | `pytest_asyncio.fixture` | 테스트마다 깨끗한 테이블 |
| 4 | respx upstream mock | `respx` | vLLM/OpenAI HTTP 가짜 응답 |
| 5 | in-memory SQLite + StaticPool | `sqlite+aiosqlite:///:memory:` | 빠르고, 격리되고, file 안 남김 |
| 6 | SSE chunk assertion | `aiter_bytes()` | 스트리밍 본문 검증 |

## 1. httpx.AsyncClient + ASGITransport

`fastapi.testclient.TestClient` 는 sync wrapper 라 lifespan 이 thread 에서 돌고, `await` 가 진짜 async 가 아니다. async DB / async upstream 을 쓰는 게이트웨이 같은 앱이면 sync TestClient 가 connection leak 을 만든다.

```python
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

@pytest_asyncio.fixture
async def client():
    from gateway.main import create_app
    app = create_app()
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as c:
        yield c

@pytest.mark.asyncio
async def test_health(client):
    r = await client.get("/health")
    assert r.status_code == 200
```

`ASGITransport` 는 TCP 를 안 거치므로 빠르고, `respx` 와 같은 트랜스포트 레이어에서 upstream HTTP 만 골라 mock 할 수 있다.

## 2. Lifespan in tests

`ASGITransport(app, ...)` 는 *기본적으로* lifespan 을 안 실행한다. FastAPI 의 startup 에서 `engine = create_async_engine(...)` 같은 걸 만들면 테스트는 engine 이 None 이라 깨진다. 두 방법:

**A) httpx ≥ 0.27 — `lifespan="on"`**

```python
transport = ASGITransport(app=app, lifespan="on")  # httpx 0.27+
```

**B) `asgi-lifespan` (확실)**

```python
from asgi_lifespan import LifespanManager

async with LifespanManager(app):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        ...
```

GEM-LLM 에선 `create_app()` 안에서 lifespan 이 DB 엔진 + httpx pool 을 만든다. lifespan 미실행 → `engine is None` 으로 모든 endpoint 가 500.

## 3. Autouse DB fixture

테스트 사이에 `usage_log` row 가 남아 다음 테스트 검증을 깬다. 매 테스트 진입 시 `create_all` + 종료 시 `drop_all`.

```python
@pytest_asyncio.fixture
async def app_db():
    from gateway.db import get_engine, reset_engine
    from gateway.models import Base

    await reset_engine()  # 이전 테스트 engine 폐기
    engine = get_engine()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await reset_engine()
```

`client` fixture 가 `app_db` 를 의존하면 사실상 autouse 처럼 동작한다 (`@pytest_asyncio.fixture(autouse=True)` 도 가능하나, async client 가 함께 묶일 때는 명시 의존이 더 읽기 좋다).

## 4. respx upstream mock

게이트웨이는 vLLM / OpenAI 로 HTTP forward 한다. 테스트에선 그 upstream 만 가로채야지, app 자체는 진짜로 돌아야 한다. `respx` 는 httpx transport 레벨에서 잡으므로 `httpx.AsyncClient(...).post(upstream)` 만 mock 된다.

```python
import respx
from httpx import Response

async with respx.mock(assert_all_called=True) as mock:
    mock.post("http://vllm-31b.test/v1/chat/completions").mock(
        return_value=Response(200, json={"choices": [...], "usage": {...}})
    )
    r = await client.post("/v1/chat/completions", headers=auth, json={...})
assert r.status_code == 200
```

`assert_all_called=True` 가 *덕분에* "라우팅 잘못 돼서 mock 이 한 번도 안 호출된" 버그가 잡힌다.

## 5. in-memory SQLite + StaticPool

```python
os.environ["GATEWAY_DB_URL"] = "sqlite+aiosqlite:///:memory:"
```

함정: SQLAlchemy `:memory:` 는 *connection 마다* 다른 DB. 한 fixture 에서 `create_all` 한 다음, request handler 가 새 connection 을 잡으면 빈 DB 다. 해법은 **engine singleton + StaticPool**:

```python
from sqlalchemy.pool import StaticPool

engine = create_async_engine(
    "sqlite+aiosqlite:///:memory:",
    poolclass=StaticPool,
    connect_args={"check_same_thread": False},
)
```

GEM-LLM 은 `gateway.db.get_engine()` 이 lru_cache 로 single engine 을 반환하고, `reset_engine()` 으로만 폐기한다. 테스트는 이 두 함수만 호출.

## 6. SSE chunk assertion

스트리밍 응답의 텍스트 검증. `client.post(..., json={"stream": True})` 로 받으면 `r.text` 에 전체 SSE 본문이 들어 있다 — 짧은 응답이면 그대로 검증, 큰 응답이면 chunk 단위로 봐야 한다.

```python
async with client.stream("POST", "/v1/chat/completions", json={...}) as r:
    chunks: list[bytes] = []
    async for chunk in r.aiter_bytes():
        chunks.append(chunk)
body = b"".join(chunks)
assert b"data: " in body
assert b"[DONE]" in body
```

upstream 도 SSE 면 `respx` 로 raw bytes 를 돌려준다:

```python
sse = b'data: {"choices":[{"delta":{"content":"Hi"}}]}\n\n' b"data: [DONE]\n\n"
mock.post(URL).mock(return_value=Response(
    200, content=sse, headers={"content-type": "text/event-stream"}
))
```

## conftest.py 표준 구조

[templates/conftest.py.template](templates/conftest.py.template) 에 풀 버전. 핵심 순서:

1. **import 전에** `os.environ.setdefault(...)` — settings 캐시 피하기
2. `pytest_asyncio.fixture` 로 `app_db` (DB create/drop)
3. `pytest_asyncio.fixture` 로 `client` (ASGITransport + lifespan)
4. 동기 `admin_headers` / `auth_headers` 헬퍼
5. upstream 응답 빌더 (`make_chat_response`, `make_sse_chunks`)

`pytest.ini` / `pyproject.toml` 에:

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"      # @pytest.mark.asyncio 생략 가능
asyncio_default_fixture_loop_scope = "function"
```

## 흔한 함정

**1) `TestClient` 로 async lifespan 안 돔**
sync TestClient → thread 에서 lifespan → async engine startup 이 다른 loop 에 잡힘 → "Future attached to a different loop". → `httpx.AsyncClient + ASGITransport` 로 갈아타라.

**2) DB state 누설**
fixture scope 가 `module`/`session` 이면 row 가 다음 테스트에 남는다. **scope 미지정 = function** 이 기본이고 옳다. autouse 로 두거나 매 client 가 의존.

**3) rate limiter in-memory state 누설**
`slowapi` / `asyncio.Semaphore` 가 모듈 전역에 카운터를 들면 테스트 간에 안 리셋. 해결: lifespan 에서 만들고, app 을 매 테스트 새로 `create_app()`. 또는 `fakeredis` 로 backend 을 갈아끼우고 fixture 에서 `flushall()`.

**4) lifespan 미실행 → engine None**
ASGITransport 기본은 lifespan off. `lifespan="on"` (httpx 0.27+) 또는 `LifespanManager` 로 강제. 증상 — 모든 endpoint 가 500, 로그에 `'NoneType' has no attribute 'begin'`.

**5) respx 가 안 잡힘**
`respx.mock` 컨텍스트 *밖* 에서 upstream 호출이 일어나면 진짜 네트워크로 나간다 (또는 ConnectError). request 가 `await` 해제되기 전에 컨텍스트가 끝나지 않게 — `await client.post(...)` 까지 모두 `async with respx.mock()` 안에서.

**6) `:memory:` 가 빈 DB 로 보임**
StaticPool 안 쓰면 connection-per-call 마다 DB 가 새로 만들어진다. `poolclass=StaticPool` + `check_same_thread=False` 필수.

**7) 환경변수가 import 후 적용**
`from gateway import config` 가 먼저 실행되면 `Settings()` 가 캐시돼서 `os.environ.setdefault` 가 늦는다. **conftest.py 최상단** 에서 환경변수 → `import gateway`.

## GEM-LLM 사례 (220/220, 1 skip)

- `tests/conftest.py` (309 줄) — gateway + admin 공유 fixture, fixture 헬퍼 (`make_chat_response`, `make_sse_chunks`, `make_tool_call_response`)
- `tests/integration/` 7 파일 — auth flow, streaming, e2e CLI↔gateway, e2e gateway↔vllm
- `src/gateway/tests/` 5 파일 — admin, auth, chat streaming, metrics, quota
- `src/admin-ui/tests/` — admin UI session, CRUD
- skip 1건은 `GEM_LLM_REAL_VLLM=1` 토글 (실제 GPU 시 ON)

`make test` 1회 = ~12s. 단일 fixture 패턴 덕분에 219 테스트가 동일한 in-memory engine 라이프사이클을 따른다.

## 시작 체크리스트

- [ ] `pytest-asyncio` + `httpx` + `respx` (+ `aiosqlite` if SQLAlchemy async) 설치
- [ ] `pyproject.toml` 에 `asyncio_mode = "auto"`
- [ ] `conftest.py` 최상단에서 환경변수 `os.environ.setdefault`
- [ ] `app_db` fixture — `Base.metadata.create_all/drop_all`
- [ ] `client` fixture — `ASGITransport` + lifespan
- [ ] StaticPool 로 `:memory:` SQLite engine singleton
- [ ] upstream 호출은 모두 `respx.mock(assert_all_called=True)` 안에서
- [ ] streaming endpoint 는 `client.stream()` + `aiter_bytes()` 로 검증
