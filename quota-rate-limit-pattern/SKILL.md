---
name: quota-rate-limit-pattern
description: 'API 게이트웨이 3계층 quota/rate-limit 패턴. 사용 시점 — "rpm 제한", "daily token limit", "concurrent 한도", "429 quota exceeded", "slowapi", "asyncio Semaphore", "rate-limit 설계". slowapi (RPM) + asyncio.Semaphore (concurrent) + SQL (daily) 3 layer 결합 + HTTP 429 응답 형식.'
---

# quota-rate-limit-pattern

API 게이트웨이에서 사용자 요청을 거부해야 할 이유는 *시간 단위*에 따라 다르다. 단일 메커니즘으로 전부 막으려 하면 어딘가가 부정확하거나 메모리/DB가 터진다. RPM(분 단위 burst) · Concurrent(현재 in-flight) · Daily(누적 토큰)을 *서로 다른 도구*로 막고, 각 거부에 별도 reason code 를 붙인다 — 이게 GEM-LLM Gateway가 50/100/200 동접 부하를 통과한 패턴이다.

## 사용 시점

- "rpm 제한", "daily token limit", "concurrent 한도"
- "429 quota exceeded", "rate-limit 설계"
- "slowapi", "asyncio Semaphore"
- 단일 도구(예: slowapi 만)로 막다가 OOM/오버차지가 발생한 경우
- 거부 사유를 클라이언트에게 구분해서 알려줘야 할 때 (재시도 로직 분기)

게이트웨이가 *백엔드 보호* + *비즈니스 한도* + *공격 차단* 세 가지를 동시에 해야 한다면 3계층이 거의 항상 필요하다.

## 3계층 비교

| 계층 | 도구 | 시간 단위 | 상태 저장 | 적합 |
|---|---|---|---|---|
| RPM | `slowapi @limiter.limit("60/minute")` | 1분 (sliding/fixed) | 메모리 (in-process) | burst 차단, 봇/스크립트 방어 |
| Concurrent | `asyncio.Semaphore(N)` per user | 즉시 (현재 in-flight) | 메모리 (worker-local) | OOM/GPU 큐 폭주 방지 |
| Daily | DB `SELECT SUM(tokens) FROM usage_log WHERE ts >= today` | 24시간 (자정 reset) | DB (모든 워커 공유) | 비즈니스 한도, 과금 |

세 계층은 *교집합* 검사다 — 셋 중 하나라도 막히면 거부. 통과 순서는 보통 RPM → Concurrent → Daily (싸고 빠른 검사부터).

```
[Request]
  ↓
[1] slowapi.@limit            ─→ 429 rpm_limit       (라우트 데코레이터, DB 안 침)
  ↓
[2] async with concurrency_slot → 429 concurrent_limit (Semaphore acquire 실패)
  ↓
[3] await check_quota(session)  → 429 daily_token_limit (DB SUM 검사)
  ↓
[Upstream proxy]
```

## 계층 1 — slowapi RPM

```python
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded

def key_from_request(request: Request) -> str:
    auth = request.headers.get("authorization", "")
    if auth.lower().startswith("bearer "):
        token = auth.split(" ", 1)[1].strip()
        return token[:16]                       # raw key 노출 X — prefix만
    return get_remote_address(request)

limiter = Limiter(key_func=key_from_request, default_limits=["1200/minute"])

# 라우트
@router.post("/v1/chat/completions")
@limiter.limit("60/minute")                     # per-key, 분당 60
async def chat(...): ...
```

특징:
- 라우트 데코레이터 한 줄로 적용 — DB I/O 0
- `key_func` 으로 사용자 단위/IP 단위 자유 선택 (raw API key 절대 *그대로* 쓰지 말고 prefix만)
- 거부 시 `RateLimitExceeded` 예외 → 미들웨어 핸들러에서 OpenAI 형식 429 변환

```python
async def rate_limit_handler(request, exc: RateLimitExceeded) -> JSONResponse:
    return JSONResponse(
        status_code=429,
        content={"error": {
            "message": f"Rate limit exceeded: {exc.detail}",
            "type": "rate_limit_error",
            "code": "rpm_limit",                 # ← 명확한 reason
        }},
        headers={"Retry-After": "60"},
    )
```

## 계층 2 — asyncio.Semaphore concurrent

