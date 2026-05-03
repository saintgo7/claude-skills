---
name: shell-cli-dispatch-pattern
description: 'Bash CLI sub-command dispatcher 정형 패턴. 사용 시점 — "bash CLI", "subcommand", "argument forwarding", "shift", "case dispatch", "admin-cli", "옵션 무시됨", "silent bug 셸". `shift; cmd_<name> "$@"` 정형 + shellcheck + 회귀 테스트. gem-llm case 19에서 추출.'
---

# shell-cli-dispatch-pattern

Bash로 작성한 운영 CLI (admin-cli, ops-tool, deploy.sh 등) 의 sub-command dispatcher 표준 패턴.
`shift; "$@"` 한 줄을 빠뜨리면 옵션이 silent하게 무시되는 버그가 발생한다.
shellcheck + dispatch lint + 회귀 테스트 3중 디펜스로 막는다.

## 1. 사용 시점

- `bash admin-cli list-users --plan free` 처럼 sub-command + 옵션을 받는 셸 스크립트를 작성/수정할 때
- "옵션이 무시되는 것 같은데 에러는 안 난다" 류 silent bug 디버깅 중일 때
- `case "$1" in ...) cmd_xxx ;;` 형태의 dispatcher를 리뷰할 때
- shell CLI에 새 sub-command 를 추가할 때 (정형 boilerplate 적용)

## 2. 잘못된 패턴 (silent bug 유발)

```bash
case "$1" in
  list-users) cmd_list_users ;;          # ❌ 인자 전달 X
  add-user)   cmd_add_user ;;            # ❌
esac
```

증상:
- `admin-cli list-users --plan free` 실행 시 `--plan free` 가 `cmd_list_users` 에 도달하지 않음
- `cmd_list_users` 내부의 옵션 파서는 빈 인자를 받아 default 분기로 떨어짐 → 필터 무시
- exit code 0, 에러 출력 없음 → silent bug

## 3. 정형 패턴 (case 19 fix)

```bash
[ "$#" -eq 0 ] && { usage; exit 0; }
cmd="$1"; shift                           # ← sub-command 만 소비
case "$cmd" in
  list-users) cmd_list_users "$@" ;;      # ✅ 나머지 인자 전체 forward
  add-user)   cmd_add_user "$@" ;;        # ✅
  -h|--help)  usage ;;
  *) echo "Unknown command: $cmd" >&2; usage; exit 1 ;;
esac
```

핵심 규칙 3가지:
1. dispatcher 진입 전 `cmd="$1"; shift` 로 sub-command 분리
2. 모든 분기에서 `"$@"` 인자 전체 forward (큰따옴표 필수: SC2068 회피)
3. `*)` default 분기로 typo 검출 + exit 1

## 4. 옵션 파싱 표준 (long option + `=` 형식 모두)

각 `cmd_xxx` 함수 내부:

```bash
cmd_list_users() {
  local plan=""
  local active=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --plan)     plan="$2"; shift 2 ;;
      --plan=*)   plan="${1#*=}"; shift ;;
      --active)   active="true"; shift ;;
      --)         shift; break ;;            # 종료 명시
      -*)         echo "Unknown option: $1" >&2; return 1 ;;
      *)          echo "Unexpected arg: $1" >&2; return 1 ;;
    esac
  done
  api GET "${API_BASE}/users${plan:+?plan=$plan}"
}
```

요점:
- `--plan PLAN` (공백) 과 `--plan=PLAN` (등호) 둘 다 지원 → 사용자 습관 차이 흡수
- `-*)` 분기로 unknown 옵션 fail-fast (default 분기에 흡수되지 않게)
- `--` 로 옵션 종료 명시 가능

## 5. set -euo pipefail (필수)

스크립트 첫 줄 다음 무조건:

```bash
#!/bin/bash
set -euo pipefail
```

