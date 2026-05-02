---
name: bash-cli-best-practices
description: 'bash로 운영 CLI 작성 시 검증된 패턴 — set -euo pipefail, sub-command dispatch, 환경변수 우선순위, mv to _trash, prepared statement(SQL injection). 사용 시점 — "bash cli", "운영 자동화", "rm -rf 금지", "subcommand 라우터", "안전한 셸 스크립트", "supervisor.sh", "admin-cli". GEM-LLM에서 검증.'
---

# bash-cli-best-practices

운영 CLI를 bash로 짜다 보면 같은 함정에 매번 빠진다 — `set -e` 빼먹어서 에러가 무시되고, 변수 인용을 빠뜨려 스페이스에 깨지고, `rm -rf`로 복구 불가능한 사고를 내고, sqlite에 user input 그대로 박아 넣어 SQL injection을 만든다. 아래 8 패턴은 GEM-LLM의 `supervisor.sh`(전체 스택 start/stop/status), `admin-cli.sh`(사용자/quota 관리), `health-monitor.sh`(주기 헬스체크) 세 스크립트 운영에서 검증된 조합이다. 일반 bash CLI 어디에나 같은 함정이 있고 같은 해법이 통한다.

## 사용 시점

- "bash cli 처음", "운영 스크립트", "subcommand 라우터"
- "rm -rf 대신 mv to _trash", "안전한 삭제"
- "set -e", "set -u", "pipefail"
- "PID 파일", "nohup setsid 백그라운드"
- "헬스체크 폴링 curl", "epoch ms latency"
- "bash에서 sqlite SQL injection 안전하게"
- "supervisor.sh", "admin-cli.sh"

## 8 패턴 한눈에

| # | 패턴 | 해결 |
|---|---|---|
| 1 | `set -euo pipefail` | 에러 무시 / 미정의 변수 / 파이프 silent fail 차단 |
| 2 | Sub-command dispatch | `case` 한 곳에서 라우팅, `shift "$@"` 패스스루 |
| 3 | 환경변수 + .env 우선순위 | CLI args > env > .env > default 4단계 |
| 4 | `mv to _trash` | `rm -rf` 금지, 타임스탬프 디렉토리에 격리 |
| 5 | Prepared statement (Python 바인딩) | bash → sqlite SQL injection 방지 |
| 6 | PID 파일 + 좀비 청소 | `kill -0`로 살아있는지 확인 후 시작 |
| 7 | 헬스체크 폴링 | `curl -m -w "%{http_code}"` + `seq` 루프 |
| 8 | `setsid nohup` 백그라운드 | 셸 종료에도 살아남는 분리된 프로세스 |

## 1. `set -euo pipefail` (필수)

```bash
set -euo pipefail
```

- `-e`: 명령이 0이 아닌 코드로 끝나면 즉시 종료. 실패한 `mkdir`이 조용히 넘어가서 다음 줄 `cd`가 엉뚱한 디렉토리로 가는 사고를 막는다.
- `-u`: 미정의 변수 참조 시 에러. `${MY_VAR:-default}` 또는 `${1:-}`로 명시적 기본값을 강제하게 됨.
- `-o pipefail`: `cmd1 | cmd2`에서 `cmd1`이 실패해도 `cmd2`가 0이면 전체가 0이 되는 default를 뒤집는다. `curl ... | jq ...`에서 curl 실패를 잡을 때 필수.

예외적으로 실패가 정상인 경우만 `|| true`:
```bash
kill -TERM "$pid" 2>/dev/null || true
```

## 2. Sub-command dispatch

`git`, `kubectl`, `docker`처럼 `<cli> <verb> [args...]` 구조.

```bash
case "${1:-help}" in
  start)   shift; cmd_start "$@" ;;
  stop)    shift; cmd_stop "$@" ;;
  status)  cmd_status ;;
  logs)    shift; cmd_logs "${1:-gateway}" ;;
  help|*)
    cat <<EOF
사용: $0 {start|stop|status|logs [service]}
EOF
    ;;
esac
```

핵심:
- `${1:-help}` — 인자 없이 실행해도 `set -u`에 안 걸림.
- `shift; cmd_xxx "$@"` — verb 제거 후 나머지 인자를 함수에 그대로 넘김.
- `*)` 마지막에 두고 도움말. 알 수 없는 verb도 도움말로 떨어짐.

