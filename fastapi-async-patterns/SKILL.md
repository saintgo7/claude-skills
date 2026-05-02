---
name: fastapi-async-patterns
description: 'FastAPI + asyncio + httpx + SQLAlchemy async 검증된 패턴 모음. 사용 시점 — "async 패턴", "sse 스트리밍 fastapi", "asyncio Semaphore", "fastapi lifespan", "Depends DI", "background task", "httpx async stream", "sqlalchemy async session". 6 패턴 — streaming proxy, lifespan, DI, semaphore, async DB, background task.'
---

# fastapi-async-patterns

FastAPI 가 비동기라는 사실은 알려져 있지만, 실제로 *blocking 없이* 끝까지 async 로 흐르게 만드는 건 별개다. sync httpx 한 줄, `time.sleep`, sync SQLAlchemy session 하나만 섞여도 이벤트 루프가 멈추고 동접이 1로 떨어진다. 아래 6 패턴은 GEM-LLM Gateway (FastAPI + httpx + SQLAlchemy async) 가 50~200 동접 부하에서 통과한 조합이다 — 일반 FastAPI 프로젝트에서도 같은 함정이 있고 해법도 같다.

## 사용 시점

- "async 패턴", "fastapi 비동기 처음"
- "sse 스트리밍 fastapi", "OpenAI 호환 streaming proxy"
- "asyncio Semaphore", "concurrent 제한"
- "fastapi lifespan", "startup/shutdown"
- "Depends DI", "async session 주입"
- "background task", "fire-and-forget", "asyncio.create_task"
- "httpx async stream", "sqlalchemy async session"

특히 *sync 코드가 섞여서 throughput 이 안 나올 때*, *connection leak / TooManyConnections*, *streaming 끊김* 류 증상이면 이 6 패턴 중 하나를 빼먹은 것이다.

## 6 패턴 한눈에

| # | 패턴 | 도구 | 해결하는 문제 |
|---|---|---|---|
| 1 | SSE 스트리밍 프록시 | `httpx.AsyncClient.stream` | upstream chunk 를 그대로 클라이언트에 흘리기 |
| 2 | Lifespan | `@asynccontextmanager` | startup 자원 생성 + shutdown 정리 |
| 3 | Dependency Injection | `Depends(get_session)` | request 별 session 주입, 테스트 가능 |
| 4 | Semaphore | `asyncio.Semaphore(N)` | 동시 in-flight 제한, OOM 방지 |
| 5 | Async DB | `async with session.begin()` | 커밋/롤백 자동, 누수 방지 |
| 6 | Background task | `asyncio.create_task` | 응답 즉시 + 비동기 후처리 |

## 1. SSE 스트리밍 프록시 (httpx)

OpenAI 호환 게이트웨이가 vLLM 으로 요청을 forward 하면서 chunk 를 끊김 없이 흘려야 하는 경우.

```python
import httpx
from fastapi.responses import StreamingResponse

async def proxy_stream(payload: dict):
    timeout = httpx.Timeout(connect=5.0, read=None, write=10.0, pool=5.0)
    async with httpx.AsyncClient(timeout=timeout) as client:
        async with client.stream("POST", UPSTREAM_URL, json=payload) as resp:
            resp.raise_for_status()
            async for chunk in resp.aiter_bytes():
                yield chunk

@router.post("/v1/chat/completions")
async def chat(body: dict):
    return StreamingResponse(proxy_stream(body), media_type="text/event-stream")
```

핵심:
- `client.stream(...)` 은 *async context manager* — `async with` 두 번 (client + stream) 필수
- `aiter_bytes()` 가 chunk 를 그대로 반환 → 가공 없이 yield
- `read=None` — SSE 는 개별 chunk 사이 간격이 길 수 있어 read timeout 비활성화 (단 connect/write 는 유지)

