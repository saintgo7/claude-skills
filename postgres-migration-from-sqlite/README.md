# postgres-migration-from-sqlite

SQLite → PostgreSQL 마이그레이션 스킬 (FastAPI/SQLAlchemy/Alembic). GEM-LLM `gateway.db` 200 동접 write-lock 사례 (troubleshooting case 14)에서 도출한 일반 가이드.

## 사용 시점

- "sqlite write lock", "database is locked", "100+ 동접"
- "postgres migration", "production scaling"
- "alembic postgres", "asyncpg 전환"

## 설치

```bash
./install.sh postgres-migration-from-sqlite
```

7단계 마이그레이션 (PG 설치 → DB/권한 → DSN → Alembic → dump/restore → SERIAL 시퀀스 회복 → 검증), 흔한 함정 (NULL/datetime/auto-increment/FK cascade), rollback 절차는 [SKILL.md](SKILL.md) 참조. 자동화 스크립트는 [scripts/migrate.sh](scripts/migrate.sh).
