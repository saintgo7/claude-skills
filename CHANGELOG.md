# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

(현재 main 브랜치에 머지되었으나 아직 태깅되지 않은 변경사항이 여기에 누적됩니다.)

## [0.7.0] - 2026-05-02

[`9290bc3`] feat: observability-bundle skill (Prometheus + Loki + OTel + Sentry 3 pillar 통합)
[`c13c998`] feat: dependency-vulnerability-fix skill (pip-audit 4단계 안전 fix)

### Added
- `dependency-vulnerability-fix` skill — pip-audit 발견 취약점 **안전 fix 4단계** 패턴
  (스캔 → 분류 → patch-only 안전 업그레이드 → 회귀 검증;
  vLLM/PyTorch 같은 큰 의존성을 깨뜨리지 않으면서 patch 단위만 정밀 업그레이드;
  GEM-LLM `vllm-env` 27 vulnerabilities fix 작업에서 도출,
  CVE 분류 (critical / high / medium), patch-version delta 정책,
  pin 충돌 회피 (transformers/torch/flashinfer 매트릭스 보존),
  pip-audit CI 통합 권고, lockfile 회귀 검증, supply chain 위험 노트;
  scripts/ 도우미 — 회귀 패키지 detect, lockfile diff)
- `observability-bundle` skill — FastAPI 통합 **관측성 3 pillar** (metrics / logs / traces) + Sentry
  (`prometheus-fastapi-metrics` 가 metrics 1 pillar 만 다룬다면, 이 skill 은 logs/traces 까지 확장하고
  4 도구를 한 스택으로 묶는다 — Prometheus + Loki + OpenTelemetry + Sentry;
  templates/ — Sentry SDK 통합, OTel FastAPI/SQLAlchemy/httpx instrumentation,
  Loki structured logging, Grafana datasource provisioning,
  trace-id ↔ log line correlation 패턴, sampling 전략, error budget 가이드;
  GEM-LLM Go-Live 4.6 (Sentry) / 4.7 (OTel) / 4.8 (로그 집계) P2-P3 권고 충족 가이드)

### Changed
- `install.sh` REGISTRY **36 → 38 entries** (37 skills + 1 command) — 신규 2개 추가

## [0.6.0] - 2026-05-02

[`5c5a151`] feat: vllm-tool-calling skill (3단계 디펜스 일반화)
[`23064a8`] feat: fastapi-async-patterns skill (6 검증된 async 패턴)
[`304d03b`] feat(prometheus-fastapi-metrics): add Grafana dashboard template

### Added
- `vllm-tool-calling` skill — vLLM tool calling 3-계층 디펜스 운영 가이드
  (server parser + model weight + client fallback 패턴 일반화; 7 parser 매핑,
  5개 실패 패턴 — case 15/16/17 일반화, stream chunk-boundary 디버깅 워크플로,
  stream buffer hold, telemetry, 운영 체크리스트;
  templates/fallback-parser.py.template — hermes/qwen3/bare-JSON 3패턴 추출,
  정규식 precompile, 이미 정상 `tool_calls`이면 즉시 pass-through;
  templates/smoke-test.sh.template — non-stream + stream + leak 검증, curl + jq only)
- `fastapi-async-patterns` skill — FastAPI + asyncio + httpx + SQLAlchemy async 검증 패턴
  (GEM-LLM Gateway 50~200 동접 통과; streaming proxy / lifespan / DI / Semaphore /
  async DB / background task 6 패턴, 함정 종합, 시작 체크리스트;
  templates/lifespan.py.template, templates/streaming-proxy.py.template)
- `prometheus-fastapi-metrics` skill에 Grafana dashboard 템플릿 추가
  (templates/grafana-dashboard.json.template — 8-panel starter dashboard,
  Grafana 10.x schemaVersion 38, `${DS_PROMETHEUS}` 변수, `<service>` placeholder;
  SKILL.md "Grafana 대시보드 시작점" 섹션 + 8 PromQL one-liners — requests /
  chat completions / latency p50/p95/p99 / tokens / active gauge / quota rejections /
  5xx ratio / GPU util)

### Changed
- `install.sh` REGISTRY **29 → 32 entries** (31 skills + 1 command) — 신규 2개 추가

## [0.5.0] - 2026-05-02

[`38cff97`] docs: add missing README.md for bilingual-book-authoring skill
[`e959472`] fix(install): show ERROR for unknown skill, warn on duplicate install
[`5af72df`] feat: postgres-migration-from-sqlite skill (case 14 long-term fix)
[`046f44b`] feat: prometheus-fastapi-metrics skill (Counter/Histogram/Gauge 3-위치 패턴)
[`5bb29cc`] feat: quota-rate-limit-pattern skill (3-layer rate limiting)

