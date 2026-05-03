---
name: api-contract-testing-pattern
description: 'FastAPI/REST API contract 테스트 검증된 패턴. 사용 시점 — "contract test", "API 명세 검증", "openapi snapshot", "schema validation", "response shape", "API drift 감지", "200 OK는 충분치 않음", "router 통합 테스트". pydantic 응답 스키마 + openapi.json 스냅샷 + 라우트 존재성 + smoke + happy/error path.'
---

# api-contract-testing-pattern

FastAPI/REST API의 *명세대로의 동작*을 검증하는 contract 테스트 패턴. smoke (라우트 존재 + 200 OK)만으로는 잡히지 않는 응답 schema drift, 누락된 필드, 잘못된 status code 같은 문제를 잡는다. gem-llm case 20 (admin-cli `list-keys` silent 4xx) 회귀 방지를 위해 도입한 17/17 smoke + contract 패턴을 일반화했다.

## 1. 사용 시점

contract test가 필요한 시점:

- 라우트 변경 시 — case 20 같은 path/method mismatch 회귀 방지
- 응답 schema 변경 시 — 필드 추가/삭제/타입 변화
- 새 endpoint 추가 시 — `app.include_router` 등록 누락 발견
- API 클라이언트 (CLI, frontend, SDK)가 의존하는 응답 형식 보장
- `openapi.json` drift 감지 — 의도치 않은 라우트 제거/추가
- error 응답이 RFC 7807 / 자체 표준을 따르는지 검증

smoke가 "살아 있는가" 라면 contract는 "spec대로 동작하는가" 다.

## 2. smoke ↔ contract ↔ integration 차이

| 종류 | 검증 | 시간 | 도구 |
|---|---|---|---|
| **smoke** | 라우트 존재 + 200 OK | <5초 | curl, pytest |
| **contract** | 응답 schema + happy/error path + status code | <30초 | pytest + pydantic |
| **integration** | 실제 DB/cache/외부 mock 통합 flow | <5분 | pytest + testcontainers |
| **e2e** | 외부 서비스 + 실제 사용자 시나리오 | <30분 | playwright, locust |

contract 테스트는 외부 의존성을 mocking 하거나 in-memory SQLite 같은 가벼운 fixture로 격리한다. CI 매 PR 마다 돌릴 수 있을 만큼 빠르게 유지하는 것이 핵심.

## 3. pydantic 응답 스키마 검증

```python
from datetime import datetime
from typing import Literal
from pydantic import BaseModel, ConfigDict
import httpx, pytest

class UserResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")  # drift 감지

    id: str
    username: str
    email: str
    plan: Literal["free", "pro", "enterprise"]
    created_at: datetime

@pytest.mark.contract
def test_get_user_contract(client, alice_key):
    r = client.get("/v1/me", headers={"Authorization": f"Bearer {alice_key}"})
    assert r.status_code == 200

    # schema 검증 — 필드 누락/타입 불일치/extra 추가 모두 잡힘
    user = UserResponse.model_validate(r.json())

    # 핵심 invariant
    assert user.username == "alice"
    assert "@" in user.email
```

`extra = "forbid"` 설정으로 새 필드 추가 시 자동 실패. 의도된 추가라면 schema 갱신 + reviewer 승인.

## 4. openapi.json snapshot

라우트/스키마 drift를 한 번에 잡는 가장 단순한 방법.

```python
# tests/contract/test_openapi_snapshot.py
import json, pytest
from pathlib import Path

SNAPSHOT_PATH = Path(__file__).parent / "openapi.snapshot.json"

def test_openapi_no_unintended_drift(client):
    current = client.get("/openapi.json").json()

    if not SNAPSHOT_PATH.exists():
        SNAPSHOT_PATH.write_text(json.dumps(current, indent=2, sort_keys=True))
        pytest.skip("Snapshot created, run again to verify")

    snapshot = json.loads(SNAPSHOT_PATH.read_text())

    current_paths = set(current["paths"].keys())
    snapshot_paths = set(snapshot["paths"].keys())

    removed = snapshot_paths - current_paths
    added = current_paths - snapshot_paths

    if removed:
        pytest.fail(f"Routes removed (breaking change): {removed}")

    if added:
        # 새 라우트 OK, 다만 PR description에 명시
        print(f"New routes (review required): {added}")
        # 자동으로 snapshot 갱신은 하지 않음 → reviewer가 명시적으로 갱신
```

snapshot 갱신은 항상 명시적으로 (`pytest --update-snapshot` 같은 별도 모드). silent 갱신은 drift 감지의 의미를 없앤다.

## 5. happy path + error path 표준

각 endpoint마다 최소 4 시나리오 (happy + 인증 없음 + 인증 잘못 + 권한/리소스 없음).

