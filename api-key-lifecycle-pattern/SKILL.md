---
name: api-key-lifecycle-pattern
description: 'API key 발급/회수/검증 라이프사이클 + prefix lookup + hash 패턴. 사용 시점 — "api key 발급", "key revoke", "key prefix", "argon2 vs sha256", "key rotation", "raw key 1회 노출", "admin-cli". GEM-LLM에서 검증 (gem_live_<32hex>, prefix 8자, sha256+salt).'
---

# api-key-lifecycle-pattern

API key 의 *전체 라이프사이클* — 발급(issue) / 검증(verify) / 회수(revoke) / 회전(rotation) — 을 raw key 1회 노출 + prefix lookup + 해시 저장 3원칙으로 묶은 패턴. GEM-LLM Gateway 의 `admin-cli` (issue-key / list-keys / revoke-key / set-quota) 가 이 패턴으로 28일 운영 + 200 동접 부하를 통과했다. 일반 FastAPI / REST API 에 그대로 이식 가능.

## 1. 사용 시점

- "api key 발급 / 회수 / rotation" 설계
- "raw key 를 응답 어디까지 노출할지"
- "key prefix lookup" 인덱스 설계
- "argon2 vs sha256" 선택 (인덱스 비교 가능 여부)
- 평문/단순 hash 만 쓰던 prototype → production 강화
- `admin-cli` 같은 운영 도구를 새로 만들 때 명령 set 표준

라이프사이클이 *발급 → 영원* 인 prototype 에는 과한 패턴. *회수 / 감사 로그 / 멀티 디바이스* 가 필요하면 이 패턴.

## 2. 키 형식 권장

```
gem_live_a1b2c3d4e5f6...  ← 9자 prefix + 32 hex (총 41자)
└─┬───┘ └────┬─────────┘
  │         body: 16 bytes random → hex 32자
  service marker (live/test 환경 구분)
```

규칙:
- **prefix `<service>_<env>_`** — `gem_live_`, `sk_live_`, `gh_pat_` 등 (Stripe/OpenAI/GitHub 관행)
- **body 32 hex** — `secrets.token_hex(16)` (16 bytes = 128 bit 엔트로피)
- **검색용 prefix 8자** — body 의 앞 8자 (사용자 인지 + DB lookup 인덱스)
  - 예: `gem_live_a1b2c3d4...` 의 마지막 8자가 검색 키 X — body 첫 8자 `a1b2c3d4` 가 검색 키
  - 사용자에게는 마스킹된 형태로 표시: `gem_live_a1b2c3d4...****`

## 3. DB 스키마

```sql
CREATE TABLE api_keys (
  id          TEXT PRIMARY KEY,           -- ULID
  user_id     TEXT NOT NULL REFERENCES users(id),
  key_prefix  CHAR(8) NOT NULL,           -- 검색용 (body 첫 8자)
  key_hash    TEXT NOT NULL,              -- SHA256(salt + raw_key)
  name        TEXT,                       -- "laptop", "ci/cd" 등 사용자 라벨
  last_used   TIMESTAMP,
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  revoked     BOOLEAN NOT NULL DEFAULT FALSE,
  revoked_at  TIMESTAMP
);

CREATE INDEX idx_api_keys_prefix ON api_keys(key_prefix) WHERE NOT revoked;
CREATE INDEX idx_api_keys_user ON api_keys(user_id);
```

핵심:
- **`key_prefix` 인덱스 필수** — 매 요청마다 hash 만으로 lookup 하면 full scan
- **partial index `WHERE NOT revoked`** — 활성 키만 인덱스 (회수 키가 누적되면 효과)
- **revoked 컬럼 (DELETE 안 함)** — 감사 로그 + 회수 history 보존

## 4. 발급 (issue)

```python
import hashlib
import secrets
from datetime import datetime

import ulid

SALT = os.environ["API_KEY_SALT"]  # ← key 자체와 다른 secret


def issue_key(db, user_id: str, name: str | None = None) -> dict:
    body = secrets.token_hex(16)               # 32 hex chars
    raw = f"gem_live_{body}"
    prefix = body[:8]                          # 검색용
    hash_ = hashlib.sha256(f"{SALT}{raw}".encode()).hexdigest()
    key_id = str(ulid.new())

    db.execute(
        "INSERT INTO api_keys (id, user_id, key_prefix, key_hash, name) "
        "VALUES (?, ?, ?, ?, ?)",
        (key_id, user_id, prefix, hash_, name),
    )

    # ⚠️ raw 는 이 응답에만 — 이후 어디서도 복원 불가
    return {"id": key_id, "raw_key": raw, "prefix": prefix, "name": name}
```

원칙:
- raw key 는 **응답에 1회만** — DB 에는 hash 만 저장 → 이후엔 prefix 만 노출
- 사용자에게 *지금 안 받으면 다시는 못 본다* 경고 (Stripe/OpenAI 와 동일 UX)

## 5. 검증 (auth middleware)

```python
from fastapi import Header, HTTPException


def verify(authorization: str = Header(...)) -> str:
    if not authorization.startswith("Bearer "):
        raise HTTPException(401, "missing_bearer")
    raw = authorization[7:].strip()

    if not raw.startswith("gem_live_") or len(raw) != 41:
        raise HTTPException(401, "invalid_format")

    body = raw[len("gem_live_"):]
    prefix = body[:8]
    hash_ = hashlib.sha256(f"{SALT}{raw}".encode()).hexdigest()

    row = db.execute(
        "SELECT user_id FROM api_keys "
        "WHERE key_prefix = ? AND key_hash = ? AND NOT revoked",
        (prefix, hash_),
    ).fetchone()

    if not row:
        raise HTTPException(401, "invalid_or_revoked")

    # 비동기로 last_used 갱신 (요청 본문 막지 말 것)
    db.execute("UPDATE api_keys SET last_used=? WHERE key_prefix=? AND key_hash=?",
               (datetime.utcnow(), prefix, hash_))
    return row.user_id
```

