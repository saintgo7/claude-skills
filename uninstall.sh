#!/usr/bin/env bash
# ──────────────────────────────────────────────────────
# Claude Code Skills Uninstaller
#
# Usage:
#   ./uninstall.sh              # Remove all skills from this pack
#   ./uninstall.sh searcam-book # Remove a specific skill
# ──────────────────────────────────────────────────────

set -euo pipefail

SKILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/commands" && pwd)"
TARGET_DIR="$HOME/.claude/commands"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[SKIP]${NC} $*"; }

if [[ $# -gt 0 ]]; then
  FILES=()
  for arg in "$@"; do
    FILES+=("$SKILLS_DIR/${arg%.md}.md")
  done
else
  mapfile -t FILES < <(find "$SKILLS_DIR" -maxdepth 1 -name "*.md" | sort)
fi

REMOVED=0
for src in "${FILES[@]}"; do
  name="$(basename "$src")"
  dest="$TARGET_DIR/$name"
  if [[ -f "$dest" ]]; then
    rm "$dest"
    success "Removed: /${name%.md}"
    REMOVED=$((REMOVED + 1))
  else
    warn "Not found (already removed?): $name"
  fi
done

echo ""
echo "Removed $REMOVED skill(s)."
