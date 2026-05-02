---
name: gem-llm-overview
description: GEM-LLM 프로젝트 전체 구조와 컴포넌트 위치를 빠르게 파악. 사용 시점 — "gem-llm이 뭐야", "전체 구성", "어디서 시작해", "프로젝트 구조", "포트 매핑", "어떤 모델 사용", "llm.pamout.com 어디로 가", "gem-llm overview". 시스템에 새로 합류하거나 어떤 컴포넌트가 어디 있는지 빠르게 확인할 때 사용. 깊은 디버깅은 다른 gem-llm-* skill로.
---

# gem-llm-overview

GEM-LLM = Gemma → Qwen Coder로 전환된 **Qwen2.5-Coder-32B + Qwen3-Coder-30B-A3B 듀얼 서빙** 코딩 어시스턴트 시스템.

## 한 그림

```
[curl https://llm.pamout.com] 
  → [Cloudflare Tunnel (master 노드 통과)]
  → [n1 cloudflared (port 8080 forward)]
  → [Gateway :8080 (FastAPI, API key 인증, quota, rate-limit)]
  → [vLLM :8001 Dense (Qwen2.5-Coder-32B, GPU 0-3, TP=4)]
  → [vLLM :8002 MoE (Qwen3-Coder-30B-A3B, GPU 4-7, TP=4)]
```

## 포트 매핑 (n1 = wku-vs-01-0)

| 포트 | 서비스 | 모델 / 역할 |
|---|---|---|
| 8001 | vLLM Dense | Qwen2.5-Coder-32B-Instruct (GPU 0-3, TP=4) |
| 8002 | vLLM MoE | Qwen3-Coder-30B-A3B-Instruct (GPU 4-7, TP=4) |
| 8080 | Gateway | OpenAI 호환 + 인증 + quota |
| 8090 | Admin UI | FastAPI + Jinja2 + HTMX |
| 외부 | https://llm.pamout.com | Cloudflare Tunnel → 8080 |

## 디렉토리

`/home/jovyan/gem-llm/` (datavol-1 심볼릭)
- `src/` — vllm-serve, gateway, cli, admin-ui, common
- `docs/` — book-{ko,en} (~576p 각), manual-{ko,en} (~150p 각), paper-{ko,en} (KCI/IEEE), diagrams/ (40 SVG)
- `plan/` — 12 SPEC + 3 ADR + roadmap
- `tests/` — integration, load (locust + multi-user-bench), smoke
- `scripts/` — supervisor.sh, admin-cli.sh, build-docs.sh, build-diagrams.sh
- `_logs/` — 운영 로그
- `_data/` — gateway.db (SQLite, gitignore)
- `_trash/` — destructive 대신 격리 보존

## 주요 명령

```bash
bash scripts/supervisor.sh status        # 전체 스택 상태
bash scripts/supervisor.sh start         # 시작 (vLLM 로딩 5분)
bash scripts/admin-cli.sh add-user X X@y pro
bash scripts/admin-cli.sh issue-key <user_id>
make book-ko book-en                     # PDF 빌드
locust -f tests/load/locustfile.py       # 부하 테스트
```

## 외부 노출

- **llm.pamout.com** — n1 cloudflared tunnel `10f3cb24-...`로 라우팅
- master tunnel (e9781f73-...) → paper.pamout.com (code-server)는 별개
- DNS 라우팅 추가는 master에서 `cloudflared tunnel route dns ... llm.pamout.com`

## 알려진 함정

- **vLLM 0.19.1 사용** (0.20.0 DeepGEMM 빌드 실패). transformers 5.7.0, mistral_common 최신 필수.
- **SQLite WAL 파일 mv 금지** (case 13 — DB 손상). `.gitignore` 추가는 OK.
- **Gemma 4 미사용** (case 11 — `layer_scalar` weight 호환 깨짐). Qwen Coder 듀얼이 현재 운영.
- **n1↔master SSH는 양방향** (~/.ssh/config의 `Host master`/`Host n3` cloudflared access ssh).
- **rm -rf 절대 금지** (feedback memory). 삭제 대신 `_trash/<날짜>/` 로 mv.

## 깊은 디버깅 → 다른 skill

- vLLM 모델 로딩/충돌 → `gem-llm-deploy-vllm`
- 사용자/키 관리 → `gem-llm-admin-cli`
- 부하 테스트 → `gem-llm-load-test`
- 빌드 (PDF/SVG/논문) → `gem-llm-build-docs`
- CLI 사용 → `gem-llm-cli-client`
- 외부 라우팅 → `gem-llm-cloudflare-tunnel`
- 에러 사례 → `gem-llm-troubleshooting`
- 추론 검증 → `gem-llm-test-inference`
- 프롬프트 리뷰 → `gem-llm-review-prompt`
- MCP 디버깅 → `gem-llm-debug-mcp`

## GitHub

- Repo: `saintgo7/gem-llm` (Private)
- 9 commits at last sync
- credentials store: `~/.git-credentials` (mode 600)

## 메모리 참조

- `project_gem_llm.md` (정적 사실)
- `project_gem_llm_runtime.md` (가동 상태, 버전, 함정)