검증 흐름:
1. 형식 체크 → `invalid_format` 401
2. prefix lookup (인덱스 사용) → 후보 1~5건
3. hash 비교 → 일치 + `NOT revoked` → 통과
4. `last_used` 갱신 (감사 + 미사용 키 정리용)

## 6. 회수 (revoke)

```sql
UPDATE api_keys
SET revoked    = TRUE,
    revoked_at = CURRENT_TIMESTAMP
WHERE id = ?;
-- DELETE 절대 X (감사 로그 + 사후 forensic)
```

```python
def revoke_key(db, key_id: str, by_user_id: str) -> None:
    db.execute(
        "UPDATE api_keys SET revoked=TRUE, revoked_at=? WHERE id=?",
        (datetime.utcnow(), key_id),
    )
    audit_log(action="revoke", actor=by_user_id, target=key_id)
```

회수 후:
- 다음 요청부터 즉시 401 (캐시 없음)
- 사용자 UX 가 중요하면 *grace period* 24h: `revoked_at + 24h` 까지 warning header 만 → 그 후 차단

## 7. 키 로테이션 권장

- **90일 마다 자동 알림** (last_used 또는 created_at 기준)
- **새 키 발급 후 기존 키 revoke** — 동시 사용 안 함 (혼란 + 감사 추적 어려움)
- 자동화: nightly cron 으로 `created_at < now - 90d AND NOT revoked` 사용자에게 메일/Slack

```sql
SELECT user_id, id, key_prefix, created_at
FROM api_keys
WHERE NOT revoked AND created_at < CURRENT_TIMESTAMP - INTERVAL '90 days';
```

## 8. 보안 원칙 (5가지)

1. **raw key 는 발급 시 1회만 응답** — 이후 어떤 endpoint 도 raw 반환 X (prefix + name + last_used 만)
2. **로그에 raw key 절대 X** — middleware logger 는 `prefix` 8자만 기록 (FastAPI 의 `request.headers["authorization"]` 통째로 로깅하면 사고)
3. **salt 는 별도 secret** — `.env` 또는 secrets manager. raw key 와 *다른 변수*. salt 유출 = 모든 hash 가 rainbow table 으로 풀림
4. **DELETE 대신 `revoked=TRUE`** — 감사 로그 보존, "이 키가 언제 누구에게 발급됐는가" 추적 가능
5. **timing attack 회피** — `hashlib.sha256` 은 deterministic 이라 hash 비교에 `hmac.compare_digest()` 또는 DB 의 `=` 비교(상수시간 아님)로 충분 — DB lookup 시간이 hash 시간보다 훨씬 큼

## 9. 흔한 함정 (5가지)

1. **raw key 를 매 요청마다 응답에 포함** — `list-keys` 응답에 raw 가 들어가면 사고. prefix 8자 + name 만.
2. **prefix 인덱스 누락** → 매 요청 full table scan. 키 1만개 넘어가면 100ms+ latency.
3. **argon2/bcrypt 사용 시 인덱스 비교 안 됨** — argon2 는 매번 다른 salt 생성 → DB `WHERE hash=?` 못 함. *반드시* prefix lookup → argon2 verify 2단계. SHA256+global-salt 가 단순 + 인덱스 가능 (저엔트로피 비밀번호 X, 128-bit 랜덤 키이므로 SHA256 충분).
4. **salt 를 운영 중 변경** → 모든 기존 키 무효화. salt rotation 하려면 *모든 사용자 재발급* 캠페인 필요. 처음부터 강한 salt 한 번만.
5. **revoke 후 grace period 0** — CI/CD 가 도는 와중에 즉시 차단하면 deploy 실패. `revoked_at` 부터 24h 동안 warning header (`X-API-Key-Revoked: please-rotate`) 만 → 그 후 차단.

## 10. admin-cli 패턴 (GEM-LLM 검증)

운영 도구가 갖춰야 할 4 명령 set:

```bash
admin-cli issue-key <user_id> [name]    # raw_key 1회 노출
admin-cli list-keys <user_id>           # prefix 8자만
admin-cli revoke-key <key_id>           # revoked=TRUE
admin-cli set-quota <user_id> --rpm=N --daily=M  # quota 별개 테이블
```

설계 원칙:
- **issue 는 stdout 에 raw 단 한 번** — 사용자가 실수로 다시 호출해도 새 키만 나오지 *재현* X
- **list 는 절대 raw X** — JSON `{"id": "...", "prefix": "a1b2c3d4", "name": "...", "last_used": "..."}`
- **revoke 는 idempotent** — 이미 revoked 인 키 재호출해도 200
- **set-quota 는 별개** — `api_keys` 가 아니라 `quotas` 테이블 (키마다 한도 다른게 아니라 user 마다 한도)

## 11. 관련 skill

- `quota-rate-limit-pattern` — 발급된 키의 RPM/daily/concurrent 한도 (issue → quota 가 짝)
- `fastapi-gateway-pattern` — 본 패턴이 들어가는 5계층 게이트웨이 (auth 가 1계층)
- `gem-llm-admin-cli` — 본 패턴 GEM-LLM 특화 CLI 구현
- `bash-cli-best-practices` — admin-cli 같은 운영 bash CLI 설계
