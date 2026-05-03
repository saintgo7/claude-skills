---
name: api-route-consistency-pattern
description: 'Gateway 라우트 ↔ CLI/admin-cli 호출 ↔ 매뉴얼 ↔ 테스트 4-way 일관성 검증 패턴. 사용 시점 — "route mismatch", "404 silent", "admin-cli 빈 결과", "API contract drift", "라우트 변경", "스모크 테스트 admin", "API 문서 일관성", "fail-fast curl". gem-llm case 20 사고에서 추출 + curl --fail-with-body + smoke test.'
---

# api-route-consistency-pattern

Gateway 라우트, CLI/admin-cli 호출, 매뉴얼 인용, 테스트 — 이 4 표면이 시간이 지나면 어긋나기 시작한다. 라우트 한 곳만 바꾸면 다른 3곳이 outdated. 이 skill은 4-way 일관성을 강제하는 최소 패턴을 제공한다 — fail-fast curl, route extraction + diff, smoke test, PR 체크리스트. gem-llm case 20 (admin-cli list-keys가 존재하지 않는 라우트를 호출했는데 4xx silent로 빈 결과만 보였던 사고) 사후 분석에서 추출했다.

## 1. 사용 시점

- "admin-cli가 빈 결과를 리턴한다 (silent fail)"
- "라우트 변경했더니 매뉴얼/CLI/테스트가 outdated"
- "404인데 curl이 0 exit code"
- "스모크 테스트로 admin 명령 전체를 매 push마다 검증"
- "API contract drift 방지"
- "신규 엔드포인트 추가 시 매뉴얼/테스트 동시 갱신 강제"

## 2. 4-way 일관성

라우트 한 줄은 4 표면에 동시에 존재한다.

```
[1] FastAPI 라우터    →  /admin/keys?user_id=
[2] CLI 호출 (curl)   →  GET /admin/keys?user_id=$id   ← 일치해야 함
[3] 매뉴얼 §X.Y.Z     →  "GET /admin/keys?user_id="    ← 일치해야 함
[4] 테스트            →  client.get("/admin/keys?user_id=...")
```

라우트 변경 시 4 표면 모두 한 PR에서 동기화. atomic commit이 contract drift의 유일한 방어.

## 3. fail-fast curl 패턴

`-s` 만 쓰면 4xx/5xx에서도 exit 0이라 jq 파이프가 silent로 빈 결과를 흘린다. 4-way 불일치가 silent로 묻히는 주된 원인.

```bash
api() {
  local method="$1" path="$2" data="$3"
  curl --fail-with-body -sS \
       -X "$method" \
       -H "Authorization: Bearer ${ADMIN_TOKEN}" \
       -H "Content-Type: application/json" \
       ${data:+-d "$data"} \
       "${API_BASE}${path}"
}
```

핵심: `--fail-with-body` (curl 7.76+):
- 4xx/5xx → exit code 22 + stderr에 응답 본문
- jq에 빈 결과 silent pipe 차단
- `-sS`: progress는 숨기되 에러는 stderr로

`set -euo pipefail` + `set -o pipefail` 같이 쓰면 파이프 중간 실패도 cascade.

## 4. 라우트 추출 + 비교

**[1] FastAPI 라우터 추출:**

```python
# scripts/extract-fastapi-routes.py
from fastapi import FastAPI
import importlib

app = importlib.import_module("gateway.main").app
routes = [(r.methods, r.path) for r in app.routes if hasattr(r, "path")]
for methods, path in sorted(routes):
    for m in sorted(methods):
        print(f"{m} {path}")
```

**[2] CLI/admin-cli 호출 추출:**

```bash
# scripts/extract-cli-routes.sh
grep -hE "(GET|POST|PUT|DELETE|PATCH)\s+/[^\"]*" admin-cli.sh \
  | sed -E 's/^.*(GET|POST|PUT|DELETE|PATCH)\s+(\/[^"]*).*$/\1 \2/' \
  | sort -u
```

**[3] 매뉴얼 인용 추출:**

```bash
grep -hoE "(GET|POST|PUT|DELETE|PATCH)\s+/[a-zA-Z0-9_/{}-]*" docs/manual-*/chapters/*.md \
  | sort -u
```

**[4] 비교 (set diff):**

```bash
diff <(scripts/extract-fastapi-routes.py) <(scripts/extract-cli-routes.sh)
diff <(scripts/extract-fastapi-routes.py) <(scripts/extract-manual-routes.sh)
```

`<()` process substitution으로 임시 파일 없이 3-way set diff. 차이가 있으면 CI fail.

## 5. smoke test (CI 통합)