- `-e` 에러 즉시 종료 → silent fail 차단
- `-u` 미정의 변수 참조 시 에러 → 오타 검출 (`$user` vs `$usr`)
- `-o pipefail` 파이프 중간 실패 감지 → `cmd | jq` 에서 `cmd` 가 죽어도 알 수 있음

조건부로 unset 가능한 변수는 `${VAR:-}` 로 default 처리.

## 6. fail-fast curl

```bash
api() {
  curl --fail-with-body -sS \
       -H "Authorization: Bearer $ADMIN_TOKEN" \
       -H "Content-Type: application/json" \
       "$@"
}
```

- `--fail-with-body` : HTTP 4xx/5xx 시 exit 22 + body 출력 (silent 4xx 차단)
- `-sS` : progress 숨기되 에러는 출력
- `--fail` 단독은 body 손실 → 반드시 `--fail-with-body`

## 7. 회귀 테스트 패턴

옵션이 **실제로 효과를 내는지** 검증 (case 19 재발 방지):

```bash
# tests/test_admin_cli.sh
total=$(bash admin-cli.sh list-users | jq 'length')
filtered=$(bash admin-cli.sh list-users --plan free | jq 'length')
[ "$filtered" -lt "$total" ] || {
  echo "FAIL: --plan filter ignored ($filtered == $total)" >&2
  exit 1
}
```

요점:
- 옵션 적용 전/후 결과 카운트 비교 → "옵션이 dispatch 됐는가" 가 아니라 "옵션이 효과를 냈는가" 검증
- pytest + subprocess 로 옮겨도 동일 (admin-cli smoke test)

## 8. shellcheck 통합

CI 에 추가:

```bash
shellcheck -e SC1090 -e SC1091 admin-cli.sh
```

특히 잡아야 할 룰:
- SC2046 unquoted command substitution (단어 분할)
- SC2086 unquoted variable (글로빙)
- SC2068 array `$@` 큰따옴표 누락
- SC2154 referenced but not assigned (typo)

`set -u` + shellcheck SC2154 조합으로 변수 typo 가 두 번 막힌다.

## 9. dispatch lint script

`scripts/check-dispatch.sh <script.sh>` 로 dispatcher 패턴 위반 정적 검출.
case 분기 라인에 `"$@"` 가 없으면 violation 으로 보고.
CI 의 shellcheck 다음 단계로 추가:

```yaml
- name: dispatch lint
  run: bash scripts/check-dispatch.sh admin-cli.sh
```

휴리스틱이라 false positive 가 있을 수 있다 (인자 없는 sub-command 의도된 경우).
그 경우 함수명을 `cmd_xxx_noargs` 같이 표시하거나 lint 주석으로 무시.

## 10. 흔한 실수 표

| 증상 | 원인 | 해결 |
|---|---|---|
| 옵션 silent 무시 | dispatch 분기 `"$@"` 누락 | 정형 dispatch (3절) |
| 4xx silent | `curl -s` 만 사용 | `--fail-with-body` (6절) |
| 미정의 변수가 빈 문자열 | `set -u` 없음 | `set -euo pipefail` (5절) |
| 파이프 앞 명령 실패 무시 | `set -e` 만 | `-o pipefail` (5절) |
| `--plan free` 만 동작, `--plan=free` 안됨 | `=` 형식 분기 누락 | `--plan=*)` (4절) |
| typo sub-command 가 동작 | `*)` default 누락 | default 분기 + exit 1 (3절) |
| `cmd_x $@` 글로빙 | `"$@"` 큰따옴표 빠짐 | 항상 `"$@"` (SC2068) |

## 11. 관련 skill

- `bash-cli-best-practices` — set -euo pipefail, mv to _trash, SQL injection 방지 등 일반 베이스
- `api-route-consistency-pattern` (case 20) — Gateway ↔ CLI 라우트 4-way 일관성
- `production-postmortem-pattern` (case 19 사례 포함) — silent bug 사고 분석 템플릿
- `pytest-fastapi-pattern` — admin-cli smoke test 의 pytest 호환 형태
