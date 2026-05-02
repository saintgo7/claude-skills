# sqlite-wal-safe-ops

SQLite WAL 모드 운영 함정 회피 스킬. GEM-LLM `_data/gateway.db` 손상 사례 (troubleshooting case 13)에서 도출.

## 사용 시점

- "disk I/O error", "sqlite3 OperationalError"
- "db-wal db-shm 손상", "sqlite 백업 안전"
- "활성 db 파일 옮기기", "wal checkpoint"
- "journal_mode"

## 설치

```bash
./install.sh sqlite-wal-safe-ops
```

WAL/SHM 파일 mv 금지 정책, graceful shutdown 백업 흐름, `PRAGMA journal_mode=DELETE` 단순화 옵션은 [SKILL.md](SKILL.md) 참조.