GEM-LLM의 `admin-cli.sh`는 이 패턴으로 10개 sub-command(`add-user`/`issue-key`/`set-quota`/...)를 한 파일에 깔끔히 둔다.

## 3. 환경변수 + .env 우선순위

운영 CLI는 4단계 우선순위 — **CLI args > env > .env > default**.

```bash
PROJECT_ROOT="${PROJECT_ROOT:-/home/jovyan/gem-llm}"
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"

# .env 자동 로드 (set -a로 export 강제)
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

ADMIN_KEY="${GATEWAY_ADMIN_KEY:-}"
[ -z "$ADMIN_KEY" ] && { echo "ERROR: GATEWAY_ADMIN_KEY 미설정" >&2; exit 1; }
```

- `${VAR:-default}`로 default 표시. `set -u`와 자연스럽게 호환.
- `set -a; source .env; set +a` — `.env`의 모든 var을 자동으로 export. 안 하면 자식 프로세스(python, curl)가 못 봄.
- `.env`는 `git`에 절대 안 넣음 — `.gitignore`에 항상 추가.

## 4. `rm -rf` 대신 `mv to _trash`

운영 스크립트에서 `rm -rf "$DIR/$VAR/"` 같은 줄은 한 줄 오타로 시스템을 날린다. 대안:

```bash
TRASH="$PROJECT_ROOT/_trash/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$TRASH"
mv "$old_pidfile" "$TRASH/" 2>/dev/null || rm -f "$old_pidfile"
```

핵심:
- `_trash/<TS>/`로 격리. 사고가 나도 `mv` 되돌리면 복구 가능.
- `mv` 실패해도 (예: 파일 없음) 다음 줄 `rm -f`가 책임. `|| rm -f` 패턴.
- 주기적으로 `find _trash -mtime +30 -delete` cron으로 청소.
- GEM-LLM `supervisor.sh`의 `stop_service`가 이 패턴으로 죽은 PID 파일을 보존함.

## 5. SQL injection 방지 (Python prepared statement)

bash에서 `sqlite3 db "SELECT ... WHERE id = '$USER_ID'"` 같이 변수를 직접 박으면 `'; DROP TABLE users; --` 한 방에 망한다. 해법은 bash → Python heredoc + `?` placeholder.

```bash
GATEWAY_DB="$db" USER_ID="$user_id" python3 - <<'PYEOF'
import os, sqlite3, sys
db = os.environ["GATEWAY_DB"]
uid = os.environ["USER_ID"]
conn = sqlite3.connect(db)
cur = conn.cursor()
cur.execute(
    "SELECT user_id, daily_token_limit FROM quotas WHERE user_id = ?",
    (uid,),
)
row = cur.fetchone()
if not row:
    print(f"ERROR: user_id='{uid}' 없음", file=sys.stderr)
    sys.exit(2)
print(row)
conn.close()
PYEOF
```

핵심:
- 변수는 **환경변수로** 전달 — heredoc 안에 `$USER_ID`를 박지 않음 (`<<'PYEOF'`로 quote해서 bash 보간 차단).
- Python `sqlite3.execute(sql, params)`의 두 번째 인자가 prepared statement bind. `?`로 자리 표시.
- `set -e` + `sys.exit(2)` 조합으로 bash 호출자도 에러를 받음.
- GEM-LLM `admin-cli.sh`의 `cmd_get_quota`/`cmd_set_quota`가 이 패턴.

## 6. PID 파일 + 좀비 청소

```bash
start_service() {
  local name=$1 cmd=$2
  local pidfile="$LOG_DIR/$name.pid"

  # 기존 프로세스 확인
  if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    echo "  [$name] 이미 실행 중 (PID $(cat "$pidfile"))"
    return
  fi
  # PID 파일은 있지만 프로세스 죽어있음 → 좀비 PID 파일
  [ -f "$pidfile" ] && rm -f "$pidfile"

  setsid nohup bash -c "$cmd" > "$LOG_DIR/$name.log" 2>&1 < /dev/null &
  echo $! > "$pidfile"
}
```

