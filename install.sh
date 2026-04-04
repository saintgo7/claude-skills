#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# Claude Code Skills Installer
# https://github.com/saintgo7/claude-skills
#
# Usage:
#   ./install.sh              # Install all skills globally
#   ./install.sh searcam-book # Install a specific skill
#   ./install.sh --list       # List available skills
# ──────────────────────────────────────────────────────

set -euo pipefail

SKILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/commands" && pwd)"
TARGET_DIR="$HOME/.claude/commands"
BACKUP_DIR="$HOME/.claude/commands-backup-$(date +%Y%m%d%H%M%S)"

# ── Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── List mode ──
if [[ "${1:-}" == "--list" ]]; then
  echo ""
  echo "Available skills:"
  echo ""
  for f in "$SKILLS_DIR"/*.md; do
    name="$(basename "$f" .md)"
    desc="$(grep -m1 '^description:' "$f" | sed 's/description: *"//' | sed 's/".*//' || echo "(no description)")"
    printf "  %-25s %s\n" "$name" "$desc"
  done
  echo ""
  exit 0
fi

# ── Create target dir ──
mkdir -p "$TARGET_DIR"

# ── Collect skills to install ──
if [[ $# -gt 0 && "${1:-}" != "--list" ]]; then
  # Specific skill(s) requested
  FILES=()
  for arg in "$@"; do
    skill_file="$SKILLS_DIR/${arg%.md}.md"
    if [[ ! -f "$skill_file" ]]; then
      error "Skill not found: $arg"
      echo "Run './install.sh --list' to see available skills."
      exit 1
    fi
    FILES+=("$skill_file")
  done
else
  # All skills
  mapfile -t FILES < <(find "$SKILLS_DIR" -maxdepth 1 -name "*.md" | sort)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  warn "No skill files found in $SKILLS_DIR"
  exit 0
fi

echo ""
echo "Claude Code Skills Installer"
echo "────────────────────────────"
echo "Source : $SKILLS_DIR"
echo "Target : $TARGET_DIR"
echo ""

INSTALLED=0
SKIPPED=0
BACKED_UP=0

for src in "${FILES[@]}"; do
  name="$(basename "$src")"
  dest="$TARGET_DIR/$name"

  if [[ -f "$dest" ]]; then
    # Backup existing file before overwrite
    if [[ $BACKED_UP -eq 0 ]]; then
      mkdir -p "$BACKUP_DIR"
    fi
    cp "$dest" "$BACKUP_DIR/$name"
    BACKED_UP=$((BACKED_UP + 1))
    warn "Overwriting existing skill (backup saved): $name"
  fi

  cp "$src" "$dest"
  success "Installed: /${name%.md}"
  INSTALLED=$((INSTALLED + 1))
done

echo ""
echo "────────────────────────────"
echo "Installed : $INSTALLED skill(s)"
if [[ $BACKED_UP -gt 0 ]]; then
  echo "Backups   : $BACKED_UP file(s) → $BACKUP_DIR"
fi
echo ""
echo "Restart Claude Code (or open a new session) to use the new skills."
echo "Type /<skill-name> to invoke any installed skill."
echo ""
