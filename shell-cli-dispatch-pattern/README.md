# shell-cli-dispatch-pattern

Bash CLI sub-command dispatcher 정형 패턴 (`shift; cmd_xxx "$@"`).

`case "$1" in list) cmd_list ;;` 처럼 `"$@"` 를 빠뜨리면 옵션이 silent하게
무시되는 버그가 발생 (gem-llm case 19). shellcheck + dispatch lint + 회귀
테스트 3중 디펜스로 막는 표준 패턴.

## 구성

- `SKILL.md` — 11 섹션 가이드 (안티패턴 → 정형 → 옵션 파서 → 테스트)
- `templates/dispatch.sh.template` — 복사용 boilerplate
- `scripts/check-dispatch.sh` — dispatch 패턴 위반 정적 검출

## 설치

```bash
./install.sh shell-cli-dispatch-pattern
```
