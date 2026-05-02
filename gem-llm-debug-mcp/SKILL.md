---
name: gem-llm-debug-mcp
description: Diagnose Model Context Protocol (MCP) server issues for the GEM-LLM Claude Code setup — connection failures, missing tools, permission prompts, env var/token problems, npx package resolution, log inspection. Use when the user says "MCP 안 떠", "MCP 디버깅", "MCP 서버 연결 실패", "github mcp 토큰 에러", "filesystem mcp 권한", "firecrawl mcp 안됨", "mermaid mcp 동작 안함", "mcp 도구 안 보여", "mcp 로그 어디". Inspects ~/.claude/settings.json mcpServers config, runs npx <pkg> --help to check resolution, validates env vars, and tails Claude Code MCP stderr.
---

# gem-llm-debug-mcp

Claude Code 의 MCP (Model Context Protocol) 서버 문제 진단 스킬.

## When to use

- "MCP 안 떠", "MCP 도구가 목록에 없어"
- "github mcp 인증 실패"
- "filesystem mcp 권한 거부"
- "firecrawl/mermaid/pandoc mcp 동작 안 함"
- "npx <pkg> 못 찾음"
- "MCP 로그 어디"

## Step 1 — settings.json 검증

```bash
python -c "import json; d=json.load(open('/home/jovyan/.claude/settings.json')); print(json.dumps(d.get('mcpServers',{}), indent=2, ensure_ascii=False))"
```

확인 포인트:
- 각 서버에 `command`, `args`(있다면), `env`(필요시) 존재
- env 의 토큰이 placeholder(`<...>`)면 진짜 값으로 교체 필요
- JSON 유효한지 (`json.load` 에러 없어야)

## Step 2 — 패키지 resolution

각 MCP 서버 `command`/`args[0]`을 추출해 npx로 dry run:
```bash
npx -y @modelcontextprotocol/server-github --help 2>&1 | head -20
npx -y @modelcontextprotocol/server-filesystem --help 2>&1 | head -20
npx -y firecrawl-mcp --help 2>&1 | head -20
npx -y mcp-mermaid --help 2>&1 | head -20
npx -y mcp-pandoc --help 2>&1 | head -20
```
패키지를 못 찾으면 정확한 npm 이름을 `npm search` 또는 npm registry 로 확인.

## Step 3 — 환경변수

```bash
env | grep -iE 'GITHUB|FIRECRAWL|ANTHROPIC|HF_' | sed 's/=.*/=***/'
```
민감 토큰은 마스킹해서 사용자에게 보고. 실제 값을 화면에 출력하지 말 것.

## Step 4 — Claude Code MCP 로그

Claude Code 는 보통 `~/.cache/claude-code/` 또는 `~/.claude/logs/` 에 로그를 남김. 위치 자동 탐색:
```bash
find ~/.claude ~/.cache/claude-code ~/.local/share/claude-code -maxdepth 4 -name '*.log' -o -name 'mcp*' 2>/dev/null | head
```
최근 stderr:
```bash
tail -n 200 <found-log>
```

## Step 5 — 증상별 분기

| 증상 | 의심 | 조치 |
|---|---|---|
| MCP 서버가 도구 목록에 없음 | settings.json 미반영 | Claude Code 재시작 |
| `EACCES` / 권한 거부 | filesystem 경로 화이트리스트 | `args` 의 허용 디렉토리 확인 |
| 401/403 (github) | PAT 만료/스코프 부족 | `repo`, `read:org` 스코프 재발급 |
| `npx` hang | 첫 다운로드 중 | 1회 수동 `npx -y <pkg>` |
| stdout JSON 파싱 에러 | 서버가 stderr 대신 stdout에 로그 | 해당 서버 버그/이슈 검색 |

## Step 6 — 수정 후 재검증

settings.json 변경 시 항상 백업 먼저:
```bash
cp ~/.claude/settings.json /home/jovyan/gem-llm/_trash/settings-backup-$(date +%Y%m%d-%H%M%S).json
```
JSON 유효성:
```bash
python -c "import json; json.load(open('/home/jovyan/.claude/settings.json'))" && echo OK
```

## Safety

- 토큰/PAT를 transcript에 절대 기록하지 말 것
- `~/.claude/settings.json` 의 `hooks` (argos hook 포함) 와 다른 키 보존 — `mcpServers` 만 만지기
- `rm` 금지, 항상 `mv` 또는 `cp` 백업
