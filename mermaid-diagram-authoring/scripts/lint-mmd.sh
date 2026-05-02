#!/usr/bin/env bash
# lint-mmd.sh — Mermaid diagram lint (CI-ready)
#
# Validates:
#   1. Each mmd/diagram-NN.mmd parses with mmdc --quiet (dry render)
#   2. Each svg/diagram-NN.svg is non-zero bytes
#   3. CATALOG.md IDs == mmd/*.mmd basenames == svg/*.svg basenames
#
# Exit code: 0 = OK, 1 = lint failure.

set -euo pipefail

ROOT="${1:-diagrams}"
CATALOG="$ROOT/CATALOG.md"
MMD_DIR="$ROOT/mmd"
SVG_DIR="$ROOT/svg"
PUPPETEER="${PUPPETEER:-$ROOT/puppeteer.json}"

fail=0
note() { echo "  $1"; }
err()  { echo "FAIL: $1" >&2; fail=1; }

[ -f "$CATALOG" ] || { err "missing $CATALOG"; exit 1; }

# 1. mmdc syntax check (dry-run via output to /tmp)
echo "→ Step 1: mmdc syntax check"
for f in "$MMD_DIR"/diagram-*.mmd; do
  [ -f "$f" ] || continue
  id=$(basename "$f" .mmd)
  if ! mmdc -i "$f" -o "/tmp/${id}.svg" -p "$PUPPETEER" --quiet 2>/tmp/mmdc.err; then
    err "$id: mermaid syntax error"
    sed 's/^/    /' /tmp/mmdc.err >&2
  else
    note "$id OK"
  fi
done

# 2. SVG non-zero bytes
echo "→ Step 2: SVG size check"
for f in "$SVG_DIR"/diagram-*.svg; do
  [ -f "$f" ] || continue
  id=$(basename "$f" .svg)
  if [ ! -s "$f" ]; then
    err "$id: 0-byte SVG"
  else
    note "$id $(stat -c%s "$f") bytes"
  fi
done

# 3. CATALOG ↔ mmd ↔ svg 1:1:1
echo "→ Step 3: ID consistency"
catalog_ids=$(grep -oE '^## (diagram-[0-9]+)' "$CATALOG" | awk '{print $2}' | sort -u)
mmd_ids=$(ls "$MMD_DIR"/diagram-*.mmd 2>/dev/null | xargs -n1 basename | sed 's/\.mmd$//' | sort -u)
svg_ids=$(ls "$SVG_DIR"/diagram-*.svg 2>/dev/null | xargs -n1 basename | sed 's/\.svg$//' | sort -u)

diff_co=$(diff <(echo "$catalog_ids") <(echo "$mmd_ids") || true)
diff_ms=$(diff <(echo "$mmd_ids") <(echo "$svg_ids") || true)

[ -z "$diff_co" ] || { err "CATALOG vs mmd mismatch:"; echo "$diff_co" >&2; }
[ -z "$diff_ms" ] || { err "mmd vs svg mismatch:";   echo "$diff_ms" >&2; }

[ "$fail" -eq 0 ] && echo "✓ lint-mmd OK" || { echo "✗ lint-mmd failed"; exit 1; }
