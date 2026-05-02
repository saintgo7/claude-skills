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
)

# ── helpers ────────────────────────────────────────────────────────────────

find_entry() {
  local name="$1"
  for entry in "${REGISTRY[@]}"; do
    [ "$(echo "$entry" | cut -d'|' -f1)" = "$name" ] && echo "$entry" && return
  done
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
    rm -rf "$dest"
    cp -r "$TMP_DIR/$name" "$dest"
    echo "✓ Installed → $dest"

  elif [ "$type" = "command" ]; then
    sparse_clone "commands"
    mkdir -p "$COMMANDS_DIR"
    cp "$TMP_DIR/commands/${name}.md" "$COMMANDS_DIR/"
    dest="$COMMANDS_DIR/${name}.md"
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