### Added
- `prometheus-fastapi-metrics` skill — FastAPI 애플리케이션 Prometheus 커스텀 메트릭 패턴
  (Counter / Histogram / Gauge 3종, 미들웨어 + 핸들러 + 백그라운드 3-위치 패턴,
  default registry 충돌 회피, label cardinality 가이드, Grafana 대시보드 예시;
  GEM-LLM gateway 6 메트릭 — requests, tokens, latency 검증)
- `quota-rate-limit-pattern` skill — 3-layer rate limiting (per-key RPM / daily / monthly)
  (slowapi + 자체 미들웨어 조합, 429 응답 표준 헤더 `Retry-After` / `X-RateLimit-*`,
  fail-open vs fail-closed, SQLite/Redis 백엔드 비교, 분산 환경 권장사항)
- `postgres-migration-from-sqlite` skill — SQLite → PostgreSQL 장기 마이그레이션 가이드
  (case 14 SQLite write-lock 200 동접 한계 후속 처리, alembic 스키마 이관,
  connection pool 튜닝 차이, JSONB / `INSERT ... ON CONFLICT` 패턴, 백업/롤백 전략)

### Changed
- `install.sh` REGISTRY 29 entries (28 skills + 1 command) — 신규 3개 추가

### Fixed
- `install.sh` silent failure — 알려지지 않은 skill 이름 인자에 대해 조용히 종료하던 문제
  → `ERROR: unknown skill '<name>'` 메시지 표시 후 exit 1, 이미 설치된 skill에 대해서는 warn
- `bilingual-book-authoring` skill에 `README.md` 누락 → GitHub 폴더 진입 시 빈 화면이던 것을
  설명 + 사용 트리거 + SKILL.md 링크가 포함된 README로 교체

## [0.4.0] - 2026-05-02

[`5447aea`] feat: 3 new skills (vllm-bootstrap, bilingual-book-authoring, k8s-pod-autostart) + 22 READMEs
[`(this commit)`] feat: llm-eval-multi-model skill + CHANGELOG v0.4.0

### Added
- `vllm-bootstrap` skill — vLLM 처음부터 부팅 가이드
  (의존성 매트릭스 vllm 0.19.1 / transformers 5.7 / flashinfer 0.6.8.post1,
  TP=1/2/4/8 선택, tool-call-parser 매핑 6종, 부팅 실패 13개 패턴,
  setsid + nohup launch 표준; gem-llm-vllm-debug 일반화)
- `bilingual-book-authoring` skill — 한/영 동시 책 저작 워크플로
  (~1000p 검증; OUTLINE mirror, 다이어그램 공유, Part 멀티 에이전트 분산,
  에러 사례 수집 패턴, 한/영 미세 차이 처리 — 영어 idiom vs 한국어 자연스러움)
- `k8s-pod-autostart` skill — K8s pod / 컨테이너 환경 자동 시작 (systemd 없이)
  (s6-overlay cont-init, .bashrc one-shot guard, watchdog 패턴,
  livenessProbe + restartPolicy 4가지 패턴 비교)
- `llm-eval-multi-model` skill — 여러 LLM 동시 평가/비교
  (asyncio.gather 병렬 호출, TTFT/TPOT/p50/p95/p99 메트릭, LLM-as-judge,
  tool calling 정확도 채점, 한국어/영어 응답 품질 비교; Dense vs MoE 사례)
- 22개 skill에 개별 `README.md` 추가 — GitHub 노출 시 각 skill 폴더에서 바로 읽기
  (`./install.sh <name>` 명령, 사용 시점 트리거 phrase, SKILL.md 링크)
- GitHub Actions CI status 체크 통합

### Changed
- `install.sh` REGISTRY 26 entries (25 skills + 1 command)
- `README.md` skill catalog 표 — 새 skill 4개 추가 (vllm-bootstrap,
  bilingual-book-authoring, k8s-pod-autostart, llm-eval-multi-model)

## [0.3.0] - 2026-05-02

[`6818823`] feat: multi-agent-orchestrator skill + GitHub Actions CI

### Added
- `multi-agent-orchestrator` skill — Claude Code 8+ 에이전트 병렬 디스패치 패턴
  (Domain/Part/Language/Verification 샤딩, `subagent_type` 선택 가이드, rate limit 처리,
  ultrathink 통합, 프롬프트 템플릿 포함; GEM-LLM bootstrap 1000p book + 12K LOC 검증)
