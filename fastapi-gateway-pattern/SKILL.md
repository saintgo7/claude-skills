---
name: fastapi-gateway-pattern
description: 'FastAPI로 OpenAI 호환 LLM 게이트웨이 구축 패턴. 사용 시점 — "openai 호환 게이트웨이", "vllm 앞단", "api key 인증", "rate limit fastapi", "스트리밍 sse 프록시", "quota 시스템", "sqlalchemy pool 설정". 인증/라우팅/quota/streaming/usage logging 5계층 구조 + 50동접 검증된 SQLAlchemy pool 설정.'
---

# fastapi-gateway-pattern

FastAPI 앞단에서 하나 이상의 OpenAI 호환 백엔드(vLLM, TGI, llama.cpp server, sglang 등)를 묶어서 제공하는 LLM 게이트웨이 패턴. 인증·쿼터·스트리밍·로깅 5계층을 분리해서 작성하면 백엔드/모델/클라이언트가 바뀌어도 코드 손상 없이 확장된다.

## 사용 시점

- 여러 vLLM(또는 호환) 인스턴스를 단일 엔드포인트로 통합하고 싶을 때
- API key 발급/회수, 사용자별 일일 토큰·RPM·동시성 제한이 필요할 때
- OpenAI SDK(`base_url`만 바꿔서) 그대로 쓰는 클라이언트가 있을 때
- 스트리밍(SSE) 응답을 그대로 패스스루하면서 사용량은 따로 기록하고 싶을 때
- 50~수백 동시 접속에서도 죽지 않는 DB pool/세마포 설정이 필요할 때

게이트웨이가 *모델 자체*는 호스팅하지 않는다. 인증·과금·라우팅·관측만 담당하고 추론은 업스트림에 위임한다.

## 5계층 아키텍처

```
[Client: Authorization: Bearer <prefix>_<32hex>]
  ↓
[1] Auth middleware            — Bearer 추출, prefix lookup, hash 검증, AuthContext 주입
  ↓
[2] RateLimit middleware       — slowapi (per-key RPM, in-memory)
  ↓
[3] Logging middleware         — 요청/응답 메타데이터 (key prefix만, raw 키는 절대 X)
  ↓
[4] Routes layer               — /v1/chat/completions, /v1/models, /healthz, /metrics, /admin/*
  ↓
[5] Services layer             — quota / proxy(httpx) / usage(async INSERT)
  ↓
[Upstream: OpenAI 호환 백엔드 N개]
```

각 계층의 책임을 섞지 않는 게 핵심이다. 예: route 함수에서 직접 httpx 호출 금지 → service.proxy 통과. 미들웨어에서 DB I/O 금지 → 라우트의 Depends에서.

## 디렉터리 구조

```
gateway/
├── main.py             # create_app(), lifespan, 미들웨어/라우터 등록
├── config.py           # pydantic-settings (.env 로딩)
├── db.py               # async engine + session factory (싱글턴)
├── deps.py             # FastAPI Depends 헬퍼 (get_db, get_auth, ...)
├── models.py           # SQLAlchemy ORM (User, ApiKey, Quota, UsageLog)
├── schemas.py          # Pydantic 요청/응답
├── middleware/
│   ├── auth.py         # Bearer 검증, AuthContext
│   ├── rate_limit.py   # slowapi Limiter
│   └── logging.py      # 요청 로깅
├── routes/
│   ├── health.py       # /healthz, /readyz, /metrics
│   ├── models.py       # /v1/models
│   ├── chat.py         # /v1/chat/completions (stream + non-stream)
│   └── admin.py        # /admin/users, /admin/keys, /admin/usage
├── services/
│   ├── proxy.py        # httpx → upstream
│   ├── quota.py        # daily/RPM/concurrent 검사
│   └── usage.py        # async UsageLog INSERT
└── utils/
    ├── crypto.py       # SHA256(salt + raw_key)
    └── ids.py          # ULID 생성, KEY_PREFIX 상수
```

## 인증 패턴

### 키 형식

권장: `<prefix>_<32hex>` (예: `app_live_a3f2c8e1...`).
- prefix는 환경 식별 (`live`/`test`) + 발급 주체 표기에 사용
- 32hex(=128bit)면 무차별 대입 방어 충분
- DB 저장 시 raw 키는 절대 보관 X — `key_hash = SHA256(salt || raw)` + `key_prefix(앞 16자)` 만 저장

### 검증 흐름

```python
1. Authorization: Bearer ... 헤더 추출
2. 형식 검사 (prefix_ 시작?)
3. lookup_hash = SHA256(salt || raw)
4. SELECT * FROM api_keys WHERE key_hash = ? AND revoked = false
5. 매치 행에 대해 verify_api_key() (timing-safe compare)
6. user.disabled 체크 → AuthContext(user, api_key) 반환
7. 어디서든 실패 → 401 invalid_api_key
```

