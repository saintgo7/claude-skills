---
name: multi-llm-routing-pattern
description: '여러 LLM 백엔드(vLLM, OpenAI, TGI 등)를 단일 게이트웨이에서 라우팅하는 검증된 패턴. 사용 시점 — "모델 라우팅", "upstream_map", "fallback 모델", "weighted routing", "사용자별 모델", "플랜별 LLM", "모델 ID 매핑". 5 패턴 (정적 매핑, weighted, fallback, 사용자/플랜별, A/B test) + GEM-LLM 검증.'
---

# multi-llm-routing-pattern

여러 LLM 백엔드를 *단일 OpenAI 호환 게이트웨이* 뒤에 두고 클라이언트 요청의 `model` 파라미터(또는 사용자/플랜)로 라우팅하는 패턴. GEM-LLM Gateway 가 `qwen2.5-coder-32b → :8001`, `qwen3-coder-30b → :8002` 정적 매핑으로 28일 + 100 동접 부하를 통과한 사례를 일반화했다. 정적 매핑에서 시작해 weighted / fallback / 사용자별 / A/B canary 까지 단계적으로 확장 가능.

## 1. 사용 시점

- "vLLM 모델을 2개 이상 띄웠다, 어떻게 한 endpoint 로 라우팅?"
- `upstream_map` 같은 모델 ID → URL 매핑 설계
- "모델 한 대가 죽으면 다른 모델로 fallback 하고 싶다"
- "free 사용자는 작은 모델, pro 는 큰 모델"
- A/B canary (5% 트래픽만 새 모델로)
- 두 vLLM instance 에 weighted load balancing
- 외부 provider (OpenAI, Anthropic) 와 자체 vLLM 혼합

라우팅이 *한 모델 = 한 URL* 인 prototype 에는 과한 패턴. 모델 ≥ 2 개거나 fallback / 플랜별 분기가 필요하면 이 패턴.

## 2. 5 라우팅 패턴

### (1) 정적 매핑 (가장 흔함, GEM-LLM 사례)

```python
upstream_map = {
    "qwen2.5-coder-32b": "http://localhost:8001",
    "qwen3-coder-30b":   "http://localhost:8002",
}
```

- key = OpenAI API 의 `model` 파라미터 그대로
- value = 백엔드 URL (`/v1/chat/completions` 가 붙는 base)
- 단순, 디버그 쉬움, GEM-LLM 1차 운영의 기본형

### (2) Weighted routing (load balancing)

```python
import random

upstream_map = {
    "qwen2.5-coder-32b": [
        ("http://vllm-1:8001", 0.7),
        ("http://vllm-2:8001", 0.3),
    ],
}

def pick(model: str) -> str:
    candidates, weights = zip(*upstream_map[model])
    return random.choices(candidates, weights=weights, k=1)[0]
```

- 두 vLLM instance 에 7:3 분산 (GPU 1 trafico 가 2 보다 큰 경우)
- 사용자 sticky 가 필요 없을 때만 — 같은 user 가 매 요청 다른 백엔드 → 캐시 miss

### (3) Fallback chain

```python
fallback_chain = {
    "qwen3-coder-30b": [
        "http://localhost:8002",   # primary
        "http://localhost:8003",   # fallback 1 (warm spare)
        "openai-gpt-4-turbo",      # fallback 2 (외부 provider)
    ],
}
```

흐름: primary 502/timeout → 다음 url 시도. 4xx (400/401/422) 는 fallback 안 함 (클라이언트 잘못).

### (4) 사용자/플랜별 라우팅

```python
def route(model: str, user_plan: str) -> str:
    if user_plan == "free":
        return "http://localhost:8001"          # 32B (작은 모델)
    elif user_plan == "pro":
        return "http://localhost:8002"          # 30B v3
    elif user_plan == "enterprise":
        return "http://gpt-4-proxy:9000"        # 외부 best
    raise ValueError(f"unknown_plan: {user_plan}")
```

- DB 의 `users.plan` 컬럼 → 라우팅 결정
- `model` 파라미터 무시 또는 화이트리스트 강제

### (5) A/B test (canary)

```python
def route(user_id: str) -> str:
    bucket = hash(user_id) % 100
    if bucket < 5:                              # 5% canary
        return "http://vllm-new:8001"           # 신모델
    return "http://vllm-stable:8001"            # 기존
```

- `hash(user_id)` 로 sticky (같은 사용자 항상 같은 bucket)
- canary 비율 *5% 권장* — 50% 는 위험 (롤백 비용 큼)
- prom metric 으로 canary 응답 시간/에러율 비교 → 안전 시 비율 증가

## 3. 구현 — FastAPI Gateway

```python
# config.py
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    vllm_32b_url: str = "http://localhost:8001"
    vllm_30b_url: str = "http://localhost:8002"

    @property
    def upstream_map(self) -> dict[str, str]:
        return {
            "qwen2.5-coder-32b": self.vllm_32b_url,
            "qwen3-coder-30b":   self.vllm_30b_url,
        }
```

```python
# proxy.py
def resolve_upstream(model: str) -> str:
    settings = get_settings()
    if model not in settings.upstream_map:
        raise HTTPException(400, f"unknown_model: {model}")
    return settings.upstream_map[model]
```

