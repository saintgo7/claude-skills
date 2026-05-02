# claude-skills

Claude Code skills collection — bilingual research/code projects, LLM serving infrastructure, and project bootstrapping.

> Battle-tested in [GEM-LLM](https://github.com/saintgo7/gem-llm) (Gemma → Qwen Coder dual-model coding assistant on 8×B200).

## 설치

```bash
git clone https://github.com/saintgo7/claude-skills.git
cp -r claude-skills/* ~/.claude/skills/
```

또는 심볼릭 링크 (자동 동기화):
```bash
ln -s "$(pwd)/claude-skills" ~/.claude/skills
```

## Skill 카탈로그

### 🚀 Bootstrap

| Skill | 사용 시점 |
|---|---|
| **`project-bootstrap`** | 새 bilingual research/code 프로젝트 한 번에 시작 (GitHub + Cloudflare + 한/영 책 + 한/영 논문 + Pandoc 빌드 파이프라인 + Mermaid + plan/specs/decisions) |

```bash
bash ~/.claude/skills/project-bootstrap/scripts/init-project.sh \
  <project-name> [domain]
```

자동 수행:
- GitHub `saintgo7/<name>` private repo 생성 + push
- Cloudflare `<domain>` DNS 라우팅 (master tunnel)
- 한/영 개발 책 골격 (~500p × 2, Pandoc + XeTeX)
- 한/영 연구개발 논문 템플릿 (KCI + IEEE/ACM)
- 40 Mermaid 다이어그램 카탈로그 + SVG 빌드
- 12 SPEC + 3 ADR + master roadmap 골격
- 메모리 자동 등록

### 📚 GEM-LLM 운영 (14 skills)

GEM-LLM 운영에서 추출한 일반화 가능한 skills:

| Skill | 역할 |
|---|---|
| `gem-llm-overview` | 전체 구조 + 다른 skill 라우팅 |
| `gem-llm-supervisor` | 전체 스택 start/stop/status/restart |
| `gem-llm-admin-cli` | 사용자/API key 관리 (CLI + REST) |
| `gem-llm-load-test` | locust + asyncio 다중 사용자 부하 |
| `gem-llm-troubleshooting` | 실전 13개 에러 사례 빠른 매핑 |
| `gem-llm-cloudflare-tunnel` | DNS/터널 운영 + master↔n1 SSH |
| `gem-llm-cli-client` | gem-cli REPL/슬래시/tool calling |
| `gem-llm-vllm-debug` | vLLM 의존성 매트릭스 + 부팅 실패 패턴 |
| `gem-llm-gateway-debug` | FastAPI Gateway 500/401/429 패턴 |
| `gem-llm-deploy-vllm` | vLLM 단일 모델 launch (구) |
| `gem-llm-test-inference` | 추론 검증 |
| `gem-llm-build-docs` | Pandoc + LaTeX 빌드 |
| `gem-llm-review-prompt` | 프롬프트 리뷰 |
| `gem-llm-debug-mcp` | MCP 서버 디버깅 |

## Skill 작성 형식

```
.claude/skills/<name>/
├── SKILL.md              # frontmatter (name, description) + 본문
├── scripts/              # 보조 셸 스크립트 (선택)
├── templates/            # 파일 템플릿 (선택)
└── CHECKLIST.md          # 체크리스트 (선택)
```

`SKILL.md` frontmatter:

```yaml
---
name: skill-name
description: 'When to invoke this skill. Trigger phrases: "...", "...", "...". Brief role description.'
---
```

description은 최대 1024자. 트리거 phrase를 명확히 — Claude Code가 이 description을 보고 자동 invocation 결정.

## 핵심 결정 (battle-tested)

이 skills는 다음 결정을 누적:

- **Pandoc + XeTeX** (kotex/luatex 대신) — Noto Sans KR 직접 fontspec
- **vLLM 0.19.1** (0.20+ DeepGEMM 빌드 실패) + transformers 5.7.0
- **rm -rf 절대 금지** — 격리(`_trash/`) 정책
- **SQLite WAL 파일 mv 금지** — DB 손상 case 13
- **SQLAlchemy pool size 50+** — 50동접 시 100배 차이 case 12
- **n1↔master cloudflared access ssh** — Cloudflare HTTP-only 우회
- **multi-agent 병렬화** — 책 ~1,000p 작성 시 8 에이전트 동시

## 의존성 (한 번만 설치)

```bash
sudo apt install -y texlive-xetex texlive-publishers texlive-lang-cjk \
  texlive-fonts-recommended fonts-noto-cjk fonts-noto-cjk-extra librsvg2-bin
sudo apt install -y libatk-bridge2.0-0 libatk1.0-0 libcups2 libdrm2 libgbm1 \
  libgtk-3-0 libnspr4 libnss3 libxcomposite1 libxdamage1 libxfixes3 \
  libxkbcommon0 libxrandr2 libpango-1.0-0 libcairo2 libasound2t64 libxshmfence1
npm install -g @mermaid-js/mermaid-cli
```

## 라이선스

MIT (개인 사용 자유, 상업 사용 가능, 인용 환영).

## 출처

[GEM-LLM 프로젝트](https://github.com/saintgo7/gem-llm) 운영에서 추출 + 일반화.

각 skill 본문은 한국어 위주 (저자 모국어). 영문 주석 + identifier.