prefix lookup이 *없으면* 모든 키 hash를 순회해야 하므로 키가 많아지면 느려진다. `key_prefix` 컬럼에 인덱스 + 정확 일치 lookup 후 hash 비교가 표준 패턴.

`X-Admin-Key` 헤더는 별개 채널로 — 환경변수 `ADMIN_KEY`와 직접 비교 (DB 없이).

## 모델 라우팅

`config.py`의 `upstream_map: dict[str, str]`로 모델 ID → 업스트림 base URL 매핑.

```python
@property
def upstream_map(self) -> dict[str, str]:
    return {
        "<model_name_dense>": self.backend_a_url,   # 예: localhost:8001
        "<model_name_moe>":   self.backend_b_url,   # 예: localhost:8002
    }
```

route는 `payload["model"]`을 보고 `resolve_upstream(model)` 호출. 알 수 없는 모델 → `400 unknown_model`.

`/v1/models`에 노출하는 `served_model_names`는 `upstream_map.keys()`와 *같아야 한다*. 둘이 어긋나면 OpenAI SDK 클라이언트가 `model not found`로 실패한다 — 모델 이름 변경 시 항상 두 곳 동시 수정.

## Quota (3중)

각 사용자에 대해 세 가지 상한을 동시에 적용:

| 종류 | 메커니즘 | 보관 위치 | 정확도 |
|---|---|---|---|
| RPM (분당 요청 수) | `slowapi.Limiter` | in-memory | 단일 워커에서 정확, 분산 시 부정확 |
| Concurrent (동시 in-flight) | `asyncio.Semaphore` per user | in-memory dict | worker-local |
| Daily tokens | `SELECT SUM(prompt+completion) FROM usage_log WHERE ts >= today` | DB | 정확 (모든 워커 공유) |

```python
async with concurrency_slot(user_id, limit=quota.concurrent_limit):
    snapshot = await check_quota(session, user_id, estimated_tokens=...)
    if not snapshot.allowed:
        raise HTTPException(429, detail={"code": snapshot.reason})
    result = await proxy.chat_completions(payload)
```

다중 uvicorn 워커 환경에서 RPM/concurrency를 정확하게 강제하려면 Redis(또는 비슷한 공유 카운터)로 옮긴다. 단일 워커 + 50동접 정도면 in-memory로 충분.

## 스트리밍 프록시 (SSE 패스스루)

핵심: `httpx.AsyncClient.stream()`으로 업스트림 SSE를 받아 *수정 없이* 클라이언트로 전달, 도중에 usage chunk만 가로채서 토큰 카운트 갱신.

```python
async with client.stream("POST", url, json=payload) as resp:
    async for line in resp.aiter_lines():
        if line.startswith("data: "):
            data = line[6:]
            if data.strip() != "[DONE]":
                obj = json.loads(data)
                if "usage" in obj:                  # 마지막 청크 직전
                    prompt_tokens = obj["usage"]["prompt_tokens"]
                    completion_tokens = obj["usage"]["completion_tokens"]
        yield (line + "\n").encode("utf-8")        # 그대로 패스스루
```

주의:
- `payload["stream"] = True` 강제 + `stream_options.include_usage = True` 설정 (vLLM/일부 백엔드는 이게 있어야 usage chunk 보냄)
- SSE 빈 줄(`\n\n`)도 그대로 전달해야 클라이언트 SDK가 이벤트 경계를 인식
- `[DONE]` 도착 후 백그라운드 task로 `record_usage()` 호출 — 응답 종료를 막지 말 것
- httpx 클라이언트는 요청별로 새로 만들거나, 앱-수명 공유 시 `limits=Limits(max_keepalive_connections=...)` 튜닝

## 사용량 로깅

응답 종료 *후* 별도 세션에서 INSERT → 응답 latency에 영향 없음.

```python
# routes/chat.py 마지막에
from fastapi import BackgroundTasks
background_tasks.add_task(
    record_usage,
    user_id=auth.user.id,
    key_id=auth.api_key.id,
    model=payload["model"],
    prompt_tokens=result.prompt_tokens,
    completion_tokens=result.completion_tokens,
    latency_ms=result.latency_ms,
    status=result.status_code,
)
```

`record_usage()`는 자체 session factory에서 새 세션을 열고 commit한다. 라우트의 세션을 재사용하면 트랜잭션 경계가 꼬인다.

## SQLAlchemy pool 설정 (중요)

기본값(`pool_size=5, max_overflow=10`)은 50 동시 접속에서 즉시 터진다:

```
sqlalchemy.exc.QueuePoolError: QueuePool limit of size 5 overflow 10 reached,
connection timed out, timeout 30.00
```

검증된 설정:

```python
create_async_engine(
    settings.db_url,
    pool_pre_ping=True,
    pool_size=50,         # 기본 풀
    max_overflow=150,     # 피크 시 추가 (총 200)
    pool_timeout=10,      # 대기 후 빠르게 실패 → 호출자에게 502/503
)
```

산정 근거:
- 1 요청 = 인증 lookup 1 + quota 검사 2 + usage INSERT 1 = 평균 3~4 connection
- 동접 50 × 4 = 200 → pool_size + max_overflow ≥ 200
- `pool_timeout`은 짧게(5~10s) — 30s는 클라이언트 타임아웃과 충돌

SQLite + aiosqlite는 동시 writer 제약이 있어 WAL 모드 + `synchronous=NORMAL` 필수:

```python
async with engine.begin() as conn:
    await conn.execute(text("PRAGMA journal_mode=WAL"))
    await conn.execute(text("PRAGMA foreign_keys=ON"))
    await conn.execute(text("PRAGMA synchronous=NORMAL"))
```

100+ 동접이면 PostgreSQL 권장.

## 흔한 에러 매핑

| 응답 | 원인 | 점검 위치 |
|---|---|---|
| `401 invalid_api_key` | prefix 불일치 / hash 불일치 / salt 변경 / revoked | `middleware/auth.py`, `api_keys.revoked` |
| `400 unknown_model` | `upstream_map`에 없는 모델 ID | `config.py`, `routes/models.py` (둘 다) |
| `400 admin_key required` | `X-Admin-Key` 헤더 누락 | `require_admin()` |
| `429 rate_limited` | slowapi RPM 초과 (정상 동작) | `middleware/rate_limit.py` |
| `429 daily_token_limit` | 사용자 일일 한도 초과 | `services/quota.py`, `quotas` 테이블 |
| `500 internal_error` | 미처리 예외 | 로그 traceback (fallback handler) |
| `500 QueuePool limit reached` | DB pool 부족 | `db.py` pool_size/max_overflow |
| `502 bad_gateway` | 업스트림 다운/타임아웃 | upstream `/health`, httpx 타임아웃 |
| `Invalid args for response field` | FastAPI가 dict를 모델로 검증 시도 | `@router.post(..., response_model=None)` |

## 검증된 성능 (참고)

50 동시접속 × 단일 노드(B-급 GPU 1장) + 단일 uvicorn 워커:

| 지표 | 값 |
|---|---|
| p50 latency | 144ms (DB lookup ~10ms + 업스트림 ~120ms + 오버헤드) |
| p99 latency | 4.1s (업스트림 큐 적체로 인한 outlier) |
| 처리량 | 45 req/s |
| 토큰 throughput | 1441 tok/s (출력 기준) |

게이트웨이 자체 오버헤드는 보통 5~15ms. p99가 1초를 넘으면 거의 항상 *업스트림*(GPU 큐 또는 KV cache eviction) 문제이고, 게이트웨이 코드 문제가 아니다 — 진단 시 `/metrics`로 게이트웨이 시간과 업스트림 시간을 분리해서 볼 것.

병목 의심 순서:
1. SQLAlchemy pool size — 로그에 `QueuePool` 보이면 pool_size 키우기
2. `asyncio.Semaphore` concurrent limit — 사용자당 5는 너무 빡빡할 수 있음
3. 업스트림 자체 큐 (vLLM `--max-num-seqs`)
4. `nvidia-smi` GPU util — 80%↓면 게이트웨이/스케줄링 문제, 95%+면 GPU bound

## 시작 체크리스트

새 프로젝트에 적용 시:

1. `templates/main.py.template`, `auth.py.template` 복사 → 모듈 이름·모델 이름 치환
2. `.env`에 다음 변수: `PORT`, `ADMIN_KEY`(32hex), `DB_URL`, `API_KEY_SALT`(32hex), `BACKEND_*_URL`, `DEFAULT_DAILY_TOKEN_LIMIT`, `DEFAULT_RPM`
3. `db.py`에 `pool_size=50, max_overflow=150` 명시
4. `upstream_map` + `served_model_names` 두 곳에 모델 등록
5. `OPENAI_BASE_URL=http://gateway:PORT/v1` + `OPENAI_API_KEY=<발급한 키>` 로 클라이언트 검증
6. 부하 테스트 (locust 등)로 50 동접에서 5xx 비율 < 1% 확인
7. `/metrics` 엔드포인트 노출 → Prometheus 스크랩

## 관련 skill

- `gem-llm-gateway-debug` — 본 패턴의 GEM-LLM 특화 구현 디버깅
- `gem-llm-load-test` — locust 기반 동접 검증 시나리오
- `gem-llm-vllm-debug` — 업스트림 vLLM 자체 디버깅
- `gem-llm-cloudflare-tunnel` — 게이트웨이를 외부에 노출할 때
