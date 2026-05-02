---
name: gem-llm-gateway-debug
description: GEM-LLM Gateway (FastAPI port 8080) 디버깅. 사용 시점 — "Gateway 500", "QueuePool", "unknown_model", "401 Invalid API key", "스트리밍 끊김", "/v1/chat 안됨", "/metrics 추가", "rate limit". 인증/quota/스트리밍 프록시 구조 + 흔한 함정.
---

# gem-llm-gateway-debug

## 구조

```
[Request: Bearer token]
  → middleware/auth.py        # API key SHA256 검증, AuthContext 주입
  → middleware/rate_limit.py  # slowapi (60 RPM)
  → middleware/logging.py     # 요청/사용량 로깅 (key prefix 8자만)
  → routes/chat.py            # /v1/chat/completions
  → services/quota.py         # daily/concurrent 검사
  → services/proxy.py         # httpx → vLLM upstream
  → services/usage.py         # async UsageLog INSERT
```

## 정상 endpoint

| | |
|---|---|
| `GET /healthz` | 200 — 프로세스 살아있음 |
| `GET /readyz` | 200 — 두 vLLM 모두 health OK |
| `GET /metrics` | Prometheus format |
| `GET /v1/models` | 인증 필요. `qwen2.5-coder-32b`, `qwen3-coder-30b` 반환 |
| `POST /v1/chat/completions` | 인증 + quota + 프록시 |
| `POST /admin/users` | X-Admin-Key 헤더 필요 |
| `POST /admin/keys` | 키 발급 (raw_key 1회 노출) |
| `GET /admin/usage` | 사용량 조회 |

## 시작 명령

```bash
cd /home/jovyan/gem-llm/src/gateway
set -a; source /home/jovyan/gem-llm/.env; set +a
nohup /home/jovyan/vllm-env/bin/python -m uvicorn gateway.main:app \
  --host 0.0.0.0 --port 8080 \
  > /home/jovyan/gem-llm/_logs/gateway.log 2>&1 &
```

`.env`는 src/gateway/.env에도 같은 사본 필요 (pydantic-settings가 cwd .env 찾음).

## .env 필수 변수

```
GATEWAY_PORT=8080
GATEWAY_ADMIN_KEY=admin_<32hex>     # 자동생성, 한 번만 표시
GATEWAY_DB_URL=sqlite+aiosqlite:////home/jovyan/gem-llm/_data/gateway.db
GATEWAY_API_KEY_SALT=salt_<32hex>   # 자동생성, 변경 시 기존 모든 키 무효
GATEWAY_VLLM_31B_URL=http://localhost:8001
GATEWAY_VLLM_26B_URL=http://localhost:8002
GATEWAY_DEFAULT_DAILY_TOKEN_LIMIT=50000
GATEWAY_DEFAULT_RPM=60
```

## 모델 라우팅 매핑

`src/gateway/gateway/config.py`:

```python
@property
def upstream_map(self) -> dict[str, str]:
    return {
        "qwen2.5-coder-32b": self.vllm_31b_url,  # → 8001
        "qwen3-coder-30b": self.vllm_26b_url,    # → 8002
    }
```

새 모델 추가 시 여기 + `routes/models.py`의 served_model_names 둘 다 업데이트.

## 흔한 에러 → 원인

| 응답 | 원인 |
|---|---|
| `401 invalid_api_key` | 키 prefix 또는 hash 불일치, salt 변경, 회수됨 |
| `400 unknown_model: gem-31b` | upstream_map 옛 이름 — case 11 마이그레이션 후 수정 필요 |
| `400 admin_key required` | X-Admin-Key 헤더 누락 또는 GATEWAY_ADMIN_KEY 불일치 |
| `429 rate_limited 60 per 1 minute` | slowapi 정상 작동 |
| `429 daily_token_limit` | quota.py — 사용자별 50K 한도 |
| `500 internal_error` | 내부 — 로그 traceback 확인 |
| `502 bad_gateway` | upstream vLLM 응답 안 함 — `gem-llm-vllm-debug` |

## 500 traceback 패턴

```bash
grep -B2 -A5 "ERROR\|Exception\|Traceback" /home/jovyan/gem-llm/_logs/gateway.log | tail -30
```

### `QueuePool limit of size 5 overflow 10 reached`
**케이스 12.** db.py에서 `pool_size=50, max_overflow=150, pool_timeout=10` 설정.

### `sqlite3.OperationalError: disk I/O error`
**케이스 13.** SQLite WAL 파일 손상. `_data/`를 `_trash/`로 격리 + alembic upgrade head + 사용자 재발급.

### `unknown_model`
upstream_map 또는 routes/models.py의 served_model_names 옛 이름. grep + sed로 일괄 치환.

### `Invalid args for response field`
chat.py의 `@router.post("/chat/completions")`에 `response_model=None` 추가 (이미 적용됨).

## 인증 흐름

1. Bearer 헤더 → `gem_live_<32hex>` 형식 검증
2. prefix 8자 추출 → DB의 api_keys.key_prefix lookup
3. 후보 hash 비교 (SHA256 + salt)
4. 매치 → AuthContext 주입 (user_id, plan)
5. revoked=True 또는 미매치 → 401

## quota 검사 (services/quota.py)

```python
1. RPM (slowapi 미들웨어, in-memory) — 60/min/key
2. concurrent — asyncio.Semaphore(quotas.concurrent_limit), default 5
3. daily — UsageLog 테이블에서 오늘자 토큰 SUM ≥ daily_token_limit
```

증액 (개별 사용자):
```sql
UPDATE quotas SET daily_token_limit=200000, rpm_limit=120, concurrent_limit=10
WHERE user_id='01K...';
```

## 스트리밍 동작

```python
1. client → POST /v1/chat/completions {"stream": true}
2. proxy.py → httpx.AsyncClient.stream()으로 vLLM 호출
3. SSE chunks (data: {...}\n\n) 그대로 패스스루
4. data: [DONE] 도착 시 종료
5. 스트림 끝나면 services/usage.py.record() async (블로킹 X)
```

## /metrics (Prometheus)

```python
# routes/health.py
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST
@router.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
```

기본 metrics: process_cpu, process_memory, python_gc, http_requests_total. 커스텀 metric 추가 시 `Counter`/`Histogram` import.

## 부하 테스트 시 Gateway 동작

50동접에서:
- p50 = 144ms (DB lookup ~10ms + vLLM ~120ms)
- p99 = 4.1s (vLLM 큐 적체로 인한 outliers)
- 처리량 = 45 req/s, 1441 tok/s

병목이 의심되면:
1. SQLAlchemy pool size (case 12)
2. asyncio.Semaphore concurrent (default 5)
3. vLLM 자체 큐
4. nvidia-smi GPU util

## 관련

- 책 Part III Ch.9 — Gateway 구현 상세
- SPEC-03 — Gateway API 설계
- `src/gateway/` 코드 + `tests/integration/test_e2e_gateway_vllm.py`
