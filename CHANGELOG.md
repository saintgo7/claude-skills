# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

(현재 main 브랜치에 머지되었으나 아직 태깅되지 않은 변경사항이 여기에 누적됩니다.)

## [0.8.5] — 2026-05-03

### Added
- `cloudflare-tunnel-ssh-access-pattern` skill — SSH via Cloudflare Tunnel (cloudflared access ssh ProxyCommand). K8s pod / no-public-IP 외부 접속 패턴, gem-llm 3노드(master/n1/n3) 검증.
- `pod-process-autostart-pattern` skill — K8s pod / systemd-less idempotent 자동 시작 (~/.bashrc 가드 + s6 + supervisord + lifecycle.postStart).
- `playbook-authoring-pattern` skill — 4-tuple([목적][명령][기대출력][실패복구]) 절차서 작성 일반화.

### Changed
- `cloudflare-tunnel-setup` — SSH 라우팅 섹션 + 관련 skill cross-reference 추가.

### Notes
- REGISTRY: 54 → **57 entries**
- gem-llm SSH 외부접속 doc v2(1193 lines, v1 438 → v2 1193 +172%) 작성 사례에서 추출.
- 책 case 4(master→n1 SSH HTTP-only)의 일반화된 해결 패턴.

## [0.8.4] — 2026-05-03

### Added
- `api-contract-testing-pattern` skill — FastAPI/REST contract 테스트 (pydantic + openapi snapshot)
- `html-static-dashboard-pattern` skill — 정적 HTML 헬스 대시보드 (Grafana 부재 대안)
- `multi-agent-autonomous-loop-pattern` skill — 5 agent + ScheduleWakeup + atomic hook (55h 검증)

### Notes
- REGISTRY: 51 → **54 entries**
- gem-llm 55시간 자율 진행 패턴 추출 (71 라운드, ~350 디스패치, force push 0)
- atomic commit hook race condition 자동 해결 검증 완료 (case 21)
- README 카탈로그 26 → 53 항목 확장

## [0.8.3] — 2026-05-03

### Added
- `production-postmortem-pattern` skill — 7-section + blameless + 액션 아이템 + 책 case 통합
- `shell-cli-dispatch-pattern` skill — bash sub-command dispatcher 정형 (case 19에서 추출)

### Notes
- REGISTRY: 49 → **51 entries**
- gem-llm 5월 3일 라운드에서 추출 (case 19 silent bug postmortem 사례)
- atomic commit hook 검증 완료 (race condition 자동 해결 입증)
- (예정) `api-contract-testing-pattern` 추가 시 v0.8.4

## [0.8.2] — 2026-05-03

### Added
- `bulk-user-onboarding-pattern` skill — CSV/JSON 사용자 일괄 등록 (idempotent + 1회 캐싱)
- `api-route-consistency-pattern` skill — Gateway ↔ CLI ↔ 매뉴얼 ↔ 테스트 4-way 일관성

### Notes
- REGISTRY: 47 → **49 entries**
- gem-llm 5월 3일 라운드에서 추출 (case 20 사고 + 76 users bulk 등록 검증)
- atomic commit hook 검증 통과

## [0.8.1] — 2026-05-03

### Added
- `concurrent-load-testing-pattern` skill — locust + asyncio.gather 일반화 (5 파일, 183-line SKILL + 2 templates)

### Notes
- REGISTRY: 46 → **47 entries**
- 검증된 부하 패턴 5종 (50/100/200 동접 + 16-keys 분배 + p99 SLO)
- gem-llm 5월 3일 라운드에서 추출 (scaling-bench 16 keys × 7 p99 -7.6%, 16 × 13 p99 -20%)

## [0.8.0] - 2026-05-03

큰 자산(라우팅 + cutover 패턴) 추가로 **minor 버전 ↑**.
GEM-LLM v8 (76 users, 책 18장 확장 보강) 와 동일 사이클.

### Added
- `multi-llm-routing-pattern` skill — Gateway 모델 라우팅 5 패턴
  (정적 매핑 / weighted load balancing / fallback 체인 / 사용자·플랜별 / A/B canary;
  GEM-LLM Gateway `upstream_map` 정적 매핑이 `qwen2.5-coder-32b → :8001`,
  `qwen3-coder-30b → :8002` 로 28일 + 100동접 부하 통과한 사례 일반화;
  단계적 확장 가이드 — 정적 → weighted → fallback → 사용자 플랜 → A/B 카나리 5 단계,
  외부 provider(OpenAI/Anthropic) + 자체 vLLM 혼합 라우팅,
  헤더 / 모델 ID / 사용자 키 기반 분기 매트릭스,
  실패 모드 — upstream 한 대 down 시 fallback timeout 설계,
  templates/ — FastAPI router 패턴, weighted random 헬퍼, fallback wrapper)