- GitHub Actions CI (`.github/workflows/validate.yml`)
  - SKILL.md YAML frontmatter 검증 (`name`, `description` ≤ 1024자, `name == dir`)
  - `install.sh` REGISTRY ↔ 디렉토리 존재 교차 검증
  - 모든 `*.sh` 파일 Bash 문법 검사
  - push/PR to main 트리거

### Changed
- `install.sh` REGISTRY 19 entries (17 skills + 1 command + 1 신규)

## [0.2.1] - 2026-05-02

[`efd48f2`] feat: add pandoc-bilingual-build skill + CONTRIBUTING.md

### Added
- `pandoc-bilingual-build` skill — *기존* 프로젝트에 빌드 파이프라인 추가
  (`bash install-into.sh /path/to/project` 한 줄로 Makefile + scripts/ +
  docs/build/templates/ + OUTLINE stub 주입; 6 타겟 × 4 포맷 = book-ko/en, manual-ko/en, paper-ko/en)
- `CONTRIBUTING.md` — 신규 skill 제출 가이드
  (SKILL.md frontmatter 규칙, body 구조 권장 50–300줄, install.sh REGISTRY 등록 절차,
  품질 기준, skill 아이디어 카테고리, PR 가이드)

### Changed
- `install.sh` REGISTRY 18 entries (16 skills + 1 command + 1 신규)

## [0.2.0] - 2026-05-02

[`51120d4`] feat: initial claude-skills release
[`86f6d12`] merge: integrate GEM-LLM skills + project-bootstrap into existing skill collection
[`1002db7`] fix(project-bootstrap): cleanup OUTLINE templates + SKIP flags

### Added
- `project-bootstrap` skill — bilingual research/code 프로젝트 init 한 방
  (GitHub + Cloudflare + KO/EN book + KO/EN paper + Pandoc + plan;
  74개 템플릿 포함: Pandoc filters, KCI+IEEE LaTeX templates, Mermaid catalog, OUTLINE skeletons)
- 14 GEM-LLM operational skills (production-tested)
  - `gem-llm-overview`, `gem-llm-supervisor`, `gem-llm-admin-cli`
  - `gem-llm-load-test`, `gem-llm-troubleshooting`, `gem-llm-cloudflare-tunnel`
  - `gem-llm-cli-client`, `gem-llm-vllm-debug`, `gem-llm-gateway-debug`
  - `gem-llm-deploy-vllm`, `gem-llm-test-inference`, `gem-llm-build-docs`
  - `gem-llm-review-prompt`, `gem-llm-debug-mcp`
- `init-project.sh`에 `SKIP_GITHUB=1`, `SKIP_CLOUDFLARE=1` 환경변수
  (GitHub repo / DNS record 생성 없이 테스트용 dry-run 가능)

### Changed
- README.md 통합 테이블 — 17 skills 한 눈에 보기
- `.gitignore` — `*.swp`, `.env.local`, `*.pyo` 추가
- `install.sh` REGISTRY 17 entries 확장 (project-bootstrap + 14 gem-llm-*)

### Fixed
- `project-bootstrap` OUTLINE 템플릿이 GEM-LLM에서 그대로 복사되어
  `Qwen Coder Dense(31B) + MoE(26B-A4B)` 같은 프로젝트 특정 내용이
  새 프로젝트에 노출되던 문제 — 6개 OUTLINE.md를 `__PROJECT_TITLE__`
  placeholder 사용 project-agnostic stub으로 교체
- `docs/templates`와 `docs/pandoc-filters`가 `docs/build/templates`,
  `scripts/pandoc-filters`와 중복되던 문제 — 중복 디렉토리 제거
- 3회 dry-run bootstrap (`bootstrap-test-2026`, `bootstrap-verify`,
  `bootstrap-final-test`)으로 검증; 모두 `_trash/` 격리

## [0.1.0] - 2026-04-22

[`16393d0`] Add selective skill installer with sparse-checkout
[`10ff0c4`] Separate skills into independent folders with own READMEs
[`171e1ce`] Add exam-system skill
[`0d16a1a`] init: searcam-book skill + install/uninstall scripts

### Added
- `searcam-book` command + install/uninstall scripts (초기 커밋)
- `exam-system` skill
- 독립 폴더 + 개별 README 구조 — 각 skill이 자체 README를 갖도록 분리
- `install.sh` selective installer (sparse-checkout)
  - GitHub에서 선택한 skill만 다운로드 (전체 repo clone 불필요)
  - `./install.sh --list` 로 사용 가능한 skill 목록 표시

[Unreleased]: https://github.com/USER/claude-skills/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/USER/claude-skills/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/USER/claude-skills/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/USER/claude-skills/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/USER/claude-skills/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/USER/claude-skills/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/USER/claude-skills/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/USER/claude-skills/releases/tag/v0.1.0
