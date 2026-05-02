---
name: postgres-migration-from-sqlite
description: 'SQLite → PostgreSQL 마이그레이션 (Alembic 기반 FastAPI/SQLAlchemy 프로젝트). 사용 시점 — "sqlite write lock", "100동접 이상", "database is locked", "postgres migration", "production scaling", "sqlite 한계", "alembic postgres". SQLAlchemy DSN 변경 + Alembic re-init + 데이터 dump/restore + 자동 SERIAL 시퀀스 회복 + 검증 7단계.'
---

# postgres-migration-from-sqlite

SQLite로 시작한 FastAPI/SQLAlchemy/Alembic 프로젝트를 PostgreSQL로 안전하게 마이그레이션.
GEM-LLM `gateway.db` 200 동접 write-lock 사례 (troubleshooting case 14)에서 도출한 일반 가이드.

## 사용 시점 (트리거)

- "sqlite write lock", "database is locked", "OperationalError: database is locked"
- "100 동접 이상", "200 user concurrent", "production scaling"
- "sqlite 한계", "sqlite single-writer"
- "postgres migration", "sqlite to postgres"
- "alembic postgres", "asyncpg 전환"

## 언제 마이그레이션해야 하나?

SQLite는 운영 환경에서도 충분히 강력하지만, 아래 신호 중 2개 이상이면 PostgreSQL로 갈 시점:

| 신호 | 임계값 (대략) |
|------|--------------|
| 동시 write 요청 | 50+ req/s 이상에서 `database is locked` 빈발 |
| 동접 사용자 | 100+ (read 위주면 더 버팀, write 섞이면 위험) |
| 다중 워커/프로세스 | uvicorn `--workers 2+`에서 lock 충돌 시 |
| 다중 노드 | 한 DB를 여러 host가 써야 할 때 (SQLite는 불가능) |
| Replication 필요 | read replica, hot standby, PITR |
| 분석/집계 query | 큰 GROUP BY, window function 성능 |
| Row level security | RLS, 세분화된 권한 |

조건이 안되면 먼저 `sqlite-wal-safe-ops` skill의 WAL 튜닝부터 시도하자.

## SQLAlchemy DSN 차이

```python
# SQLite (async)
DATABASE_URL = "sqlite+aiosqlite:///./_data/gateway.db"

# PostgreSQL (async)
DATABASE_URL = "postgresql+asyncpg://gem:secret@localhost:5432/gem_gateway"

# PostgreSQL (sync, alembic용)
ALEMBIC_URL = "postgresql+psycopg2://gem:secret@localhost:5432/gem_gateway"
```

핵심 차이:
- SQLite는 파일 경로, PostgreSQL은 host/port/db/user/pass 4튜플
- SQLite는 `check_same_thread=False`, PostgreSQL은 connection pool 옵션 (pool_size, max_overflow, pool_pre_ping)
- 일부 SQLAlchemy 타입(`JSON`, `BIGINT`, `UUID`)은 SQLite에서 동작은 해도 의미가 약함 → Postgres에서 native 지원

## 7단계 마이그레이션

### 1. PostgreSQL 설치 (Docker 권장)

```bash
docker run -d --name gem-postgres \
  -e POSTGRES_USER=gem \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=gem_gateway \
  -p 5432:5432 \
  -v $PWD/_pgdata:/var/lib/postgresql/data \
  postgres:16
```

또는 K8s/시스템 패키지로 설치. 운영 환경은 16 LTS 권장 (asyncpg 호환성 검증됨).

### 2. 신규 DB 생성 + 권한

Docker `POSTGRES_DB`로 자동 생성된 경우 스킵. 별도 사용자 분리 시:

```sql
-- 관리자로 접속
CREATE DATABASE gem_gateway;
CREATE USER gem_app WITH ENCRYPTED PASSWORD 'app_secret';
GRANT ALL PRIVILEGES ON DATABASE gem_gateway TO gem_app;
\c gem_gateway
GRANT ALL ON SCHEMA public TO gem_app;
```

### 3. .env DSN 변경 (feature flag 권장)

```bash
# .env
DATABASE_URL=postgresql+asyncpg://gem:secret@localhost:5432/gem_gateway

# 점진적 롤아웃을 위해 flag 분리도 가능
DB_BACKEND=postgres   # sqlite | postgres
```

코드에서:

```python
if settings.db_backend == "postgres":
    DATABASE_URL = settings.postgres_url
else:
    DATABASE_URL = settings.sqlite_url
```

### 4. Alembic stamp 또는 재초기화

이미 운영 중인 SQLite DB가 있고 같은 schema로 PostgreSQL을 만들 경우:

**Option A — Alembic으로 새 DB에 schema만 만들기 (추천)**

```bash
# alembic.ini의 sqlalchemy.url을 postgres로 바꾼 뒤
alembic upgrade head
```

migration 파일들이 sqlite-only DDL을 쓰지 않았다면 그대로 동작한다. `BatchOperations`, `BLOB`, `INTEGER PRIMARY KEY AUTOINCREMENT` 등은 검토 필요.

**Option B — Schema는 SQLAlchemy `Base.metadata.create_all()`로 만들고 stamp**

```bash
python -c "from app.db import Base, engine; import asyncio; \
  asyncio.run(Base.metadata.create_all_async(engine))"
alembic stamp head
```

이후 새 migration은 정상적으로 PostgreSQL DDL로 생성됨.

### 5. 데이터 dump/restore (sqlite3 → CSV → psql COPY)

스키마는 4단계에서 만들었으니 이제 데이터만 옮긴다.

