#!/bin/bash
# Claude Code skill installer — installs only what you choose.
#
# Usage:
#   ./install.sh --list              show available skills
#   ./install.sh <skill-name>        install a skill
#   ./install.sh --remove <skill>    uninstall a skill
#
# Example:
#   ./install.sh exam-system
#   ./install.sh searcam-book

set -e

REPO="https://github.com/saintgo7/claude-skills.git"
SKILLS_DIR="$HOME/.claude/skills"
COMMANDS_DIR="$HOME/.claude/commands"
TMP_DIR="/tmp/claude-skills-$$"

# Registry — add a line here whenever a new skill is added to the repo.
# Format: "name|type|description"
#   type "skill"   → installed to ~/.claude/skills/<name>/
#   type "command" → installs commands/<name>.md to ~/.claude/commands/
REGISTRY=(
  "exam-system|skill|온라인 시험 운영 플레이북 (모니터링·대응·사후 통계)"
  "searcam-book|command|SearCam 기술 서적 챕터 작성 슬래시 커맨드"
  "project-bootstrap|skill|bilingual research/code 프로젝트 한 번에 부트스트랩 (GitHub + Cloudflare + 한/영 책 + 한/영 논문 + Pandoc)"
  "pandoc-bilingual-build|skill|기존 프로젝트에 한/영 Pandoc + XeTeX 빌드 파이프라인 추가 (project-bootstrap의 빌드 부분만)"
  "multi-agent-orchestrator|skill|Claude Code 8+ 에이전트 병렬 디스패치 패턴 (책 1000p, 코드 12K LOC 검증)"
  "bilingual-book-authoring|skill|한/영 동시 책 저작 워크플로 (~1000p 검증) — OUTLINE mirror, 다이어그램 공유, Part 멀티 에이전트, 에러 사례 수집"
  "cloudflare-tunnel-setup|skill|Cloudflare Tunnel 처음부터 셋업 (도메인 → 로컬 HTTPS 노출, SSH ProxyCommand 포함)"
  "gem-llm-overview|skill|GEM-LLM 시스템 전체 구조 + 다른 gem-llm-* skill 라우팅"
  "gem-llm-supervisor|skill|GEM-LLM 전체 스택 start/stop/status/restart"
  "gem-llm-admin-cli|skill|GEM-LLM 사용자/API key 관리"
  "gem-llm-load-test|skill|GEM-LLM 부하 테스트 (locust + asyncio multi-user)"
  "gem-llm-troubleshooting|skill|GEM-LLM 13개 실전 에러 사례 매핑"
  "gem-llm-cloudflare-tunnel|skill|llm.pamout.com / Cloudflare DNS / master-n1 SSH"
  "gem-llm-cli-client|skill|gem-cli REPL/슬래시/tool calling"
  "gem-llm-vllm-debug|skill|vLLM 의존성 매트릭스 + 부팅 실패 패턴"
  "gem-llm-gateway-debug|skill|FastAPI Gateway 500/401/429 패턴"
  "gem-llm-deploy-vllm|skill|vLLM 단일 모델 launch (구)"
  "gem-llm-test-inference|skill|vLLM 추론 검증"
  "gem-llm-build-docs|skill|Pandoc + LaTeX 빌드 (책/매뉴얼/논문)"
  "gem-llm-review-prompt|skill|프롬프트 리뷰 가이드"
  "gem-llm-debug-mcp|skill|MCP 서버 디버깅"
  "sqlite-wal-safe-ops|skill|SQLite WAL 모드 운영 함정 회피 (disk I/O error 방지, 안전한 백업, journal_mode 선택)"
  "fastapi-gateway-pattern|skill|FastAPI OpenAI 호환 LLM 게이트웨이 구축 패턴 (인증/quota/스트리밍/SQLAlchemy pool)"
  "vllm-bootstrap|skill|vLLM 처음부터 부팅 가이드 (의존성 매트릭스, TP=1~8 선택, tool-call-parser, 부팅 실패 13개 패턴)"
  "k8s-pod-autostart|skill|K8s pod / 컨테이너 환경에서 systemd 없이 자동 시작 (s6 cont-init, .bashrc one-shot, watchdog, livenessProbe 4가지 패턴)"
  "llm-eval-multi-model|skill|여러 LLM 동시 평가/비교 (latency, throughput, 정확도, tool calling, 한국어 응답)"
  "postgres-migration-from-sqlite|skill|SQLite → PostgreSQL 마이그레이션 (FastAPI/SQLAlchemy/Alembic, 100+ 동접 production scaling)"
  "prometheus-fastapi-metrics|skill|FastAPI Prometheus 커스텀 메트릭 추가 (Counter/Histogram/Gauge 3계층, cardinality 제한, Grafana 시작)"
  "quota-rate-limit-pattern|skill|API 게이트웨이 3계층 quota/rate-limit (slowapi RPM + asyncio.Semaphore + DB daily, 50동접 검증)"
  "fastapi-async-patterns|skill|FastAPI + asyncio + httpx + SQLAlchemy async 6 패턴 (SSE 스트리밍, lifespan, DI, Semaphore, async DB, background task)"
  "vllm-tool-calling|skill|vLLM tool calling 3단계 디펜스 (server parser + model weight + client fallback) — case 15/16/17 일반화"
  "pytest-fastapi-pattern|skill|pytest로 FastAPI 통합 테스트 (httpx async + ASGITransport + respx + lifespan + 격리, 219 테스트 검증)"
  "bash-cli-best-practices|skill|bash 운영 CLI 작성 8 검증 패턴 (set -euo pipefail, sub-cmd, mv to _trash, SQL injection 방지)"
  "claude-code-skill-authoring|skill|Claude Code skill 작성 메타 가이드 (frontmatter, REGISTRY, install/uninstall, CI validation)"
  "deployment-checklist|skill|LLM/API 서비스 배포 전 체크리스트 7영역 56항목 (인증/보안/모니터링/스케일/문서/롤백/외부) — GEM-LLM 28일 운영 검증"
  "korean-tech-blog-authoring|skill|한국어 기술 블로그/아티클 작성 6원칙 (격식체, 영문 식별자, 기술 용어, 코드 인용, 다이어그램, 구조)"
  "dependency-vulnerability-fix|skill|pip-audit 취약점 안전 fix 4단계 (스캔→분류→patch 업그레이드→회귀) — vLLM/PyTorch 보호"
  "observability-bundle|skill|FastAPI 통합 관측성 (Prometheus + Loki + OpenTelemetry + Sentry, 3 pillar 통합)"
  "env-isolation-pattern|skill|운영 환경변수 → 테스트 누설 방지 (case 18 일반화) — explicit unset + unconditional override + container isolation"
  "llm-serving-performance-tuning|skill|LLM 서빙 (vLLM + FastAPI) 성능 튜닝 6단계 — GEM-LLM 50/100/200동접 검증 (1282 tok/s, p99 9.1s)"
  "mermaid-diagram-authoring|skill|Mermaid 다이어그램 작성 + Pandoc 통합 5단계 (CATALOG → extract → SVG → Lua filter → 본문 참조) — 40 다이어그램 검증"
  "api-key-lifecycle-pattern|skill|API key 발급/회수/검증 라이프사이클 (gem_live_<32hex>, prefix 8자 lookup, sha256+salt)"
  "k8s-cron-alternatives|skill|K8s pod / cron 미설치 환경 정기 작업 5 패턴 (watchdog + CronJob + external + s6-cron + supervisord)"
  "cicd-github-actions-pattern|skill|GitHub Actions CI/CD 검증된 패턴 (schema validation + pip-audit + atomic commit) — claude-skills 41 run green"
  "blue-green-deployment-pattern|skill|LLM 서빙 blue/green 무중단 cutover (격리 venv + 새 포트 검증 + 트래픽 전환 + rollback) — vLLM 0.19→0.20 검증"
  "multi-llm-routing-pattern|skill|FastAPI Gateway 모델 라우팅 5 패턴 (정적/weighted/fallback/사용자별/A/B) — GEM-LLM 검증"
)