- `blue-green-deployment-pattern` skill — LLM 서빙 무중단 cutover 패턴
  (이전 v0.7.x 사이클에서 작성됨, **v0.8.0 에서 CHANGELOG 카탈로그 정리**;
  격리 venv(`/home/jovyan/vllm-020-env`)에서 새 버전 검증 → 새 포트 부팅 →
  헬스체크 + 토큰 echo → 게이트웨이 upstream atomic switch → 5분 관찰 →
  blue 정리 / 이상 시 즉시 rollback;
  GEM-LLM vLLM 0.19→0.20 cutover 자산화 — `scripts/cutover-vllm-020.sh` 185줄(10단계),
  `scripts/rollback-vllm-019.sh` 65줄, 실측 다운타임 약 3분;
  K8s 환경 deployment / service selector 전환 매핑 — bare-metal vs cluster 두 시나리오,
  templates/cutover.sh.template + rollback.sh.template — 단계별 검증 게이트)

### Changed
- `install.sh` REGISTRY **44 → 46 entries** (45 skills + 1 command) — 신규 2개 추가
  (`multi-llm-routing-pattern`, `blue-green-deployment-pattern`)

### Stats
- 누적 commits since v0.7.0: 22+
- CI: validate.yml + atomic commit check, 41+ run all green
- GEM-LLM 동기화: STATUS v8 (76 users, 책 18장 보강, claude-skills 46 반영)

## [0.7.3] - 2026-05-02

### Added
- `cicd-github-actions-pattern` skill — GitHub Actions CI/CD 검증된 패턴
  (validate.yml: SKILL.md frontmatter 검증 + REGISTRY ↔ 디렉토리 교차 검증 + Bash 문법 검사,
  pip-audit.yml: push/PR + 매주 월 09:00 UTC 의존성 스캔, gateway/cli 분리,
  atomic commit check: PR base..HEAD diff 에서 새 SKILL.md vs install.sh REGISTRY 추가
  일치 확인 — case CI transient mismatch 회피;
  claude-skills 자체 워크플로 **41 run green** 으로 검증된 베이스라인,
  GEM-LLM `pip-audit` weekly 27 vulnerabilities 식별 → fix 4단계 통합)
- `api-key-lifecycle-pattern` skill — API key 발급/회수/검증 라이프사이클 패턴
  (`gem_live_<32hex>` 포맷 — `gem_live_` prefix 8자 lookup + sha256+salt 해시 저장,
  raw key는 issue 직후 1회만 표시 (`raw_key`는 DB 미저장),
  revoke 시 soft-delete (`revoked_at` timestamp, key 자체는 보존하여 audit log 추적),
  prefix 8자 인덱스로 sha256 해시 비교 비용 최소화 — 19 keys 환경에서 P50 < 1ms,
  GEM-LLM gateway `/v1/auth` 미들웨어 + admin-cli `issue-key`/`revoke-key`/`list-keys` 검증,
  templates/ — SQLAlchemy 모델, FastAPI dependency, admin-cli 명령 3종)
- `k8s-cron-alternatives` skill — K8s pod / cron 미설치 환경 정기 작업 5 패턴
  (1) bash watchdog (sleep loop, supervisor.sh 통합, GEM-LLM `cve-watcher` 검증),
  (2) Kubernetes CronJob (cluster-level, RBAC + ServiceAccount),
  (3) external scheduler (GitHub Actions schedule, AWS EventBridge),
  (4) s6-cron in cont-init.d (동일 파드 영구, overlay FS 한계),
  (5) supervisord [program] autostart=true autorestart=true;
  GEM-LLM `backup-db.sh` 일 1회 + `cve-watcher.sh` 주 1회 검증,
  systemd 부재 환경의 표준 패턴 매핑, livenessProbe와 분리 가이드)
- `.githooks/pre-commit` — atomic commit hook
  (새 `<name>/SKILL.md` 디렉토리 추가 시 같은 commit에 install.sh REGISTRY entry가
  함께 들어가는지 검증 — case CI transient mismatch 회피;
  반대로 REGISTRY entry 추가 시 디렉토리/SKILL.md 동시 존재 검증)