contract test (각 라우트 unit)는 모킹된 라우트만 검증한다. mock != real. 실제 admin-cli 명령이 진짜 gateway에 200 OK를 받는지 매 push마다 검증해야 한다.

```python
# tests/smoke/test_admin_routes.py
import pytest
import subprocess

ADMIN_COMMANDS = [
    ["list-users"],
    ["list-users", "--plan", "free"],
    ["list-keys"],
    ["list-keys", "--user", "1"],
    ["bulk-users", "tests/load/users-3.csv"],
]

@pytest.mark.parametrize("cmd", ADMIN_COMMANDS)
def test_admin_cli_smoke(cmd):
    """모든 admin-cli 명령이 200 OK인지 확인."""
    result = subprocess.run(
        ["bash", "scripts/admin-cli.sh"] + cmd,
        capture_output=True, text=True, timeout=10,
    )
    assert result.returncode == 0, f"{cmd} failed: {result.stderr}"
```

CI에서 매 push 마다 실행. 실제 gateway 부팅 → admin-cli 실행 → exit 0 강제. `--fail-with-body`와 묶이면 4xx도 즉시 잡힌다.

## 6. 라우트 변경 시 PR 체크리스트

PR template에 다음 체크리스트를 박아두면 4-way 동기화 누락이 review에서 catch.

```markdown
## API 라우트 변경 PR 체크리스트

- [ ] gateway/routes/*.py 변경
- [ ] CLI/admin-cli.sh 호출 동기화
- [ ] 매뉴얼 §X.Y.Z 인용 갱신
- [ ] tests/test_routes.py contract 테스트 추가/수정
- [ ] tests/smoke/test_admin_routes.py에 새 명령 등록
- [ ] CHANGELOG.md에 라우트 변경 기록
```

## 7. silent 4xx 방지

각 클라이언트마다 4xx fail-fast 강제 옵션이 다르다.

bash:
```bash
curl --fail-with-body  # 4xx → exit 22
```

Python httpx:
```python
response.raise_for_status()  # 4xx → exception
```

Python requests:
```python
response.raise_for_status()
```

JS fetch:
```js
if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
```

Go net/http:
```go
if resp.StatusCode >= 400 { return fmt.Errorf("status %d", resp.StatusCode) }
```

CLI wrapper에서 한 번만 박아두면 모든 호출이 자동 fail-fast.

## 8. 흔한 실수

| 증상 | 원인 | 해결 |
|---|---|---|
| admin-cli 빈 결과 | 4xx silent | `--fail-with-body` |
| 매뉴얼 outdated | 라우트만 변경 | atomic PR (4-way) |
| 테스트 모킹된 라우트 | mock != real | smoke test |
| curl 옵션 부족 | `-s` 만 | `-sS --fail-with-body` |
| jq 빈 입력 silent | curl가 빈 출력 | `set -o pipefail` |
| 라우트 변경했는데 CI green | smoke test 없음 | smoke test 도입 |

## 9. CI 통합 (GitHub Actions)

```yaml
- name: Route consistency check
  run: |
    python3 scripts/extract-fastapi-routes.py > /tmp/fastapi.txt
    bash scripts/extract-cli-routes.sh > /tmp/cli.txt
    bash scripts/extract-manual-routes.sh > /tmp/manual.txt
    diff /tmp/fastapi.txt /tmp/cli.txt && diff /tmp/fastapi.txt /tmp/manual.txt \
      && echo "OK: 3-way consistent" \
      || (echo "FAIL: route mismatch"; exit 1)

- name: Admin smoke
  run: |
    pytest tests/smoke/test_admin_routes.py -v
```

`-v`로 어느 명령이 실패했는지 즉시 보이게.

## 10. 검증된 사례 (gem-llm case 20)

- admin-cli `list-keys` 명령이 존재하지 않는 라우트를 호출 (gateway에서 라우트 rename 후 CLI 미동기화)
- `curl -s`만 써서 4xx가 silent로 묻힘 — 사용자에게는 빈 JSON 배열로 보였다
- long-running 모니터링 후에야 발견 — 회수된 키가 list에 안 보여서 의심
- 4-way 동기화 (gateway + admin-cli + manual + test) + `--fail-with-body` + smoke test 도입
- 이후 라우트 회귀 0건

## 11. 관련 skill

- `bash-cli-best-practices` — fail-fast bash 패턴 (set -euo pipefail, --fail-with-body)
- `pytest-fastapi-pattern` — contract 테스트 (라우트 unit 검증)
- `cicd-github-actions-pattern` — CI 워크플로 통합
- `quota-rate-limit-pattern` — 라우트 변경 시 rate limit 키 영향
- `gem-llm-admin-cli` — admin-cli.sh 실제 사례
