#!/usr/bin/env bash
# safe-backup.sh — SQLite WAL 모드 안전 백업
#
# Usage: safe-backup.sh <db-file> [<backup-dir>]
# Example: safe-backup.sh _data/gateway.db backups/
#
# 1) WAL checkpoint(TRUNCATE)로 .db에 모든 트랜잭션 흡수
# 2) .db / .db-wal / .db-shm 존재하는 것 모두 timestamp 붙여 복사
# 3) 백업본 PRAGMA integrity_check 검증

set -euo pipefail

DB="${1:-}"
BACKUP_DIR="${2:-backups}"

if [ -z "$DB" ]; then
  echo "Usage: $0 <db-file> [<backup-dir>]" >&2
  exit 1
fi

if [ ! -f "$DB" ]; then
  echo "ERROR: '$DB' not found" >&2
  exit 1
fi

command -v sqlite3 >/dev/null || { echo "ERROR: sqlite3 not installed" >&2; exit 1; }

mkdir -p "$BACKUP_DIR"

TS="$(date +%Y%m%dT%H%M%S)"
BASE="$(basename "$DB")"
DIR="$(dirname "$DB")"

MODE="$(sqlite3 "$DB" "PRAGMA journal_mode;" 2>/dev/null || echo unknown)"
echo "→ journal_mode=$MODE"

if [ "$MODE" = "wal" ]; then
  echo "→ WAL checkpoint(TRUNCATE)..."
  sqlite3 "$DB" "PRAGMA wal_checkpoint(TRUNCATE);"
fi

# 3 파일 모두 복사 (있는 것만)
COPIED=()
for suffix in "" "-wal" "-shm"; do
  src="${DIR}/${BASE}${suffix}"
  if [ -f "$src" ]; then
    dst="${BACKUP_DIR}/${BASE}.${TS}${suffix}"
    cp -p "$src" "$dst"
    COPIED+=("$dst")
    echo "  copied: $src → $dst"
  fi
done

# 무결성 검증 (메인 .db 파일에만)
MAIN_BACKUP="${BACKUP_DIR}/${BASE}.${TS}"
echo "→ integrity_check on $MAIN_BACKUP"
RESULT="$(sqlite3 "$MAIN_BACKUP" "PRAGMA integrity_check;")"
if [ "$RESULT" = "ok" ]; then
  echo "OK — backup verified (${#COPIED[@]} files)"
else
  echo "FAIL — integrity_check returned: $RESULT" >&2
  exit 2
fi
