---
name: env-isolation-pattern
description: '운영 환경변수가 테스트/마이그레이션 프로세스에 누설되어 운영 DB가 손상되는 사고 회피. 사용 시점 — "테스트가 운영 DB 건드림", "env 격리", "setdefault no-op", "GATEWAY_DB_URL 누설", "destructive test", "CI prod env leak". explicit unset + unconditional override + .env export 후 격리 3 패턴.'
---

# env-isolation-pattern

운영 환경변수가 자식 프로세스(pytest / alembic / 마이그레이션 스크립트)에 그대로 상속되어 **운영 DB를 테스트 코드가 wipe** 하는 사고를 막는 가이드. case 18 사고를 일반화 — 특정 변수명(GATEWAY_*) 이 아니라 "부모 → 자식 환경 누설" 자체를 다룬다.

이 skill 의 핵심 명제 — `os.environ.setdefault(...)` 는 **방어가 아니다**. 부모가 이미 export 했다면 setdefault 는 no-op 이고, 테스트 코드는 운영 DB 에 그대로 연결된다.

## 1. 사용 시점

- "테스트 돌렸더니 운영 DB 가 비었음"
- "alembic upgrade 가 prod 에 적용됨"
- conftest 의 `os.environ.setdefault(...)` 가 안 먹힘
- supervisor / wrapper 스크립트가 `set -a; source .env; set +a` 로 export
- CI 파이프라인에서 secret 이 통째로 child 에 노출
- "왜 `:memory:` SQLite 가 아니라 prod URL 로 붙지?"
- destructive test (drop_all, truncate, factory reset) 가 prod 와 한 끗 차이

## 2. 사고 시나리오 (case 18 사례)

```
supervisor.sh
  set -a; source .env; set +a   ← GATEWAY_DB_URL=prod.db export
  └── pytest
        └── conftest.py
              os.environ.setdefault("GATEWAY_DB_URL", ":memory:")
              # setdefault 는 이미 설정된 값을 안 덮음 → :memory: 적용 안 됨
              Base.metadata.drop_all(engine)  # ← 운영 DB wipe
```

원인은 **두 군데** — supervisor 가 .env 를 그대로 export, conftest 가 약한 방어(setdefault)만 사용. 둘 중 하나만 고쳐도 사고는 안 났다.

## 3. 약한 방어 vs 강한 방어

| 방어 | 코드 | 강도 | 비고 |
|---|---|---|---|
| `os.environ.setdefault(K, V)` | conftest.py | 약함 | 이미 설정된 값 무시 (case 18 원인) |
| `os.environ[K] = V` | conftest.py | 강함 | 무조건 덮음 |
| `del os.environ[K]` | conftest.py | 강함 | 부모 값 제거 후 재설정 |
| `env -u K` 로 child 호출 | shell wrapper | 강함 | 자식 환경에서 unset |
| Docker `-e K=V` | container | 가장 강함 | 외부 격리, .env 누설 원천 차단 |
| separate `.env.test` | 운영 스크립트 | 강함 | export 자체가 다른 파일 |

규칙 — 가능하면 **두 단계 이상**. shell wrapper 에서 unset + conftest 에서 override 면 한쪽이 깨져도 다른 쪽이 막는다.

## 4. 3가지 패턴

### 패턴 A: explicit unset (운영 → 테스트)

운영 wrapper 가 export 하는 prod 변수를 테스트 진입 직전에 명시적으로 제거.

```bash
env -u GATEWAY_DB_URL \
    -u GATEWAY_ADMIN_KEY \
    -u GATEWAY_API_KEY_SALT \
    -u DATABASE_URL \
    pytest tests/integration
```

장점 — Python 코드 수정 불필요, 운영 스크립트 수정 불필요. 단점 — 변수가 늘어날 때마다 unset 목록 갱신.

### 패턴 B: unconditional override (conftest)

conftest 최상단 (import 전) 에서 무조건 덮기.

```python
# tests/conftest.py — 최상단, 다른 import 보다 먼저
import os

# 모든 prod prefix 변수 제거
for k in list(os.environ):
    if k.startswith(("GATEWAY_", "ADMIN_", "DATABASE_URL")):
        del os.environ[k]

# 테스트용 값 명시적 설정
os.environ["GATEWAY_DB_URL"] = "sqlite+aiosqlite:///:memory:"
os.environ["GATEWAY_ADMIN_KEY"] = "test_admin_key"
os.environ["GATEWAY_API_KEY_SALT"] = "test_salt"
```

핵심 — `setdefault` 가 아니라 직접 할당. fixture 가 아니라 **모듈 import 시점**에 실행 (앱 코드가 환경변수를 읽기 전).

### 패턴 C: container isolation (CI/CD)

GitHub Actions / GitLab CI / Docker — 환경변수를 **명시적으로 declare** 하고 secret 만 inject.

```yaml
# .github/workflows/test.yml
env:
  GATEWAY_DB_URL: sqlite+aiosqlite:///:memory:
  GATEWAY_ADMIN_KEY: test
  # 다른 prod 환경변수는 secrets 에서만 가져옴
  # → declare 안 한 변수는 자동으로 누설 안 됨
```

장점 — 자동 격리. 단점 — 로컬 개발자 머신에서 `source .env && pytest` 하면 여전히 위험. 패턴 B 와 같이 써야 함.

## 5. 검증 방법

