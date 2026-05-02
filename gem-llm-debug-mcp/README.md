# gem-llm-debug-mcp

Claude Code의 MCP (Model Context Protocol) 서버 문제 진단 스킬.

## 사용 시점

- "MCP 안 떠", "MCP 디버깅"
- "MCP 서버 연결 실패", "github mcp 토큰 에러"
- "filesystem mcp 권한", "firecrawl/mermaid mcp 안됨"
- "mcp 도구 안 보여", "mcp 로그 어디"

## 설치

```bash
./install.sh gem-llm-debug-mcp
```

`~/.claude/settings.json` mcpServers 검사, npx 패키지 해결, env 검증, stderr 추적 절차는 [SKILL.md](SKILL.md) 참조.
