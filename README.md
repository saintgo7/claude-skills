# Claude Code Skills

Curated collection of Claude Code skills — bilingual research/code projects, LLM serving infrastructure, exam operations, technical book authoring.

> Battle-tested in [GEM-LLM](https://github.com/saintgo7/gem-llm) (Qwen Coder dual-model coding assistant on 8×B200) and operational research projects.

## Skill Catalog

| Skill | Type | Description |
|-------|------|-------------|
| [`project-bootstrap`](project-bootstrap/) | skill | bilingual research/code 프로젝트 한 번에 부트스트랩 (GitHub + Cloudflare + 한/영 책 + 한/영 논문 + Pandoc 빌드 파이프라인) |
| [`pandoc-bilingual-build`](pandoc-bilingual-build/) | skill | 기존 프로젝트에 한/영 Pandoc 빌드 파이프라인 추가 (project-bootstrap의 빌드만 분리) |
| [`multi-agent-orchestrator`](multi-agent-orchestrator/) | skill | 대량 작업 (책 ~1000p, 코드 ~12K LOC) 8+ 에이전트 병렬 디스패치 패턴 |
| [`exam-system`](exam-system/) | skill | 온라인 시험 운영 플레이북 (모니터링·대응·사후 통계) |
| [`searcam-book`](commands/) | command | SearCam 기술 서적 챕터 작성 슬래시 커맨드 |
| [`gem-llm-overview`](gem-llm-overview/) | skill | GEM-LLM 시스템 전체 구조 + 다른 skill 라우팅 |
| [`gem-llm-supervisor`](gem-llm-supervisor/) | skill | 전체 스택 start/stop/status/restart |
| [`gem-llm-admin-cli`](gem-llm-admin-cli/) | skill | 사용자/API key 관리 (CLI + REST) |
| [`gem-llm-load-test`](gem-llm-load-test/) | skill | locust + asyncio 다중 사용자 부하 테스트 |
| [`gem-llm-troubleshooting`](gem-llm-troubleshooting/) | skill | 실전 13개 에러 사례 빠른 매핑 |
| [`gem-llm-cloudflare-tunnel`](gem-llm-cloudflare-tunnel/) | skill | DNS/터널 운영 + master↔n1 SSH |
| [`gem-llm-cli-client`](gem-llm-cli-client/) | skill | gem-cli REPL/슬래시/tool calling |
| [`gem-llm-vllm-debug`](gem-llm-vllm-debug/) | skill | vLLM 의존성 매트릭스 + 부팅 실패 패턴 |
| [`gem-llm-gateway-debug`](gem-llm-gateway-debug/) | skill | FastAPI Gateway 500/401/429 패턴 |
| [`gem-llm-deploy-vllm`](gem-llm-deploy-vllm/) | skill | vLLM 단일 모델 launch |
| [`gem-llm-test-inference`](gem-llm-test-inference/) | skill | vLLM 추론 검증 |
| [`gem-llm-build-docs`](gem-llm-build-docs/) | skill | Pandoc + LaTeX 빌드 (책/매뉴얼/논문) |
| [`gem-llm-review-prompt`](gem-llm-review-prompt/) | skill | 프롬프트 리뷰 |
| [`gem-llm-debug-mcp`](gem-llm-debug-mcp/) | skill | MCP 서버 디버깅 |

## 설치

### 선택 설치 (권장)

```bash
# 1. 저장소 clone
git clone --depth=1 https://github.com/saintgo7/claude-skills.git
cd claude-skills

# 2. 사용 가능한 skill 목록 확인
./install.sh --list

# 3. 원하는 skill만 설치 (sparse checkout)
./install.sh project-bootstrap
./install.sh gem-llm-overview
./install.sh exam-system

# 4. 삭제
./install.sh --remove gem-llm-overview
```

Claude Code 재시작 후 사용 가능.

### 전체 설치

```bash
git clone https://github.com/saintgo7/claude-skills.git
cp -r claude-skills/gem-llm-* ~/.claude/skills/
cp -r claude-skills/project-bootstrap ~/.claude/skills/
cp -r claude-skills/exam-system ~/.claude/skills/
mkdir -p ~/.claude/commands
cp claude-skills/commands/*.md ~/.claude/commands/
```

## 핵심 시나리오

### 새 bilingual 프로젝트 시작

```bash
./install.sh project-bootstrap
bash ~/.claude/skills/project-bootstrap/scripts/init-project.sh \
  fishing-llm fishing.pamout.com
```

자동 수행:
- GitHub `saintgo7/fishing-llm` Private repo 생성 + push
- Cloudflare `fishing.pamout.com` DNS 라우팅 (master tunnel)
- 한/영 개발 책 골격 (~500p × 2, Pandoc + XeTeX)
- 한/영 연구개발 논문 템플릿 (KCI + IEEE/ACM)
- 40 Mermaid 다이어그램 카탈로그 + SVG 빌드 파이프라인
- 12 SPEC + 3 ADR + master roadmap 골격
- 메모리 자동 등록

### LLM 서빙 운영 (GEM-LLM 스타일)

```bash
./install.sh gem-llm-overview gem-llm-supervisor gem-llm-troubleshooting
```

`bash scripts/supervisor.sh status`로 전체 스택 확인. 13 케이스 troubleshooting + 50동접 부하 테스트 검증.

### 시험 운영

```bash
./install.sh exam-system
```

## Skill 작성 형식

```
<skill-name>/
├── SKILL.md              # frontmatter (name, description) + 본문
├── scripts/              # 보조 셸 스크립트 (선택)
├── templates/            # 파일 템플릿 (선택)
└── CHECKLIST.md          # 체크리스트 (선택)
```

`SKILL.md` frontmatter:

```yaml
---
name: skill-name
description: 'When to invoke. Trigger phrases: "...", "...". Brief role.'
---
```

description은 최대 1024자. 트리거 phrase를 명확히 — Claude Code가 이 description을 보고 자동 invocation 결정.

## Battle-tested 결정 (이 skills의 누적 자산)

- **Pandoc + XeTeX** (kotex/luatex 대신) — Noto Sans KR 직접 fontspec
- **vLLM 0.19.1** (0.20+ DeepGEMM 빌드 실패) + transformers 5.7.0
- **rm -rf 절대 금지** — 격리(`_trash/`) 정책
- **SQLite WAL 파일 mv 금지** — DB 손상 방지
- **SQLAlchemy pool size 50+** — 50동접 시 100배 차이
- **Cloudflare access ssh** — HTTP-only 환경에서 SSH 우회
- **multi-agent 병렬화** — 책 ~1,000p 작성 시 8 에이전트 동시

## 의존성 (Pandoc/Mermaid 사용 시 한 번만)

```bash
sudo apt install -y texlive-xetex texlive-publishers texlive-lang-cjk \
  texlive-fonts-recommended fonts-noto-cjk fonts-noto-cjk-extra librsvg2-bin
sudo apt install -y libatk-bridge2.0-0 libatk1.0-0 libcups2 libdrm2 libgbm1 \
  libgtk-3-0 libnspr4 libnss3 libxcomposite1 libxdamage1 libxfixes3 \
  libxkbcommon0 libxrandr2 libpango-1.0-0 libcairo2 libasound2t64 libxshmfence1
npm install -g @mermaid-js/mermaid-cli
```

## 라이선스

MIT — 자유 사용/수정/배포. 인용 환영.

## 출처

- [GEM-LLM 프로젝트](https://github.com/saintgo7/gem-llm) 운영에서 추출 + 일반화
- 다른 운영 프로젝트 (시험 시스템, 기술서적 작성 등) 패턴 누적

각 skill 본문은 한국어 위주 (저자 모국어). 영문 식별자 + 주석.