```python
class TestMeEndpointContract:
    def test_happy_path(self, client, alice_key):
        r = client.get("/v1/me", headers={"Authorization": f"Bearer {alice_key}"})
        assert r.status_code == 200
        UserResponse.model_validate(r.json())

    def test_no_auth(self, client):
        r = client.get("/v1/me")
        assert r.status_code == 401
        assert "detail" in r.json()

    def test_invalid_auth(self, client):
        r = client.get("/v1/me", headers={"Authorization": "Bearer invalid"})
        assert r.status_code == 401

    def test_revoked_key(self, client, revoked_key):
        r = client.get("/v1/me", headers={"Authorization": f"Bearer {revoked_key}"})
        assert r.status_code == 401
```

권한 분리가 있다면 `test_other_user_forbidden` (403), 리소스 미존재 시나리오 `test_not_found` (404) 도 추가.

## 6. 라우트 존재성 (parametrize)

```python
EXPECTED_ROUTES = [
    ("GET", "/healthz"),
    ("GET", "/v1/me"),
    ("GET", "/v1/me/keys"),
    ("GET", "/v1/me/quota"),
    ("POST", "/v1/chat/completions"),
    ("GET", "/admin/users"),
    ("POST", "/admin/users"),
    ("GET", "/admin/keys"),
    ("DELETE", "/admin/keys/{key_id}"),
]

@pytest.mark.parametrize("method,path", EXPECTED_ROUTES)
def test_route_exists(method, path, app):
    routes = [(r.methods, r.path) for r in app.routes if hasattr(r, "methods")]
    found = any(method in m and path == p for m, p in routes)
    assert found, f"Route {method} {path} not registered"
```

case 20 회귀 방지: 라우트 변경 (rename, remove) 시 즉시 실패. CI 1초 안에 결과.

## 7. 응답 헤더 검증

```python
def test_security_headers(client):
    r = client.get("/healthz")
    assert r.headers.get("X-Content-Type-Options") == "nosniff"
    assert "Access-Control-Allow-Origin" in r.headers  # CORS

def test_rate_limit_headers(client, alice_key):
    r = client.get("/v1/me", headers={"Authorization": f"Bearer {alice_key}"})
    # slowapi가 노출하는 표준 헤더
    assert "X-RateLimit-Limit" in r.headers
    assert "X-RateLimit-Remaining" in r.headers
```

## 8. status code 우선순위

| 상황 | 적절한 코드 |
|---|---|
| 인증 없음 / 토큰 없음 | 401 |
| 인증은 있지만 권한 없음 | 403 |
| 리소스 없음 | 404 |
| 입력 형식 오류 (JSON parse, 타입) | 422 (FastAPI 기본) |
| 입력 의미 오류 (business rule) | 400 |
| rate limit 초과 | 429 |
| 서버 오류 (예외) | 500 |
| upstream / 외부 의존성 오류 | 502 / 503 |
| 정상 (조회) | 200 |
| 정상 (생성) | 201 |
| 정상 (응답 본문 없음) | 204 |

contract test로 *각* 상황의 정확한 코드를 검증한다. "인증 없음"이 500을 반환하면 클라이언트가 retry 폭주를 일으킨다.

## 9. CI 통합

```yaml
- name: Contract tests
  run: |
    pytest tests/contract/ -m contract --tb=short
  # snapshot diff는 PR 리뷰 단계에서 reviewer 승인 필요
```

snapshot이 변경된 PR:

- CI 단계에서 자동 검출 (test fail or print)
- "openapi.json 스냅샷 변경됨" PR 댓글
- reviewer가 의도된 변경인지 확인 후 `--update-snapshot` 모드로 갱신 → merge

snapshot 파일은 **반드시 commit** 한다. `.gitignore` 금지.

## 10. 흔한 함정

| 증상 | 원인 | 해결 |
|---|---|---|
| 200 OK인데 응답 비어있음 | schema 검증 X | `pydantic.model_validate` 추가 |
| 라우트 변경이 silent하게 통과 | snapshot/존재성 테스트 없음 | section 4 + 6 |
| extra 필드 누적 (drift) | 스키마 `forbid` 미설정 | `model_config = ConfigDict(extra="forbid")` |
| status code 일관성 X | 표준 없음 | section 8 표 따르기 |
| FastAPI 422 vs 400 혼동 | 검증 위치 차이 | input format = 422, semantic = 400 |
| snapshot이 매번 변경 | 비결정적 필드 (timestamp) | snapshot 비교 시 ignore key 화이트리스트 |
| contract가 너무 느려짐 | DB/외부 호출 mock 안함 | in-memory SQLite + respx |

## 11. 관련 skill

- `pytest-fastapi-pattern` — fixture, ASGITransport, lifespan
- `api-route-consistency-pattern` — 4-way drift (gateway ↔ CLI ↔ manual ↔ test)
- `production-postmortem-pattern` — case 20 같은 사고에서 contract test로 회귀 방지
- `cicd-github-actions-pattern` — CI에서 contract 단계 분리
