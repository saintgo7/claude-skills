# Claude Code Skills

Curated collection of Claude Code skills — bilingual research/code projects, LLM serving infrastructure, exam operations, technical book authoring.

> Battle-tested in [GEM-LLM](https://github.com/saintgo7/gem-llm) (Qwen Coder dual-model coding assistant on 8×B200, ~56h autonomous operation, 21 production cases) and operational research projects.

**v0.8.5** — 57 entries, atomic commit hook + CI 검증, install.sh sparse checkout.

## 카탈로그 분포

| 카테고리 | 개수 | 비고 |
|---|---|---|
| 메타 (skill 작성/카탈로그 자체) | 3 | claude-code-skill-authoring 등 |
| 운영 (supervisor / cutover / migration) | 5 | postgres-migration-from-sqlite, blue-green-deployment 등 |
| 패턴 (재사용 가능 일반 패턴) | ~28 | fastapi-async-patterns, multi-agent-autonomous-loop, html-static-dashboard, pod-process-autostart, cloudflare-tunnel-ssh-access, playbook-authoring 등 |
| 인프라 (vLLM / Cloudflare / k8s) | 5 | vllm-bootstrap, cloudflare-tunnel-setup, k8s-pod-autostart 등 |
| 저작 (한/영 책 + 논문 + 블로그) | 3 | bilingual-book-authoring, korean-tech-blog-authoring 등 |
| **gem-llm 직접 운영** | **11** | gem-llm-overview / -supervisor / -admin-cli / -load-test / -troubleshooting / -cli-client / -vllm-debug / -gateway-debug / -deploy-vllm / -test-inference / -build-docs |
| 명령 (slash command) | 1 | `commands/searcam-book.md` |
| 시험 운영 (skill) | 1 | exam-system |

## Skill Catalog

| Skill | Type | Description |
|-------|------|-------------|
| [`project-bootstrap`](project-bootstrap/) | skill | bilingual research/code 프로젝트 한 번에 부트스트랩 (GitHub + Cloudflare + 한/영 책 + 한/영 논문 + Pandoc 빌드 파이프라인) |
| [`pandoc-bilingual-build`](pandoc-bilingual-build/) | skill | 기존 프로젝트에 한/영 Pandoc 빌드 파이프라인 추가 |
| [`multi-agent-orchestrator`](multi-agent-orchestrator/) | skill | 대량 작업 8+ 에이전트 병렬 디스패치 패턴 |
| [`multi-agent-autonomous-loop-pattern`](multi-agent-autonomous-loop-pattern/) | skill | 멀티 에이전트 자율 루프 (55h 검증 패턴) |
| [`bilingual-book-authoring`](bilingual-book-authoring/) | skill | 한/영 동시 책 저작 워크플로 (~1000p 검증) |
| [`korean-tech-blog-authoring`](korean-tech-blog-authoring/) | skill | 한국어 기술 블로그 저작 |
| [`mermaid-diagram-authoring`](mermaid-diagram-authoring/) | skill | Mermaid 다이어그램 카탈로그 + SVG 빌드 |
| [`claude-code-skill-authoring`](claude-code-skill-authoring/) | skill | skill 자체 작성 메타 |
| [`cloudflare-tunnel-setup`](cloudflare-tunnel-setup/) | skill | Cloudflare Tunnel 셋업 + SSH ProxyCommand |
| [`cloudflare-tunnel-ssh-access-pattern`](cloudflare-tunnel-ssh-access-pattern/) | skill | SSH via Cloudflare Tunnel (ProxyCommand, no-public-IP) |
| [`pod-process-autostart-pattern`](pod-process-autostart-pattern/) | skill | K8s pod / systemd-less idempotent autostart |
| [`playbook-authoring-pattern`](playbook-authoring-pattern/) | skill | 4-tuple([목적][명령][기대출력][실패복구]) 절차서 작성 |
| [`vllm-bootstrap`](vllm-bootstrap/) | skill | vLLM 처음부터 부팅 가이드 (13 실패 패턴) |
| [`vllm-tool-calling`](vllm-tool-calling/) | skill | vLLM tool-call-parser 운영 |
| [`llm-serving-performance-tuning`](llm-serving-performance-tuning/) | skill | LLM 서빙 성능 튜닝 (TP/MoE/quantization) |
| [`llm-eval-multi-model`](llm-eval-multi-model/) | skill | 여러 LLM 동시 평가/비교 |
| [`multi-llm-routing-pattern`](multi-llm-routing-pattern/) | skill | 모델 라우팅 패턴 |
| [`k8s-pod-autostart`](k8s-pod-autostart/) | skill | K8s pod 자동 시작 (systemd 없이) |
| [`k8s-cron-alternatives`](k8s-cron-alternatives/) | skill | K8s cron 대체 패턴 |
| [`fastapi-gateway-pattern`](fastapi-gateway-pattern/) | skill | FastAPI OpenAI 호환 LLM 게이트웨이 |
| [`fastapi-async-patterns`](fastapi-async-patterns/) | skill | FastAPI async 패턴 |
| [`pytest-fastapi-pattern`](pytest-fastapi-pattern/) | skill | pytest + FastAPI 통합 테스트 |
| [`api-contract-testing-pattern`](api-contract-testing-pattern/) | skill | FastAPI contract test 일반화 |
| [`api-route-consistency-pattern`](api-route-consistency-pattern/) | skill | API route prefix 일관성 (case 20) |
| [`api-key-lifecycle-pattern`](api-key-lifecycle-pattern/) | skill | API key 발급/회수/순환 |
| [`quota-rate-limit-pattern`](quota-rate-limit-pattern/) | skill | 3계층 quota (RPM + Semaphore + DB daily) |
| [`bulk-user-onboarding-pattern`](bulk-user-onboarding-pattern/) | skill | bulk 사용자 등록 (counter 개선 case 19) |
| [`concurrent-load-testing-pattern`](concurrent-load-testing-pattern/) | skill | 다중 사용자 부하 테스트 (locust + asyncio) |
| [`sqlite-wal-safe-ops`](sqlite-wal-safe-ops/) | skill | SQLite WAL 운영 함정 |
| [`postgres-migration-from-sqlite`](postgres-migration-from-sqlite/) | skill | SQLite → PostgreSQL 마이그레이션 |
| [`prometheus-fastapi-metrics`](prometheus-fastapi-metrics/) | skill | Prometheus + FastAPI 메트릭 |
| [`observability-bundle`](observability-bundle/) | skill | 관측 번들 (메트릭/로그/대시보드) |
| [`html-static-dashboard-pattern`](html-static-dashboard-pattern/) | skill | 정적 HTML 통합 대시보드 |
| [`production-postmortem-pattern`](production-postmortem-pattern/) | skill | 7-section blameless postmortem |
| [`shell-cli-dispatch-pattern`](shell-cli-dispatch-pattern/) | skill | bash sub-command dispatcher |
| [`bash-cli-best-practices`](bash-cli-best-practices/) | skill | bash CLI 모범 사례 |
| [`env-isolation-pattern`](env-isolation-pattern/) | skill | venv/conda 격리 (cutover 검증) |
| [`dependency-vulnerability-fix`](dependency-vulnerability-fix/) | skill | pip-audit + CVE watcher |
| [`blue-green-deployment-pattern`](blue-green-deployment-pattern/) | skill | blue/green 배포 |
| [`deployment-checklist`](deployment-checklist/) | skill | 배포 전 체크리스트 |
| [`cicd-github-actions-pattern`](cicd-github-actions-pattern/) | skill | GitHub Actions CI/CD |
| [`exam-system`](exam-system/) | skill | 온라인 시험 운영 플레이북 |
| [`searcam-book`](commands/) | command | SearCam 기술 서적 챕터 작성 슬래시 커맨드 |
| [`gem-llm-overview`](gem-llm-overview/) | skill | GEM-LLM 시스템 전체 구조 + 라우팅 |
| [`gem-llm-supervisor`](gem-llm-supervisor/) | skill | 전체 스택 start/stop/status/restart |
| [`gem-llm-admin-cli`](gem-llm-admin-cli/) | skill | 사용자/API key 관리 (CLI + REST) |
| [`gem-llm-load-test`](gem-llm-load-test/) | skill | locust + asyncio 부하 테스트 |
| [`gem-llm-troubleshooting`](gem-llm-troubleshooting/) | skill | 21 에러 사례 빠른 매핑 |
| [`gem-llm-cloudflare-tunnel`](gem-llm-cloudflare-tunnel/) | skill | DNS/터널 + master↔n1 SSH |
| [`gem-llm-cli-client`](gem-llm-cli-client/) | skill | gem-cli REPL/슬래시/tool calling |
| [`gem-llm-vllm-debug`](gem-llm-vllm-debug/) | skill | vLLM 의존성 매트릭스 + 부팅 실패 |
| [`gem-llm-gateway-debug`](gem-llm-gateway-debug/) | skill | FastAPI Gateway 500/401/429 |
| [`gem-llm-deploy-vllm`](gem-llm-deploy-vllm/) | skill | vLLM 단일 모델 launch |
| [`gem-llm-test-inference`](gem-llm-test-inference/) | skill | vLLM 추론 검증 |
| [`gem-llm-build-docs`](gem-llm-build-docs/) | skill | Pandoc + LaTeX 빌드 |
| [`gem-llm-review-prompt`](gem-llm-review-prompt/) | skill | 프롬프트 리뷰 |
| [`gem-llm-debug-mcp`](gem-llm-debug-mcp/) | skill | MCP 서버 디버깅 |

## 설치

### 선택 설치 (권장, sparse checkout)

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
- SPEC + ADR + master roadmap 골격
- 메모리 자동 등록

### LLM 서빙 운영 (GEM-LLM 스타일)

```bash
./install.sh gem-llm-overview gem-llm-supervisor gem-llm-troubleshooting
```

`bash scripts/supervisor.sh status`로 전체 스택 확인. 21 production case 매핑 + 100동접 sustained 부하 검증.

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

## CI 검증

- **frontmatter validator** — name + description 존재 / 1024자 제한
- **REGISTRY 일관성** — 모든 skill 디렉터리가 등록되어 있는지
- **atomic commit hook** — 한 커밋에 skill + REGISTRY + CHANGELOG 동기 추가
- **install.sh sparse checkout** — skill 단위 부분 설치 동작 검증

## Battle-tested 결정 (이 skills의 누적 자산)

- **Pandoc + XeTeX** (kotex/luatex 대신) — Noto Sans KR 직접 fontspec
- **vLLM 0.19.1** (0.20+ DeepGEMM 빌드 실패) + transformers 5.7.0 — 0.20 격리 venv 검증 완료, cutover 대기
- **rm -rf 절대 금지** — 격리(`_trash/`) 정책
- **SQLite WAL 파일 mv 금지** — DB 손상 방지 (PostgreSQL 마이그레이션 dry-run 검증 완료)
- **SQLAlchemy pool size 50+** — 50동접 시 100배 차이
- **Cloudflare access ssh** — HTTP-only 환경에서 SSH 우회
- **multi-agent 병렬화** — 책 ~1,000p 작성 시 8 에이전트 동시
- **atomic commit** — 한 커밋 = 한 단위, race 자동 해결 (case 21)

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

- [GEM-LLM 프로젝트](https://github.com/saintgo7/gem-llm) 운영에서 추출 + 일반화 — 55h 자율 운영, 21 production cases
- 다른 운영 프로젝트 (시험 시스템, 기술서적 작성 등) 패턴 누적

각 skill 본문은 한국어 위주 (저자 모국어). 영문 식별자 + 주석.