- `kill -0 PID` — 신호 안 보내고 프로세스 존재만 확인. 권한 있는 프로세스에만 0 리턴.
- `2>/dev/null` — 죽은 PID는 stderr 안 내보냄.
- `kill -TERM -- -$pid` — 음수 PID는 프로세스 그룹 전체. `setsid`로 새 그룹 만들어 자식까지 같이 죽임.

## 7. 헬스체크 폴링

```bash
for i in $(seq 1 30); do
  code=$(curl -s -m 3 -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null || echo "000")
  [ "$code" = "200" ] && break
  sleep 10
done
[ "$code" != "200" ] && { echo "ERROR: $URL 응답 없음 (5분)"; exit 1; }
```

핵심 옵션:
- `-s` silent (progress bar 끄기), `-m 3` 3초 timeout, `-o /dev/null` body 버림.
- `-w "%{http_code}"` — body 대신 status code만 출력. 가장 자주 쓰는 패턴.
- `|| echo "000"` — curl 자체가 실패해도 변수에 무언가 들어가게 (`set -e` 회피).

latency까지 재려면 `epoch.ns + awk`:
```bash
t0=$(date +%s.%N)
curl -s -m 5 ... > /dev/null
t1=$(date +%s.%N)
ms=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.0f", (b-a)*1000}')
```

`bc`는 POSIX 미지원 환경(busybox, 컨테이너)에서 자주 빠져 있음. **`awk`만 쓴다**.

## 8. `setsid + nohup` (분리된 백그라운드)

`my-cli start &` 만 하면 셸 종료 시 SIGHUP으로 같이 죽는다. 운영 데몬은 이렇게:

```bash
setsid nohup bash -c "$cmd" > "$logfile" 2>&1 < /dev/null &
echo $! > "$pidfile"
```

- `setsid` — 새 세션/프로세스 그룹 생성. 부모 셸의 SIGHUP과 분리.
- `nohup` — SIGHUP 무시 (이중 안전망).
- `> log 2>&1 < /dev/null` — stdout/stderr는 로그로, stdin은 close. 안 닫으면 터미널 의존성 남음.
- `&` 후 `$!`가 방금 띄운 프로세스의 PID. 즉시 PID 파일에 기록.

## 흔한 함정

- **`set -e` 없이 작성** — `mkdir` 실패해도 다음 줄로. 운영 사고의 60%는 여기서 시작.
- **`$1` unquoted** — `cmd_start $1` → 스페이스 들어간 인자가 두 개로 쪼개짐. **항상 `"$1"`**.
- **`cd` 후 `set -e` 반대 동작** — `cd /nonexistent` 실패 시 즉시 종료. 의도한 거면 OK, 아니면 `cd /x || true`.
- **`find -exec` 인용 부족** — `find . -name "*.log" -exec rm {} \;`에서 `\;`를 빠뜨리면 모든 파일을 한 번에 넘김. 또는 차라리 `find ... -delete`.
- **`bc` 의존성** — busybox/Alpine/컨테이너에 자주 없음. 부동소수 계산은 **`awk -v` + printf**로.
- **heredoc bash 보간** — `<<EOF`는 `$VAR` 보간됨, `<<'EOF'`(quote)는 그대로. Python heredoc은 **반드시 `<<'PYEOF'`**.
- **`source .env` 시 `set +a` 누락** — export 안 되어 자식 프로세스가 못 봄.
- **`shift`를 sub-command 함수 호출 전에 안 함** — `cmd_start`가 verb를 자기 인자로 받음.

## 시작 체크리스트

새 CLI를 만들 때 이 순서로:

1. `#!/usr/bin/env bash` + `set -euo pipefail`
2. `PROJECT_ROOT`, `LOG_DIR`, 주요 경로 변수 선언 (모두 `${X:-default}`)
3. `.env` 로드 블록 (`set -a; source; set +a`)
4. 헬퍼 함수 (`api()`, `probe_http()`, `now_ms()`)
5. `cmd_<verb>` 함수들 정의
6. 마지막에 `case "${1:-help}"` dispatcher
7. `templates/cli-skeleton.sh.template`을 복사해 시작하는 게 빠름

## 관련 skills

- `gem-llm-supervisor` — 이 패턴으로 짠 4-서비스 supervisor.
- `gem-llm-admin-cli` — 사용자/quota 관리 CLI 실제 사례.
- `sqlite-wal-safe-ops` — sqlite를 더 안전하게 다루는 보완.