테스트 환경에서 prod env 가 누설되었는지 확인.

```bash
# 1. 셸 레벨 — pytest 실행 직전
env | grep -E "^(GATEWAY_|ADMIN_|DATABASE_URL)" 
# 비어있어야 안전

# 2. Python 레벨 — conftest 실행 직후
python3 -c "
import os
leaked = [k for k in os.environ
          if k.startswith(('GATEWAY_', 'ADMIN_'))
          and 'test' not in os.environ[k].lower()
          and ':memory:' not in os.environ[k]]
if leaked:
    print(f'leaked: {leaked}')
    raise SystemExit(1)
"
```

CI 에서는 이 검증 자체를 **테스트 첫 step** 으로 넣어 fail-fast.

## 6. .env 가 누설되는 흔한 경로

- `set -a; source .env; set +a` — 전체 export, supervisor 패턴
- `docker run --env-file .env` — 모든 변수 컨테이너 진입
- systemd `EnvironmentFile=` — service 단위 전체 상속
- VSCode dev container `.env` auto-load — IDE 자체가 주입
- supervisor / wrapper 스크립트가 sub-command 로 .env 주입
- direnv `.envrc` — 디렉터리 진입 시 자동 export
- Jupyter / IPython 커널이 부모 셸 환경 그대로 상속

## 7. 흔한 함정

- **`setdefault` 사용** — 부모가 이미 설정한 값 무시 (case 18 원인). `setdefault` 는 "기본값 제공"이지 "강제 격리"가 아니다.
- **conftest fixture 가 test 시작 후 환경변수 변경** — engine 은 import 시점에 이미 prod 연결로 생성됨. 환경변수 override 는 fixture 가 아니라 **모듈 top-level**.
- **`pytest -p no:cacheprovider`** 등으로 plugin 격리해도 환경변수는 누설.
- **subprocess 에 `env=os.environ.copy()`** — 전체 복사, 격리 안 됨. 필요한 키만 골라서 dict 구성.
- **Jupyter / IPython 커널** — 부모 셸 환경 그대로 상속. 노트북에서 destructive 코드 실행 시 동일 사고.
- **alembic / 마이그레이션 스크립트** — pytest 와 같은 함정. `alembic upgrade head` 가 prod 에 적용되는 사고.
- **`.env.example` 과 `.env` 혼용** — 누군가 `.env` 에 prod URL 남겨두고 git ignore 만으로 안전하다고 착각.

## 8. 책임 분리

3 레이어 — 어느 한 레이어가 깨져도 나머지가 막아야 한다.

- **운영 스크립트 (supervisor / wrapper)** — 환경변수를 export 하는 책임. **테스트 명령에는 unset 추가**.
- **테스트 wrapper (run-tests.sh)** — `env -u` 로 prod 변수 명시적 제거.
- **conftest.py** — `setdefault` 대신 **unconditional override**. 모듈 top-level 에서 실행.
- **앱 코드 (settings.py)** — 환경변수가 prod-like 하면 **fail-fast**. `if "prod" in url and pytest_running: raise`.

## 9. 백업이 마지막 방어선

case 18 은 백업이 사고 비용을 0 으로 만들었다 — `backup-db.sh` (case 13) 가 자동으로 보존했기에 즉시 복구 가능했다. **백업 + env 격리 = 이중 방어**.

env 격리만 믿지 말 것 — 누군가 `setdefault` 를 다시 PR 로 넣을 수도 있고, 새 환경변수 추가하면서 unset 목록 빠뜨릴 수도 있다. 백업이 없으면 한 번의 실수가 영구 손실이다.

관련 패턴은 [sqlite-wal-safe-ops](../sqlite-wal-safe-ops/) (백업 정책) 참조.

## 10. 일반화 매핑

case 18 의 `GATEWAY_*` 는 예시일 뿐. 다른 프로젝트에서는 prefix 만 갈아끼우면 된다.

| 프로젝트 유형 | prod prefix 예 | 격리 대상 |
|---|---|---|
| Django | `DJANGO_*`, `DATABASE_URL` | `DJANGO_SETTINGS_MODULE`, DB URL |
| Rails | `RAILS_ENV`, `DATABASE_URL` | env 자체를 test 로 강제 |
| Node.js | `NODE_ENV`, `DB_HOST`, `REDIS_URL` | NODE_ENV=test 강제 |
| Generic | `APP_*`, `PROD_*`, `*_DB_URL`, `*_API_KEY` | 모든 secret prefix |

규칙 — **secret 으로 다루는 prefix 전부**가 격리 대상. "이 변수는 안전하니 둬도 돼" 는 case 18 의 출발점이다.

## 11. 관련 skill

- [pytest-fastapi-pattern](../pytest-fastapi-pattern/) — 격리된 통합 테스트
- [sqlite-wal-safe-ops](../sqlite-wal-safe-ops/) — 백업 정책 (마지막 방어선)
- [bash-cli-best-practices](../bash-cli-best-practices/) — env 우선순위, set -a 함정
- [postgres-migration-from-sqlite](../postgres-migration-from-sqlite/) — alembic 마이그레이션 격리

## 12. 템플릿

- `templates/conftest-isolation.py.template` — conftest 최상단 격리 코드
- `templates/safe-test-runner.sh.template` — `env -u` wrapper

복사 후 `GATEWAY_*` prefix 만 자기 프로젝트에 맞게 교체.