라우팅 로직은 **proxy 진입 직후 한 곳**. 인증/quota 통과 → `resolve_upstream(payload.model)` → httpx 로 forward.

## 4. 새 모델 추가 워크플로

1. vLLM 새 모델 띄움 — 새 포트 (예: `8003`)
2. `.env` 또는 `config.py` 에 URL 추가 — `vllm_70b_url=http://localhost:8003`
3. `upstream_map` 에 모델 ID → URL 매핑 한 줄
4. `routes/models.py` 의 `served_model_names` 에도 추가 (`/v1/models` 응답)
5. Gateway 재시작

**원자성** — 위 1~5 가 atomic 이어야 함. 3 만 추가하고 4 누락 → `/v1/models` 에서는 안 보이지만 chat 은 됨 (UI 혼란).

## 5. fallback 구현 (proxy.py)

```python
import httpx

class UpstreamError(Exception): ...

async def chat_with_fallback(payload: dict, model: str) -> dict:
    chain = fallback_chain.get(model, [resolve_upstream(model)])
    last_err: Exception | None = None
    for url in chain:
        try:
            return await call_upstream(url, payload)
        except httpx.HTTPStatusError as e:
            if e.response.status_code < 500:
                raise            # 4xx 는 즉시 반환 (클라이언트 잘못)
            last_err = e
            continue             # 5xx 는 fallback
        except (httpx.RequestError, httpx.TimeoutException) as e:
            last_err = e
            continue             # network/timeout → fallback
    raise UpstreamError(f"all_fallbacks_exhausted: {last_err}")
```

원칙:
- **4xx 는 fallback 안 함** — 400/401/422 는 클라이언트 입력이 잘못된 것. fallback 해도 같은 결과.
- **5xx 와 network error 만 fallback** — 502/503/timeout/connection refused.
- **마지막 에러 보존** — 모두 실패하면 마지막 원인 메시지 노출 (디버그용).

## 6. metrics 통합

```python
from prometheus_client import Counter

gateway_routing_decisions_total = Counter(
    "gateway_routing_decisions_total",
    "Routing decisions by model and result",
    ["model", "decision"],   # decision: primary | fallback_1 | fallback_2 | exhausted
)

# 사용
gateway_routing_decisions_total.labels(model=model, decision="primary").inc()
```

라벨 cardinality 주의 — `user_id` 를 라벨에 넣으면 폭발. `model` + `decision` 만 (수백 라벨 이내).

## 7. 흔한 함정

1. **모델 ID typo** — `gem-31b` vs `qwen2.5-coder-32b` (case 11 마이그레이션). `served_model_names` 와 `upstream_map` key 가 *완전히 동일* 해야 함. 테스트로 강제: `assert set(served_model_names) == set(upstream_map.keys())`.
2. **fallback chain 무한 루프** — 모든 url 이 unreachable 인데 retry 하면 client 가 timeout 까지 대기. chain 길이 ≤ 3 + 각 호출 timeout 30s.
3. **weighted routing 의 hash 일관성** — `random.choices` 는 매 요청 새로 → sticky session 깨짐. 사용자 sticky 가 필요하면 `hash(user_id) % total_weight` 로 결정.
4. **A/B canary 비율 폭주** — 5% 권장. 50% 는 롤백 시 절반의 사용자 영향 → 위험. 단계적 5% → 10% → 25% → 100%.
5. **new model 등록 시 served_model_names 누락** — `/v1/models` 가 거짓말. 4번 워크플로 atomic 으로 강제.
6. **`model=null` 또는 빈 문자열** — pydantic 으로 `model: str = Field(min_length=1)`. 안 그러면 `KeyError` 500 응답.
7. **upstream URL trailing slash 불일치** — `http://x:8001` vs `http://x:8001/` → httpx 에서 path 합칠 때 `//v1/...` 발생. config 단계에서 `.rstrip("/")` 표준화.

## 8. GEM-LLM 검증

- **정적 매핑 5+ 라운드** — 28일 운영 + 100 동접 부하 (`gem-llm-load-test`) 통과
- **50:50 라우팅** — 두 모델 동시 호출에서 응답 시간 분포 균등
- **신규 모델 추가 atomic commit** — `config.py` (URL) + `routes/models.py` (served_model_names) 를 한 commit 으로 (case 11 typo 사고 이후 정책)
- **fallback 미적용 (의도)** — 30B 한 대가 죽으면 알람 → 수동 복구. 자동 fallback 은 *원인 은폐* 위험이 커서 GEM-LLM 은 미채택. 외부 SaaS 게이트웨이는 fallback 권장.

## 9. 관련 skill

- `fastapi-gateway-pattern` — 본 패턴이 들어가는 5계층 게이트웨이 (라우팅 = proxy 계층)
- `prometheus-fastapi-metrics` — `gateway_routing_decisions_total` 같은 라우팅 메트릭
- `vllm-bootstrap` — 백엔드 모델을 새로 띄울 때 (4번 워크플로 step 1)
- `quota-rate-limit-pattern` — 플랜별 라우팅 시 RPM/daily 한도와 짝
- `blue-green-deployment-pattern` — A/B canary 의 cutover 전략 (점진 전환)
