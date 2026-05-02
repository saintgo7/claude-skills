---
name: sqlite-wal-safe-ops
description: 'SQLite WAL 모드 운영 함정 회피. 사용 시점 — "disk I/O error", "sqlite3 OperationalError", "db-wal db-shm 손상", "sqlite 백업 안전", "활성 db 파일 옮기기", "wal checkpoint", "journal_mode". WAL/SHM 파일 mv 금지 정책, graceful shutdown 백업 흐름, PRAGMA journal_mode=DELETE 단순화 옵션.'
---

# sqlite-wal-safe-ops

SQLite를 WAL(Write-Ahead Logging) 모드로 운영할 때 마주치는 함정과 안전한 패턴.
GEM-LLM의 `_data/gateway.db` 손상 사례(troubleshooting case 13)에서 도출한 일반 가이드.

## 사용 시점 (트리거)

- `sqlite3.OperationalError: disk I/O error` 발생
- `database disk image is malformed` 또는 `database is locked`
- `db-shm`, `db-wal` 사이드카 파일 처리 헷갈림
- 운영 중 `*.db` 백업 / 이동 / 정리 직전
- `git rm`, `mv`, `rsync`, K8s pod 재시작이 활성 DB와 겹칠 때
- `journal_mode=WAL` 유지 vs `DELETE` 단순화 결정
- "왜 commit 했는데 .db만 0바이트로 보이지?"

## SQLite WAL 모드 동작

WAL 모드에서는 단일 논리 DB가 **3개 파일**로 표현된다:

| 파일 | 역할 | 비고 |
|---|---|---|
| `mydb.sqlite` | 메인 DB (체크포인트된 페이지) | 단독으로는 최신 데이터 아님 |
| `mydb.sqlite-wal` | 미체크포인트 트랜잭션 로그 | 활성 시 핵심, 재기동 시 복구에 필수 |
| `mydb.sqlite-shm` | 공유 메모리 인덱스 (mmap) | 자동 재생성 가능, 단 활성 중에는 손대면 안 됨 |

`PRAGMA journal_mode=WAL`은 동시 read/write 성능을 크게 끌어올리지만, **세 파일이 한 묶음**이라는 사실을 잊으면 손상으로 직행한다.

확인:
```bash
sqlite3 mydb.sqlite "PRAGMA journal_mode;"
# wal  → WAL 모드
# delete → 전통 rollback journal 모드
```

## 금기 사항 (실제 손상 사례)

### 1. 활성 DB의 WAL/SHM 파일을 mv

```bash
# GEM-LLM 실제 사례 — case 13
mv _data/*.db-wal _trash/        # 다음 요청부터 disk I/O error
mv _data/*.db-shm _trash/        # 메인 .db는 stale 상태로 남음
```

WAL을 떼어내면 메인 `.db`는 **이미 커밋된 트랜잭션도 포함되지 않은** 옛 스냅샷이 된다. 다음 connection이 열리는 순간 무결성이 깨진다.

### 2. 백업할 때 .db만 복사

```bash
# 잘못된 백업
cp gateway.db backup/                  # WAL에 든 최근 트랜잭션 누락
rsync prod-db/gateway.db backup/       # 동일 함정
```

특히 트래픽이 잦은 시간에 찍으면 `.db`가 수 분~수 시간 전 상태인 경우가 흔하다.

### 3. `git rm --cached`와 `.gitignore` 혼동

```bash
# 위험
git rm --cached gateway.db-wal         # 활성 중 ref 끊김 + 스테이지 변동
```

- `.gitignore`에 `*.db-wal`, `*.db-shm` 추가 → **안전**. 디스크 파일 건드리지 않음.
- `git rm --cached`는 이미 추적되던 파일에만 의미 있고, 그 자체로 디스크는 보존하지만 워크플로(예: pre-commit, `git clean`)와 결합하면 위험. 활성 중에는 피한다.

### 4. K8s pod 재시작 / 컨테이너 SIGKILL 중 WAL 미플러시

- `terminationGracePeriodSeconds`가 짧아 앱이 connection close를 못 함
- `emptyDir` / hostPath에 WAL 남고 다음 pod가 다른 노드에서 새 마운트로 뜸
- `kubectl delete pod --force --grace-period=0` → WAL 체크포인트 미실행

→ 운영 DB는 PVC로 고정 마운트하고 graceful shutdown(SIGTERM) 핸들러에서 명시 close.

## 안전한 패턴

### A. graceful shutdown 후 이동

