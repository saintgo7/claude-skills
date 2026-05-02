#!/usr/bin/env bash
# migrate.sh — SQLite → PostgreSQL 데이터 마이그레이션
#
# Usage: migrate.sh <sqlite-path> <postgres-dsn>
# Example:
#   migrate.sh _data/gateway.db postgresql://gem:secret@localhost:5432/gem_gateway
#
# 전제: PostgreSQL 측 schema는 이미 만들어져 있다 (alembic upgrade head 또는 create_all).
# 동작:
#   1) sqlite3 / psql / pg_dump 존재 확인
#   2) pg_dump --schema-only로 대상 schema 미리보기 (검증)
#   3) sqlite의 각 user 테이블을 CSV로 추출 → psql \COPY로 적재
#   4) row 수 비교
#   5) SERIAL 시퀀스 자동 회복

set -euo pipefail

SQLITE="${1:-}"
PGDSN="${2:-}"

if [ -z "$SQLITE" ] || [ -z "$PGDSN" ]; then
  echo "Usage: $0 <sqlite-path> <postgres-dsn>" >&2
  exit 1
fi

[ -f "$SQLITE" ] || { echo "ERROR: '$SQLITE' not found" >&2; exit 1; }

for cmd in sqlite3 psql pg_dump; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd not installed" >&2; exit 1; }
done

# 연결 검증
psql "$PGDSN" -c "SELECT version();" >/dev/null || {
  echo "ERROR: cannot connect to $PGDSN" >&2; exit 1;
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "→ working dir: $WORK"

# 1) schema 미리보기
echo "→ pg_dump --schema-only (preview)"
pg_dump --schema-only --no-owner "$PGDSN" | grep -E '^(CREATE TABLE|ALTER TABLE)' | head -30 || true

# 2) sqlite 사용자 테이블 목록 (sqlite_*, alembic_version 제외)
TABLES=$(sqlite3 "$SQLITE" \
  "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'alembic_version';")

if [ -z "$TABLES" ]; then
  echo "ERROR: no user tables in $SQLITE" >&2; exit 1;
fi

echo "→ tables to migrate:"
echo "$TABLES" | sed 's/^/    /'

# 3) 테이블별 CSV 추출 및 COPY
for tbl in $TABLES; do
  csv="$WORK/${tbl}.csv"
  echo "→ [$tbl] dump..."
  sqlite3 -header -csv "$SQLITE" "SELECT * FROM \"$tbl\";" > "$csv"

  rows_src=$(($(wc -l < "$csv") - 1))
  echo "    sqlite rows: $rows_src"

  if [ "$rows_src" -le 0 ]; then
    echo "    skip (empty)"
    continue
  fi

  # 기존 데이터 있으면 중단 (사고 방지)
  exist=$(psql "$PGDSN" -tAc "SELECT COUNT(*) FROM \"$tbl\";" 2>/dev/null || echo "0")
  if [ "$exist" != "0" ]; then
    echo "    WARN: target has $exist rows already — skipping (use TRUNCATE first if intended)" >&2
    continue
  fi

  echo "    \\COPY into postgres..."
  psql "$PGDSN" -c "\\COPY \"$tbl\" FROM '$csv' CSV HEADER"

  rows_dst=$(psql "$PGDSN" -tAc "SELECT COUNT(*) FROM \"$tbl\";")
  echo "    postgres rows: $rows_dst"

  if [ "$rows_src" != "$rows_dst" ]; then
    echo "    FAIL: row count mismatch ($rows_src vs $rows_dst)" >&2; exit 2;
  fi
done

# 4) SERIAL 시퀀스 회복
echo "→ resetting SERIAL sequences..."
psql "$PGDSN" <<'SQL'
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT table_name, column_name,
           pg_get_serial_sequence(quote_ident(table_name), column_name) AS seq
    FROM information_schema.columns
    WHERE table_schema='public' AND column_default LIKE 'nextval%'
  LOOP
    IF r.seq IS NOT NULL THEN
      EXECUTE format(
        'SELECT setval(%L, COALESCE((SELECT MAX(%I) FROM %I), 1))',
        r.seq, r.column_name, r.table_name
      );
      RAISE NOTICE 'reset % (col=%)', r.seq, r.column_name;
    END IF;
  END LOOP;
END$$;
SQL

echo "OK — migration complete. Run application smoke tests next."