```python
import asyncio
from contextlib import asynccontextmanager

_concurrency_semaphores: dict[str, tuple[int, asyncio.Semaphore]] = {}
_sem_lock = asyncio.Lock()

async def _get_semaphore(user_id: str, limit: int) -> asyncio.Semaphore:
    async with _sem_lock:
        cached = _concurrency_semaphores.get(user_id)
        if cached is None or cached[0] != limit:           # 한도 변경 시 재생성
            sem = asyncio.Semaphore(limit)
            _concurrency_semaphores[user_id] = (limit, sem)
            return sem
        return cached[1]

@asynccontextmanager
async def concurrency_slot(user_id: str, limit: int):
    sem = await _get_semaphore(user_id, limit)
    await sem.acquire()
    try:
        yield
    finally:
        sem.release()
```

라우트에서:

```python
async with concurrency_slot(auth.user.id, limit=quota.concurrent_limit):
    ...                                          # in-flight 가 limit 넘으면 acquire 대기
```

대기를 *원하지 않으면* 즉시 거부:

```python
sem = await _get_semaphore(user_id, limit)
if not sem.locked() and sem._value > 0:
    await sem.acquire()
else:
    raise HTTPException(429, detail={"code": "concurrent_limit"})
```

(`sem._value` 는 internal — 안전하게 하려면 `acquire()` 의 `timeout` 으로 짧게 시도.)

## 계층 3 — DB daily token limit

```python
@dataclass
class QuotaSnapshot:
    allowed: bool
    reason: str | None
    daily_tokens_used: int
    daily_token_limit: int
    rpm_used: int
    rpm_limit: int

async def check_quota(session, user_id, estimated_tokens=0) -> QuotaSnapshot:
    quota = await session.get(Quota, user_id)
    now = datetime.now(UTC)
    day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)

    daily_total = await session.scalar(
        select(func.coalesce(
            func.sum(UsageLog.prompt_tokens + UsageLog.completion_tokens), 0
        )).where(UsageLog.user_id == user_id, UsageLog.ts >= day_start)
    ) or 0

    if daily_total + estimated_tokens > quota.daily_token_limit:
        return QuotaSnapshot(False, "daily_token_limit", daily_total, ...)
    return QuotaSnapshot(True, None, daily_total, ...)
```

특징:
- 모든 워커/노드가 같은 DB 를 보므로 정확
- 비싸다 — 매 요청마다 SUM. 사용량이 많으면 `(user_id, ts)` 인덱스 필수 + 일일 누적 캐시 테이블 고려
- daily 는 `estimated_tokens` 를 더해서 *사전* 검사 (응답 후 reject 는 사용자에게 토큰 소비만 시키고 거부)

## HTTP 429 응답 형식 (reason code 분리)

OpenAI 클라이언트 호환 + 디버깅 용이성을 위해:

```json
{
  "error": {
    "message": "Quota exceeded: daily_token_limit",
    "type": "rate_limit_error",
    "code": "daily_token_limit"
  }
}
```

`code` 필드 후보: `rpm_limit` / `concurrent_limit` / `daily_token_limit` (`quota_exceeded` 같은 단일 코드는 클라이언트 재시도 로직을 망친다 — daily 는 재시도해봐야 무의미, RPM 은 1분 후 재시도, concurrent 는 즉시 백오프).

응답 헤더에 잔여량도 같이:

```python
headers={
    "Retry-After": "60",
    "x-ratelimit-remaining": str(max(0, snap.rpm_limit - snap.rpm_used)),
    "x-daily-tokens-remaining": str(max(0, snap.daily_token_limit - snap.daily_tokens_used)),
}
```

## Prometheus 카운터 통합

각 거부를 *별도 라벨*로 카운트해야 어느 계층이 막고 있는지 보인다:

```python
gateway_quota_rejections_total = Counter(
    "gateway_quota_rejections_total",
    "Quota rejections",
    ["reason"],                   # rpm_limit | concurrent_limit | daily_token_limit
)

# cardinality 보호
def _record_rejection(reason: str) -> None:
    if reason in {"rpm_limit", "concurrent_limit", "daily_token_limit"}:
        gateway_quota_rejections_total.labels(reason=reason).inc()
```

부하 테스트 후 `/metrics` 에서:

```
gateway_quota_rejections_total{reason="rpm_limit"} 169
gateway_quota_rejections_total{reason="daily_token_limit"} 105
gateway_quota_rejections_total{reason="concurrent_limit"} 12
```

→ daily 가 더 많이 막힌다면 한도 너무 낮음, RPM 이 압도적이면 burst 패턴 문제, concurrent 가 많으면 사용자당 동접 한도 재검토.

## 분산 환경에서의 한계

| 계층 | 단일 워커 | 멀티 워커 / 멀티 노드 | 분산 대안 |
|---|---|---|---|
| slowapi RPM | 정확 | per-process 메모리 → N 배 허용 | `slowapi.storage_uri = "redis://..."` |
| asyncio.Semaphore | 정확 | worker-local — 분산 X | Redis Lock, 또는 별도 admission controller |
| DB daily | 정확 | 정확 (DB 공유) | 그대로 OK |