```bash
# 1) 앱 멈춤 — connection 모두 닫힐 때까지
systemctl stop gateway          # 또는 supervisor stop, kubectl scale --replicas=0
# 2) 잔여 lock 확인
lsof gateway.db gateway.db-wal gateway.db-shm   # 빈 출력이어야 함
# 3) 그 후 이동
mv _data/ _data-archive-$(date +%F)/
```

### B. WAL checkpoint 후 백업 (앱 가동 중에도 가능)

```bash
sqlite3 gateway.db "PRAGMA wal_checkpoint(TRUNCATE);"
# WAL 내용이 메인 DB로 흡수되고 wal 파일이 0바이트로 잘림
cp gateway.db backup/gateway-$(date +%FT%H%M%S).db
sqlite3 backup/gateway-*.db "PRAGMA integrity_check;"   # ok 확인
```

또는 SQLite 내장 백업 API:

```bash
sqlite3 gateway.db ".backup 'backup/gateway.db'"
# 라이브 백업 — 진행 중 트랜잭션과 안전하게 직렬화됨
```

`scripts/safe-backup.sh`가 이 흐름을 자동화한다 (체크포인트 → 3 파일 복사 → 무결성 검증).

### C. WAL 사용 안 해도 되면 DELETE 모드

소규모/저동시성 앱(관리자용 메타 DB, 단일 워커 봇)이라면:

```sql
PRAGMA journal_mode=DELETE;
```

- 사이드카 파일이 사라져 백업/이동이 단일 파일 단위로 단순화
- 동시 read/write 성능은 약간 떨어짐 (writer가 reader를 잠시 막음)
- 운영 DB(다수 동시 요청 처리하는 gateway 등)에는 비추천

### D. .gitignore 권장 엔트리

```gitignore
# SQLite WAL 사이드카 — 디스크는 그대로, 추적만 제외
*.db-wal
*.db-shm
*.sqlite-wal
*.sqlite-shm
```

메인 `*.db` 자체도 보통 ignore가 맞고, 스키마는 alembic 마이그레이션이나 `schema.sql`로 따로 추적.

## scripts/safe-backup.sh

```bash
bash scripts/safe-backup.sh _data/gateway.db backups/
# 1. 메인 DB가 WAL 모드인지 확인
# 2. PRAGMA wal_checkpoint(TRUNCATE) 실행
# 3. .db / .db-wal / .db-shm 모두 timestamp 붙여 복사
# 4. 백업본에 PRAGMA integrity_check
```

활성 앱과 동시에 실행해도 안전하다 (체크포인트는 락을 잠깐만 잡음).

## 손상 시 복구

이미 `disk I/O error`가 뜨고 있다면:

1. **격리** — 손상 디렉터리 통째로 `mv`:
   ```bash
   mv _data _trash/data-broken-$(date +%FT%H%M%S)/
   ```
2. **빈 디렉터리 + 마이그레이션**:
   ```bash
   mkdir -p _data
   alembic upgrade head           # 또는 앱이 부팅 시 schema 자동 생성
   ```
3. **데이터 재발급** — API key, 사용자, 세션 등은 운영 채널로 재발급. 손상된 DB에서 `sqlite3 ... .recover`로 일부 건질 수 있지만, gateway류는 일관성이 깨졌을 가능성이 높아 재발급이 빠르다.
4. **사후** — `_trash/data-broken-*`는 한 주기 후 검증 끝나면 삭제.

## 트러블슈팅

| 증상 | 원인 후보 | 조치 |
|---|---|---|
| `disk I/O error` | WAL/SHM mv, 디스크 풀, 권한 | 위 "복구" 흐름 + `df -h`, `ls -la _data/` |
| `database is locked` | 다른 long-running tx, 너무 짧은 busy_timeout | `PRAGMA busy_timeout=5000`, write contention 줄이기 |
| `database disk image is malformed` | 부분 쓰기 (전원/SIGKILL), 파일시스템 손상 | `.recover` 시도, 안 되면 백업에서 복원 |
| .db만 백업했는데 최신 데이터 없음 | WAL 미체크포인트 | 앞으로 `safe-backup.sh` 사용 |
| pod 재시작 후 `unable to open database file` | 볼륨 마운트 누락 | PVC 확인, init container 권한 |

## 관련 skill

- `gem-llm-troubleshooting` (case 13 — 본 사례 원전)
- `gem-llm-gateway-debug` — gateway DB 연결 풀 / SQLAlchemy 설정 (case 12)
- `gem-llm-supervisor` — graceful shutdown (`stop` 명령) 흐름

## 참조

- SQLite WAL 공식: https://sqlite.org/wal.html
- Backup API: https://sqlite.org/backup.html
- `PRAGMA journal_mode`: https://sqlite.org/pragma.html#pragma_journal_mode