# ── helpers ────────────────────────────────────────────────────────────────

find_entry() {
  local name="$1"
  for entry in "${REGISTRY[@]}"; do
    if [ "$(echo "$entry" | cut -d'|' -f1)" = "$name" ]; then
      echo "$entry"
      return 0
    fi
  done
  return 0  # not found — caller checks via [ -z "$entry" ] (set -e safe)
}

list_skills() {
  echo "Available skills:"
  echo ""
  for entry in "${REGISTRY[@]}"; do
    name=$(echo "$entry" | cut -d'|' -f1)
    type=$(echo "$entry" | cut -d'|' -f2)
    desc=$(echo "$entry" | cut -d'|' -f3)
    printf "  %-20s  %-10s  %s\n" "$name" "[$type]" "$desc"
  done
  echo ""
  echo "Usage:"
  echo "  ./install.sh <skill-name>"
  echo "  ./install.sh --remove <skill-name>"
}

sparse_clone() {
  local path="$1"
  rm -rf "$TMP_DIR"
  git clone --filter=blob:none --sparse --depth=1 --quiet "$REPO" "$TMP_DIR"
  git -C "$TMP_DIR" sparse-checkout set "$path" --quiet
}

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# ── install ────────────────────────────────────────────────────────────────

install_skill() {
  local name="$1"
  local entry
  entry=$(find_entry "$name")

  if [ -z "$entry" ]; then
    echo "ERROR: '$name' not found. Run ./install.sh --list"
    exit 1
  fi

  local type dest
  type=$(echo "$entry" | cut -d'|' -f2)

  echo "→ Downloading '$name'..."

  if [ "$type" = "skill" ]; then
    sparse_clone "$name"
    dest="$SKILLS_DIR/$name"
    mkdir -p "$SKILLS_DIR"
    if [ -d "$dest" ]; then
      echo "  (already installed — overwriting)"
      rm -rf "$dest"
    fi
    cp -r "$TMP_DIR/$name" "$dest"
    echo "✓ Installed → $dest"

  elif [ "$type" = "command" ]; then
    sparse_clone "commands"
    mkdir -p "$COMMANDS_DIR"
    dest="$COMMANDS_DIR/${name}.md"
    if [ -f "$dest" ]; then
      echo "  (already installed — overwriting)"
    fi
    cp "$TMP_DIR/commands/${name}.md" "$COMMANDS_DIR/"
    echo "✓ Installed → $dest"
  fi

  echo "Restart Claude Code to use the skill."
}