GEM-LLM 은 단일 uvicorn 워커 + 50~200 동접 → 메모리 백엔드 그대로 충분. 200+ 동접 또는 멀티 워커로 가면:

1. slowapi → Redis backend (`Limiter(storage_uri="redis://...")`)
2. concurrency → Redis 분산 세마포 (`aioredlock` 등) 또는 인그레스 단의 admission controller (envoy `local_ratelimit`)
3. DB daily → 그대로

## GEM-LLM 사례 (50/100/200 동접 부하)

case 12 SQLAlchemy pool 수정 (`pool_size=50, max_overflow=150`) 후 부하 테스트 결과:

| 동접 | 총 요청 | 5xx | 429 (rpm) | 429 (daily) | 429 (concurrent) |
|---|---|---|---|---|---|
| 50 | 2,300 | 0 | 12 | 0 | 0 |
| 100 | 4,800 | 0 | 47 | 38 | 3 |
| 200 | 9,200 | 8 (502 upstream) | 169 | 105 | 12 |

200 동접에서도 게이트웨이 자체는 5xx 없이 RPM/daily/concurrent 가 정상 작동 — 5xx 는 업스트림 vLLM 의 KV cache 적체 (게이트웨이 책임 X). 이게 3계층 분리의 가치 — 어디가 막고 있는지 라벨로 즉시 보인다.

## 흔한 함정

1. **SQLite write-lock 경합 (case 14)** — 100+ 동접에서 daily 검사가 SUM 하는 동안 usage INSERT 가 lock 대기. WAL 모드로 완화되지만 본질적으로 SQLite 한계. PostgreSQL 마이그레이션 (`postgres-migration-from-sqlite` 참조) 또는 daily 누적 캐시 테이블 도입.

2. **RPM 카운터 reset 타이밍** — slowapi 는 fixed window (분 단위 절대 시각). 59초에 60회 + 다음 분 0초에 60회 = 1초에 120회 burst 가능. sliding window 가 필요하면 Redis backend + `slowapi.Limiter(strategy="moving-window")`.

3. **deadlock** — `concurrency_slot` 안에서 다시 `concurrency_slot` (예: tool calling 재진입) → 자기 자신을 기다리는 deadlock. nested 호출 경로 점검, 또는 reentrant 한도로 분리.

4. **Semaphore 한도 변경 미반영** — 관리자가 quota 를 늘려도 캐시된 Semaphore 가 기존 한도 유지. 위 `_get_semaphore` 처럼 `(limit, sem)` 튜플로 캐시 + 한도 변경 감지 시 재생성.

5. **estimated_tokens 0** — daily 검사 시 추정 토큰을 0 으로 두면 한도에 *정확히* 도달한 사용자도 통과 → 다음 응답 후 한도 초과. 입력 길이로 최소 추정값 (예: `prompt_chars / 4`) 넣을 것.

6. **거부 카운터 cardinality 폭발** — `reason` 라벨에 자유 문자열 넣으면 Prometheus 가 죽는다. `_record_rejection` 처럼 화이트리스트 강제.

7. **단일 reason code 로 통합** — `quota_exceeded` 만 쓰면 클라이언트가 RPM/daily 구분 못 함 → daily 를 1분 후 재시도 같은 무의미한 동작. 처음부터 분리할 것.

## 시작 체크리스트

1. `templates/quota-service.py.template` 복사 → `services/quota.py`
2. slowapi `Limiter` 등록 (`main.py` lifespan 또는 미들웨어)
3. 라우트에 `@limiter.limit("60/minute")` 데코레이터
4. 라우트 본문에 `async with concurrency_slot(user_id, limit) + check_quota(session, user_id)` 순서로 호출
5. Prometheus 카운터 `gateway_quota_rejections_total` 등록 + `/metrics` 노출
6. 부하 테스트 (locust 등) 로 세 reason 모두 발생하는지 확인 (`gateway_quota_rejections_total{reason=...}` 카운트)
7. 분산 워커 운영 시 — slowapi storage_uri 를 Redis 로

## 관련 skill

- `fastapi-gateway-pattern` — 본 패턴이 들어가는 5계층 게이트웨이 전체 구조
- `gem-llm-gateway-debug` — 본 패턴 GEM-LLM 특화 구현 디버깅
- `gem-llm-load-test` — 50/100/200 동접 시나리오로 본 패턴 검증
- `postgres-migration-from-sqlite` — daily 검사 SQLite 한계 도달 시 이전