```bash
# 5-1. sqlite에서 테이블별 CSV 추출
sqlite3 -header -csv gateway.db "SELECT * FROM users;" > users.csv
sqlite3 -header -csv gateway.db "SELECT * FROM api_keys;" > api_keys.csv

# 5-2. PostgreSQL에 COPY로 적재
psql -U gem -d gem_gateway -c "\COPY users FROM 'users.csv' CSV HEADER"
psql -U gem -d gem_gateway -c "\COPY api_keys FROM 'api_keys.csv' CSV HEADER"
```

`scripts/migrate.sh`이 모든 테이블을 자동으로 처리한다.

대용량(>1GB)이면 `pgloader`를 검토 — 타입 변환과 시퀀스까지 알아서 한다:

```bash
pgloader sqlite:///path/to/gateway.db \
  postgresql://gem:secret@localhost/gem_gateway
```

### 6. SERIAL 시퀀스 회복

가장 흔한 실수. 데이터를 `INSERT ... id=...`로 넣으면 PostgreSQL의 SERIAL/IDENTITY 시퀀스가 따라 올라가지 않는다. 새 row를 만들면 `duplicate key`가 터진다.

```sql
-- 모든 SERIAL 컬럼 자동 복구
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT table_name, column_name, pg_get_serial_sequence(table_name, column_name) AS seq
    FROM information_schema.columns
    WHERE table_schema='public'
      AND column_default LIKE 'nextval%'
  LOOP
    EXECUTE format(
      'SELECT setval(%L, COALESCE((SELECT MAX(%I) FROM %I), 1))',
      r.seq, r.column_name, r.table_name
    );
  END LOOP;
END$$;
```

또는 테이블별 명시적으로:

```sql
SELECT setval(pg_get_serial_sequence('users', 'id'), (SELECT COALESCE(MAX(id), 1) FROM users));
```

### 7. 검증

```sql
-- row 수 비교 (sqlite와 일치해야 함)
SELECT 'users' AS t, COUNT(*) FROM users
UNION ALL SELECT 'api_keys', COUNT(*) FROM api_keys;

-- sample SELECT
SELECT id, email, created_at FROM users ORDER BY id DESC LIMIT 5;

-- 다음 시퀀스 값 확인
SELECT pg_get_serial_sequence('users', 'id'), nextval(pg_get_serial_sequence('users', 'id'));
```

application 측 검증:

```bash
# 신규 가입 / 로그인 / write 트랜잭션 모두 한 번씩
curl -X POST $API/users -d '{"email":"smoke@test"}'
curl $API/users/me -H "Authorization: Bearer $TOKEN"
```

## SQLAlchemy 코드 변경 (asyncpg 옵션)

```python
from sqlalchemy.ext.asyncio import create_async_engine

engine = create_async_engine(
    DATABASE_URL,
    pool_size=20,             # SQLite에는 없던 개념
    max_overflow=10,
    pool_pre_ping=True,       # stale 연결 자동 감지
    pool_recycle=3600,        # PgBouncer 등 미들웨어 사용 시
    connect_args={
        "server_settings": {"application_name": "gem-gateway"},
        "timeout": 10,
    },
)
```

`check_same_thread=False`는 SQLite 전용이므로 제거. autoflush/autocommit 동작은 동일.

## 흔한 함정

1. **NULL handling** — SQLite는 PRIMARY KEY에도 NULL을 허용한 적이 있음. PostgreSQL은 엄격. CSV에 빈 문자열이 들어가면 NOT NULL 위반.
2. **datetime** — SQLite는 텍스트로 저장, PostgreSQL은 `TIMESTAMP`. ISO8601 형식이면 자동 캐스팅되지만 microsecond, timezone 표기 차이 주의.
3. **integer auto-increment** — SQLite `INTEGER PRIMARY KEY AUTOINCREMENT` ≠ PostgreSQL `SERIAL`. 시퀀스 회복(6단계) 필수.
4. **Foreign key cascade** — SQLite는 `PRAGMA foreign_keys=ON` 안 켜면 무시. PostgreSQL은 항상 강제 → 데이터 부정합 노출.
5. **BOOLEAN** — SQLite는 0/1 정수로 저장. PostgreSQL은 `t`/`f` (CSV 적재 시) 또는 `true`/`false`. CAST 필요할 수 있음.
6. **JSON** — SQLite에선 텍스트, PostgreSQL은 `JSONB`. `json.loads()` 필요한 경우 ORM 매핑 재확인.
7. **case sensitivity** — PostgreSQL identifier는 따옴표로 감싸지 않으면 lowercase. `Users` 테이블이면 항상 `"Users"`.
8. **LIKE** — PostgreSQL `LIKE`는 case-sensitive. SQLite 기본은 case-insensitive. 전환 시 `ILIKE` 사용.

## 검증 후 SQLite 백업 보관

```bash
mv _data/gateway.db _data/gateway.db.pre-postgres-$(date +%Y%m%d)
# 최소 30일 보관 — rollback 대비
```

## 회귀 시 rollback 절차

1. `.env`의 `DATABASE_URL`을 SQLite로 되돌림 (또는 `DB_BACKEND=sqlite`)
2. application restart
3. PostgreSQL에서 발생한 신규 데이터는 손실됨 → 사전에 트래픽이 적은 시간대를 골라 마이그레이션
4. 원인 분석 후 재시도 — 보통 시퀀스 / NOT NULL / FK 부정합 중 하나

## 관련 skill

- `sqlite-wal-safe-ops` — 마이그레이션 전 SQLite를 더 짜내고 싶을 때
- `fastapi-gateway-pattern` — gateway 엔진/세션 설정 일반 패턴
- `gem-llm-troubleshooting` — case 14 원본 사례