# ── remove ─────────────────────────────────────────────────────────────────

remove_skill() {
  local name="$1"
  local entry
  entry=$(find_entry "$name")

  if [ -z "$entry" ]; then
    echo "ERROR: '$name' not found. Run ./install.sh --list"
    exit 1
  fi

  local type
  type=$(echo "$entry" | cut -d'|' -f2)

  if [ "$type" = "skill" ]; then
    local dest="$SKILLS_DIR/$name"
    if [ -d "$dest" ]; then
      rm -rf "$dest"
      echo "✓ Removed $dest"
    else
      echo "Not installed: $dest"
    fi

  elif [ "$type" = "command" ]; then
    local dest="$COMMANDS_DIR/${name}.md"
    if [ -f "$dest" ]; then
      rm "$dest"
      echo "✓ Removed $dest"
    else
      echo "Not installed: $dest"
    fi
  fi
}

# ── main ───────────────────────────────────────────────────────────────────

case "${1:-}" in
  --list|-l)
    list_skills
    ;;
  --remove|-r)
    [ -z "${2:-}" ] && { echo "Usage: ./install.sh --remove <skill-name>"; exit 1; }
    remove_skill "$2"
    ;;
  "")
    echo "Usage:"
    echo "  ./install.sh --list              show available skills"
    echo "  ./install.sh <skill-name>        install a skill"
    echo "  ./install.sh --remove <skill>    uninstall a skill"
    ;;
  *)
    install_skill "$1"
    ;;
esac