- GitHub Actions `validate.yml` 에 **Atomic commit check** step 추가
  (PR base..HEAD diff 에서 새 SKILL.md 디렉토리 vs install.sh REGISTRY 추가 일치 확인;
  pre-commit hook 과 2단 디펜스 — 로컬 stage 단계 + CI PR 단계)

### Changed
- `install.sh` REGISTRY **41 → 44 entries** (43 skills + 1 command) — 신규 3개 추가

## [0.7.2] - 2026-05-02

### Added
- `mermaid-diagram-authoring` skill — Mermaid 다이어그램 작성 + Pandoc 통합 5단계 패턴
  (CATALOG → extract → SVG 사전 렌더 → Lua filter 라우팅 → 본문 참조;
  GEM-LLM 책 / 매뉴얼 / 논문 6 타깃에서 **40 다이어그램 정식 SVG (Stub 0)** 검증;
  flowchart / sequenceDiagram / classDiagram / erDiagram / stateDiagram / gantt
  6 타입 권장 사용, chromium puppeteer 캐시 디렉토리 함정,
  Pandoc Lua filter 로 `<!-- diagram:NAME -->` 마커를 figure 로 치환,
  SVG vs PNG 선택 기준 (벡터 유지 vs LaTeX/Word 호환),
  한글 라벨 폰트 임베딩, ID 충돌 회피, 회귀 검증 체크리스트)
- `llm-serving-performance-tuning` skill — vLLM + FastAPI 게이트웨이 성능 튜닝 6단계 운영 가이드
  (1) baseline 측정 (RPS / TTFT / TPOT / p50/p95/p99 / tok/s),
  (2) DB pool 튜닝 (`pool_size=50, max_overflow=200, pool_timeout=10`),
  (3) SQLite write-lock (`busy_timeout=30s`) + PG 전환 시점,
  (4) vLLM 옵션 (`--max-num-seqs`, `--gpu-memory-utilization`, prefix caching),
  (5) Gateway async 함정 (lifespan, Semaphore, async DB),
  (6) 30분 health monitor + GPU/RAM 누수 검증;
  GEM-LLM **50/100/200동접 검증 — 1282 tok/s, p99 9.1s 베이스라인** + 100동접
  재검증 RPS +14.8% / p99 −11.6% 재현 가능)

### Changed
- `install.sh` REGISTRY **39 → 41 entries** (40 skills + 1 command) — 신규 2개 추가

## [0.7.1] - 2026-05-02

### Added
- `env-isolation-pattern` skill — 운영/테스트 환경변수 격리 패턴
  (GEM-LLM **case 18 일반화** — `validate-all.sh`가 부모 supervisor에서 상속한
  `GATEWAY_DB_URL` 환경변수를 통해 pytest가 운영 SQLite를 wipe한 사고에서 도출;
  `setdefault`는 약한 방어 — 강한 방어 2가지: (1) 자식 프로세스 진입 직전에
  `env -u VAR1 -u VAR2 ...` 로 운영 변수 명시적 unset, (2) test `conftest.py`에서
  `os.environ["VAR"] = "in-memory"` 무조건 덮어쓰기;
  백업 자동화는 사고 회복의 마지막 안전망 — 케이스 13의 `backup-db.sh` 자동화가
  케이스 18 사고 비용을 0으로 만든 실증;
  destructive 작업(테스트, 마이그레이션, 정리) 표준 격리 체크리스트,
  `set -a; source .env; set +a` 위험성, supervisor + 자식 pytest 환경 분리 패턴)

### Changed
- `install.sh` REGISTRY **38 → 39 entries** (38 skills + 1 command) — 신규 1개 추가

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

[Unreleased]: https://github.com/USER/claude-skills/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/USER/claude-skills/compare/v0.7.3...v0.8.0
[0.7.3]: https://github.com/USER/claude-skills/compare/v0.7.2...v0.7.3
[0.7.2]: https://github.com/USER/claude-skills/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/USER/claude-skills/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/USER/claude-skills/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/USER/claude-skills/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/USER/claude-skills/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/USER/claude-skills/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/USER/claude-skills/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/USER/claude-skills/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/USER/claude-skills/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/USER/claude-skills/releases/tag/v0.1.0
