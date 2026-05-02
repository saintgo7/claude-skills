---
name: gem-llm-cli-client
description: 'gem-cli (Claude Code 스타일 터미널 클라이언트) 사용법 + 디버깅. 사용 시점 — "gem CLI", "gem login", "gem chat", "REPL", "슬래시 명령", "/cost", "/model 변경", "tool calling 안됨", "gem-cli 설치", "auto-run". 사용자 머신 또는 n1 둘 다 동일. config 파일은 ~/.config/gem-cli/config.json.'
---

# gem-llm-cli-client

## 설치 (사용자 머신)

```bash
# 옵션 A: 직접 git clone (사내 PyPI 미설정 상태)
git clone https://github.com/saintgo7/gem-llm.git
cd gem-llm
pip install -e src/cli

# 옵션 B: n1에 이미 설치됨
/home/jovyan/vllm-env/bin/gem version
# gem-cli 0.1.0
```

## 첫 사용

```bash
gem login
# Endpoint [https://llm.pamout.com]: 
# API key: gem_live_...  (관리자에서 받은 것)
# → ~/.config/gem-gem-cli/config.json 저장
```

또는 직접 config 작성:

```bash
mkdir -p ~/.config/gem-cli
cat > ~/.config/gem-cli/config.json << 'EOF'
{
  "endpoint": "https://llm.pamout.com",
  "api_key": "gem_live_...",
  "model": "qwen2.5-coder-32b",
  "auto_run": false
}
EOF
```

## REPL 시작

```bash
gem
# gem-cli — endpoint=https://llm.pamout.com  model=qwen2.5-coder-32b  auto_run=off
# Type '/help' for commands, '/exit' to quit.
gem> Hello, write a Python fizzbuzz
```

## 슬래시 명령

| | |
|---|---|
| `/help` | 전체 명령 |
| `/model qwen2.5-coder-32b` | Dense |
| `/model qwen3-coder-30b` | MoE |
| `/clear` | 대화 history 초기화 |
| `/cost` | 누적 토큰 + 평균 latency |
| `/history` | 최근 대화 |
| `/login` | API key 재설정 |
| `/auto on\|off` | bash 도구 자동 승인 |
| `/exit` (또는 `/quit`) | 종료 |

## Tool Calling

기본 활성화. 6 tool:
- `read_file(path)`, `write_file(path, content)`, `edit_file(path, old, new)`
- `bash(command)` — **사용자 승인 필요**
- `grep(pattern, path)`, `find_files(pattern, path)`

bash 위험 명령 차단 (rm -rf, mkfs, dd of=/dev/sd*, fork bomb, shutdown):

```python
# DANGEROUS_PATTERNS in src/cli/gem_cli/utils.py
- ^rm\s+(-rf?|--recursive --force) /
- ^mkfs\.
- ^dd .* of=/dev/sd.*
- ^shutdown
- :\(\):.* fork bomb
```

차단 시 `Refused: dangerous command` 응답.

`/auto on` 후에도 위험 명령은 차단 (보안).

## 비대화 (스크립트)

```bash
# 단발 호출
printf 'List 3 Python web frameworks\n/exit\n' | gem

# 또는 직접 API 호출 (CLI 우회)
curl -s -m 30 https://llm.pamout.com/v1/chat/completions \
  -H "Authorization: Bearer $GEM_LLM_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen2.5-coder-32b","messages":[{"role":"user","content":"hi"}],"max_tokens":50}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])"
```

## 환경변수

| | |
|---|---|
| `GEM_API_KEY` 또는 `GEM_CLI_API_KEY` | config 덮어씀 |
| `GEM_ENDPOINT` | endpoint URL |
| `GEM_CLI_CONFIG_HOME` | config 디렉토리 변경 (테스트용) |
| `GEM_CLI_DATA_HOME` | history DB 위치 |

## 트러블슈팅

| 증상 | 원인 |
|---|---|
| `No API key` exit 2 | config 또는 env 미설정 |
| `Connection refused` | endpoint Gateway 죽음, supervisor.sh status |
| 401 invalid_api_key | 키 회수됨 또는 오타 |
| 429 rate_limited | 60 RPM 초과 — 1분 대기 |
| 429 daily_token_limit | 50K 토큰 초과 — admin에 quota 증액 요청 |
| tool 응답 후 무한 loop | tool_use round 16회 hardcap (config로 변경 가능) |
| 한국어 부분 깨짐 | terminal locale UTF-8 확인 |

## 히스토리 DB

`~/.local/share/gem-cli/history.db` (SQLite). 시작/종료 시 자동 저장.

리셋: `mv ~/.local/share/gem-cli/history.db ~/.local/share/gem-cli/history.db.bak.$(date +%Y%m%d)`

## 모델 선택 가이드

- **qwen2.5-coder-32b (Dense)**: 더 깊은 추론, 복잡한 알고리즘, 긴 코드 리뷰
- **qwen3-coder-30b (MoE)**: 빠른 응답, 간단한 작업, tool calling

`/model` 으로 즉시 전환 (대화 history 유지).

## 관련 코드

- `src/cli/gem_cli/main.py` — Typer CLI 엔트리
- `src/cli/gem_cli/repl.py` — prompt_toolkit REPL
- `src/cli/gem_cli/tools/` — 6개 도구 구현
- `src/cli/gem_cli/utils.py` — 위험 명령 패턴
- 책 Part III ch.10 — gem-cli 구현 상세