흔한 함정:
- **`aiter_text()` 사용** — UTF-8 부분 chunk 가 끊기면 `UnicodeDecodeError`. `aiter_bytes()` 가 안전하다.
- **`[DONE]` 처리** — OpenAI SSE 는 `data: [DONE]\n\n` 으로 종료. 그대로 forward 하면 OK, 클라이언트가 처리. 게이트웨이가 끼어들 필요 없음.
- **lifespan 으로 client 공유** — 매 요청마다 `AsyncClient()` 생성하면 connection pool 이 매번 새로 → TCP handshake 비용. lifespan 에서 만든 `app.state.client` 를 재사용 (패턴 #2 참조).
- **백프레셔 무시** — 클라이언트가 느리면 `yield` 가 await 에서 막히고, 동시에 upstream 도 멈춘다 (그게 의도). 별도 큐로 buffer 하지 말 것 — OOM 의 시작.

## 2. Lifespan event (startup/shutdown)

`@app.on_event("startup")` 은 deprecated. 0.93+ 부터는 lifespan context manager.

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
import httpx

@asynccontextmanager
async def lifespan(app: FastAPI):
    # ── startup ──
    app.state.http = httpx.AsyncClient(timeout=30.0)
    app.state.engine = create_async_engine(DB_URL, pool_size=20)
    yield
    # ── shutdown ──
    await app.state.http.aclose()
    await app.state.engine.dispose()

app = FastAPI(lifespan=lifespan)
```

특징:
- `yield` 전후 = startup / shutdown
- `app.state.*` 에 자원 저장 → 라우트에서 `request.app.state.http` 로 접근
- shutdown 코드는 *Ctrl+C / SIGTERM* 시에도 실행 (uvicorn graceful shutdown 한정)

흔한 함정:
- **lifespan 누락** — `httpx.AsyncClient()` 를 모듈 top-level 에서 생성하면 import 시점에 만들어져 이벤트 루프 없음 → `RuntimeError: no running event loop`. 항상 lifespan 안에서 생성.
- **shutdown 누락** — `aclose()` 안 부르면 connection leak, log spam (`Unclosed client session`). 항상 yield 다음에 정리.
- **여러 lifespan 합치기** — 라이브러리가 자체 lifespan 을 제공하면 `contextlib.AsyncExitStack` 으로 합친다.

## 3. Dependency Injection (`Depends`)

DB session, auth, quota 등 *request 별 객체* 주입.

```python
from typing import AsyncIterator
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

session_factory: async_sessionmaker[AsyncSession]  # lifespan 에서 만들어 둠

async def get_session() -> AsyncIterator[AsyncSession]:
    async with session_factory() as session:
        yield session                # 요청 끝나면 자동 close

@router.post("/items")
async def create_item(
    body: ItemIn,
    session: AsyncSession = Depends(get_session),
):
    item = Item(**body.model_dump())
    async with session.begin():
        session.add(item)
    return {"id": item.id}
```

특징:
- `Depends(...)` 는 매 요청마다 호출 — `yield` 는 generator 처럼 동작하고 `finally` 자리에서 cleanup
- 중첩 가능 — `get_user(session=Depends(get_session))` 처럼 DI 가 DI 를 받음
- 테스트에서 `app.dependency_overrides[get_session] = mock_session_factory` 로 교체

흔한 함정:
- **`Depends` 없이 global session** — 테스트에서 mock 불가, 동시 요청이 같은 session 공유 → race condition.
- **session 을 라우트 밖 task 로 넘기기** — `asyncio.create_task(work(session))` 하면 라우트가 끝나면서 session 이 close 됨. 백그라운드 task 는 *자체 session* 을 새로 열어야 한다 (패턴 #6 참조).
- **`Depends(...)` 안에 sync 함수** — 동작은 하지만 thread pool 로 빠짐. async 라우트에 async dependency 를 일관되게 쓸 것.

## 4. asyncio.Semaphore (concurrent limit)

이벤트 루프는 단일 스레드라 *수천 개 task 를 동시에 띄울 수 있다* — 그게 문제다. 업스트림이나 GPU 가 그만큼 못 받으면 OOM/큐 폭주. Semaphore 가 admission control.

```python
import asyncio

# 모듈 레벨 또는 lifespan 에서
SEM = asyncio.Semaphore(50)  # 동시에 50개만 진행

async def limited_call(payload):
    async with SEM:
        return await heavy_work(payload)
```

사용자별 한도면 dict 캐시:

```python
_user_sems: dict[str, asyncio.Semaphore] = {}

async def user_slot(user_id: str, limit: int):
    sem = _user_sems.setdefault(user_id, asyncio.Semaphore(limit))
    async with sem:
        yield
```

흔한 함정:
- **모듈 import 시점에 `Semaphore()` 생성** — 이벤트 루프 없으면 OK 지만 (Python 3.10+), 가능하면 lifespan 안에서 만들어 deprecated 경고 회피.
- **acquire 만 하고 release 안 함** — `async with SEM:` 으로 항상 context manager. 직접 `acquire/release` 쓰면 예외 시 leak.
- **deadlock** — slot 안에서 다시 같은 slot 진입 (재귀 호출). 한도가 1 이면 즉시 deadlock. nested 호출 경로 점검.
- **분산 환경** — Semaphore 는 *worker-local*. 워커 N 개면 실제 한도 N×limit. 분산이 필요하면 Redis 분산 세마포 또는 인그레스단 admission.

## 5. SQLAlchemy async session

`session.begin()` 이 transaction context — exit 시 자동 commit/rollback.

```python
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker

engine = create_async_engine(
    "postgresql+asyncpg://...",
    pool_size=20, max_overflow=40, pool_pre_ping=True,
)
session_factory = async_sessionmaker(engine, expire_on_commit=False)

# 사용
async with session_factory() as session:
    async with session.begin():
        session.add(obj)
    # commit 자동, 예외 시 rollback
```

읽기 전용:

```python
async with session_factory() as session:
    result = await session.scalar(select(User).where(User.id == uid))
```

특징:
- `session.begin()` 은 transaction 시작 — `with session.begin():` 빠지면 변경 사항이 안 들어간다
- `expire_on_commit=False` — commit 후 ORM 객체 attribute 접근 시 lazy reload 안 함 (async 환경에서 lazy load 는 사실상 금지)
- pool 은 lifespan 끝에 `await engine.dispose()` 로 정리

흔한 함정:
- **sync session 혼용** — `Session()` 과 `AsyncSession()` 섞으면 `MissingGreenlet` 또는 blocking. async 프로젝트는 전부 async.
- **lazy load** — `obj.related_items` 가 lazy 면 async 컨텍스트에서 `MissingGreenlet`. `selectinload` / `joinedload` 로 eager.
- **session 공유** — 여러 task 가 같은 session 을 쓰면 cursor 충돌. *task 당 session 1개*.
- **pool 부족** — 50 동접인데 `pool_size=5, max_overflow=10` 이면 `QueuePool limit overflow`. 동접 ≤ pool_size + max_overflow.

## 6. Background task (fire-and-forget)

응답을 *즉시 반환*하고 무거운 후처리는 비동기로.

```python
import asyncio

async def record_usage(user_id: str, tokens: int):
    async with session_factory() as session:        # 자체 session
        async with session.begin():
            session.add(UsageLog(user_id=user_id, tokens=tokens))

@router.post("/v1/chat/completions")
async def chat(...):
    response = await call_upstream(...)
    asyncio.create_task(record_usage(user_id, response.tokens))
    return response
```

또는 FastAPI `BackgroundTasks` (간단한 경우):

```python
from fastapi import BackgroundTasks

@router.post("/items")
async def create(bg: BackgroundTasks, ...):
    bg.add_task(record_usage, user_id, tokens)
    return {"ok": True}
```

차이:
- `BackgroundTasks` — 응답 *전송 후* 실행, 같은 이벤트 루프, 예외 발생 시 로그만
- `asyncio.create_task` — 즉시 실행, 응답과 병렬, fire-and-forget

흔한 함정:
- **task 참조 없이 `create_task`** — Python GC 가 weak ref 로 task 를 수거할 수 있음. 가능하면 `app.state.bg_tasks: set` 에 저장하고 `task.add_done_callback(bg_tasks.discard)`.
- **task 안에서 라우트 session 사용** — 라우트가 끝나면 session close. background 는 *자체 session* 새로 열기.
- **예외 사일런트** — `create_task` 의 예외는 await 하기 전엔 안 나타남. `done_callback` 으로 `task.exception()` 로깅.
- **무거운 task fire-and-forget 남발** — 1000개 task 동시에 떠서 DB pool 고갈. 정말 무거우면 별도 worker 큐 (Celery, RQ, Arq) 로.

## 흔한 함정 종합

이 6 패턴을 처음 도입할 때 자주 겹치는 실수:

1. **`async def` 안에서 sync 함수 호출** — `requests.get(...)`, `time.sleep(...)`, sync `Session` — 전부 이벤트 루프 blocking. throughput 1로 떨어진다. 의심되면 `asyncio.run_in_executor` 로 격리.
2. **`httpx.Client` (sync) 와 `AsyncClient` 혼용** — sync `Client` 를 async 컨텍스트에서 쓰면 blocking. 프로젝트 전체에서 `AsyncClient` 만 사용.
3. **session 을 task 사이에 공유** — 라우트 session 을 `create_task` 로 넘기는 것은 use-after-close 의 시작. 패턴 #6 참조.
4. **lifespan 누락** — startup 에서 만든 자원을 shutdown 에서 정리 안 하면 connection leak. CTRL+C 종료 시 `Unclosed connection` 경고가 신호.
5. **Depends 없이 global state 접근** — 테스트가 어렵고 동시 요청이 우연히 같은 객체 공유 → race. 항상 `Depends`.
6. **Semaphore 한도가 pool 크기보다 큼** — Semaphore 100 인데 DB pool 30 이면 70 개가 pool 대기에서 막힌다. 한도 정렬: Semaphore ≤ DB pool ≤ 업스트림 capacity.
7. **`run_in_executor` 의존** — sync 라이브러리를 매번 thread pool 로 돌리면 thread 가 늘어 GIL 경합. 가능하면 진짜 async 라이브러리 (asyncpg, httpx, aiofiles) 로.

## 시작 체크리스트

1. `templates/lifespan.py.template` 복사 → `main.py` 의 `lifespan`. `httpx.AsyncClient` + `create_async_engine` startup/shutdown 등록.
2. `templates/streaming-proxy.py.template` 복사 → SSE 스트리밍 라우트가 필요하면.
3. `get_session()` DI 작성 → 모든 라우트에 `Depends(get_session)`.
4. 동접 한도가 있으면 `asyncio.Semaphore(N)` 1개 또는 사용자별 dict 캐시.
5. `async with session.begin():` 패턴 일관 적용 (단일 transaction 보장).
6. fire-and-forget 후처리는 `asyncio.create_task` + 자체 session.
7. 부하 테스트 — sync 코드가 섞였는지 throughput 으로 확인 (`requests/sec` 이 동접에 비례하지 않으면 어딘가 blocking).

## 관련 skill

- `fastapi-gateway-pattern` — 본 6 패턴이 들어가는 OpenAI 호환 게이트웨이 전체 구조
- `quota-rate-limit-pattern` — 패턴 #4 Semaphore 를 RPM/Daily 와 결합
- `prometheus-fastapi-metrics` — 본 패턴들 위에 메트릭 추가
- `postgres-migration-from-sqlite` — 패턴 #5 SQLAlchemy async 의 DB 백엔드 이전
