#!/usr/bin/env bash
# pandoc-bilingual-build — 기존 프로젝트에 한/영 Pandoc 빌드 파이프라인 추가
# 사용: bash install-into.sh /path/to/your-project

set -euo pipefail

DEST="${1:-}"
if [ -z "$DEST" ] || [ ! -d "$DEST" ]; then
  echo "사용: $0 <project-directory>"
  echo "  대상 디렉토리는 미리 존재해야 함"
  exit 1
fi

# 사본 위치 — claude-skills clone에서 가져옴
# (project-bootstrap의 templates를 재사용)
BOOTSTRAP_TEMPL=~/.claude/skills/project-bootstrap/templates
if [ ! -d "$BOOTSTRAP_TEMPL" ]; then
  echo "ERROR: project-bootstrap skill이 먼저 설치되어 있어야 함"
  echo "  ./install.sh project-bootstrap"
  exit 1
fi

echo "=== $DEST 에 Pandoc 빌드 파이프라인 설치 ==="

# 1. Makefile (있으면 .bak으로 백업)
if [ -f "$DEST/Makefile" ]; then
  mkdir -p "$DEST/_trash"
  mv "$DEST/Makefile" "$DEST/_trash/Makefile.bak.$(date +%Y%m%d-%H%M%S)"
  echo "  기존 Makefile → _trash/"
fi
cp "$BOOTSTRAP_TEMPL/Makefile" "$DEST/Makefile"
echo "  ✓ Makefile"

# 2. scripts/
mkdir -p "$DEST/scripts/pandoc-filters"
for f in build-docs.sh build-diagrams.sh extract-mmd.sh validate-catalog.sh; do
  if [ -f "$BOOTSTRAP_TEMPL/scripts/$f" ]; then
    cp "$BOOTSTRAP_TEMPL/scripts/$f" "$DEST/scripts/$f"
    chmod +x "$DEST/scripts/$f"
  fi
done
for f in diagram-insert.lua citation-fix.lua code-block-listing.lua; do
  [ -f "$BOOTSTRAP_TEMPL/scripts/$f" ] && cp "$BOOTSTRAP_TEMPL/scripts/$f" "$DEST/scripts/pandoc-filters/$f"
done
echo "  ✓ scripts/"

# 3. docs/build/{templates,metadata}
mkdir -p "$DEST/docs/build/templates" "$DEST/docs/build/out"
if [ -d "$BOOTSTRAP_TEMPL/docs/build" ]; then
  cp -r "$BOOTSTRAP_TEMPL/docs/build/"* "$DEST/docs/build/" 2>/dev/null || true
fi
echo "  ✓ docs/build/"

# 4. OUTLINE stubs (없을 때만)
for d in book-ko book-en manual-ko manual-en paper-ko paper-en; do
  mkdir -p "$DEST/docs/$d"
  if [ ! -f "$DEST/docs/$d/OUTLINE.md" ] && [ -f "$BOOTSTRAP_TEMPL/docs/$d/OUTLINE.md" ]; then
    cp "$BOOTSTRAP_TEMPL/docs/$d/OUTLINE.md" "$DEST/docs/$d/OUTLINE.md"
  fi
done
mkdir -p "$DEST/docs/paper-ko/sections" "$DEST/docs/paper-en/sections"
mkdir -p "$DEST/docs/manual-ko/chapters" "$DEST/docs/manual-en/chapters"
mkdir -p "$DEST/docs/book-ko/parts" "$DEST/docs/book-en/parts"

# 5. diagrams/
mkdir -p "$DEST/docs/diagrams/mmd" "$DEST/docs/diagrams/svg"
[ -f "$BOOTSTRAP_TEMPL/docs/diagrams/CATALOG.md" ] && [ ! -f "$DEST/docs/diagrams/CATALOG.md" ] && \
  cp "$BOOTSTRAP_TEMPL/docs/diagrams/CATALOG.md" "$DEST/docs/diagrams/CATALOG.md"
[ -f "$BOOTSTRAP_TEMPL/docs/diagrams/puppeteer.json" ] && \
  cp "$BOOTSTRAP_TEMPL/docs/diagrams/puppeteer.json" "$DEST/docs/diagrams/puppeteer.json"
echo "  ✓ docs/diagrams/"

echo ""
echo "=== 설치 완료 ==="
echo ""
echo "검증:"
echo "  cd $DEST"
echo "  make book-ko    # 한국어 책 PDF (~500p stub)"
echo "  make all        # 6 targets × 4 formats"
echo ""
echo "의존성 미설치 시 SKILL.md 의 '시스템 의존성' 섹션 참조."
