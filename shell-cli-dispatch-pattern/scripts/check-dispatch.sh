#!/bin/bash
# dispatch 패턴 위반 정적 검출 (휴리스틱).
# case "$cmd" in ... ) 또는 case "$1" in ... ) 블록 안의 분기에
# `"$@"` 가 빠진 라인을 violation 으로 보고.
#
# Usage:
#   bash check-dispatch.sh admin-cli.sh
# Exit:
#   0 = OK, 1 = violations found, 2 = usage error

set -euo pipefail

FILE="${1:-}"
[ -z "$FILE" ] && { echo "Usage: $0 <script.sh>" >&2; exit 2; }
[ ! -f "$FILE" ] && { echo "File not found: $FILE" >&2; exit 2; }

errors=0
in_dispatch_case=0
lineno=0

while IFS= read -r line; do
  lineno=$((lineno+1))

  # case "$cmd" in / case "$1" in 진입 시 dispatch 모드 ON
  if echo "$line" | grep -qE '^\s*case\s+"\$(cmd|1)"\s+in' ; then
    in_dispatch_case=1
    continue
  fi

  if [ "$in_dispatch_case" -eq 1 ]; then
    # esac 만나면 모드 OFF
    if echo "$line" | grep -qE '^\s*esac\s*$' ; then
      in_dispatch_case=0
      continue
    fi

    # 분기 라인: word) ... ;;
    # -h|--help, *), -*) 같은 메타 분기는 제외 (글자로 시작하는 sub-command 만 검사)
    if echo "$line" | grep -qE '^\s*[a-z][a-z0-9_-]*\)' ; then
      if ! echo "$line" | grep -qE '"\$@"' ; then
        echo "  [$FILE:$lineno] $line" >&2
        echo "    -> \"\$@\" forward 누락 (silent 옵션 무시 위험)" >&2
        errors=$((errors+1))
      fi
    fi
  fi
done < "$FILE"

if [ "$errors" -eq 0 ]; then
  echo "OK $FILE: dispatch pattern clean"
  exit 0
else
  echo "FAIL $FILE: $errors violation(s)" >&2
  exit 1
fi
