# bash-cli-best-practices

bash로 운영 CLI를 짤 때의 검증된 8 패턴. GEM-LLM의 `supervisor.sh`/`admin-cli.sh`/`health-monitor.sh`에서 통과한 조합을 일반화.

## 사용 시점

- "bash cli", "운영 자동화 스크립트", "subcommand 라우터"
- "rm -rf 금지", "mv to _trash", "안전한 삭제"
- "set -euo pipefail", "PID 파일", "setsid nohup"
- "curl 헬스체크", "bash sqlite SQL injection"

## 설치

```bash
./install.sh bash-cli-best-practices
```

8 패턴(set -e / sub-command / .env 우선순위 / mv to _trash / Python ?-bind / PID + kill -0 / curl 폴링 / setsid nohup) 본문은 [SKILL.md](SKILL.md). 표준 스켈레톤은 [templates/cli-skeleton.sh.template](templates/cli-skeleton.sh.template).
