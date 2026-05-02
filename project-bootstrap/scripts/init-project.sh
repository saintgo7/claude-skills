#!/usr/bin/env bash
# project-bootstrap — bilingual research/code 프로젝트 한 번에 부트스트랩
# 사용: bash init-project.sh <project-name> [domain]

set -euo pipefail

PROJECT="${1:-}"
DOMAIN="${2:-}"
SKILLDIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES="$SKILLDIR/templates"

if [ -z "$PROJECT" ]; then
  echo "사용: $0 <project-name> [domain]"
  echo "예시: $0 fishing-llm fishing.pamout.com"
  exit 1
fi

DEST="/home/jovyan/wku-vs-01-datavol-1/$PROJECT"
HOME_LINK="/home/jovyan/$PROJECT"

# ===== 1. 디렉토리 구조 =====
echo "[1/8] 디렉토리 구조 생성 ($DEST)"
if [ -d "$DEST" ]; then
  TRASH="/home/jovyan/wku-vs-01-datavol-1/_trash/$PROJECT-old-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$(dirname "$TRASH")"
  mv "$DEST" "$TRASH"
  echo "  기존 → $TRASH 로 격리"
fi

mkdir -p "$DEST"/{src,docs,plan,tests,scripts,_trash,_logs,_data,.github}
mkdir -p "$DEST/docs"/{book-ko/parts,book-en/parts,manual-ko/chapters,manual-en/chapters,paper-ko/sections,paper-en/sections,diagrams/mmd,diagrams/svg,build/templates,build/out}
mkdir -p "$DEST/docs/book-ko/parts"/{part-1,part-2,part-3,part-4,part-5,appendix}
mkdir -p "$DEST/docs/book-en/parts"/{part-1,part-2,part-3,part-4,part-5,appendix}
mkdir -p "$DEST/plan"/{roadmap,specs,decisions}
mkdir -p "$DEST/scripts/pandoc-filters"

# ===== 2. 템플릿 복사 + 프로젝트 이름 치환 =====
echo "[2/8] 템플릿 복사 + 이름 치환"
if [ -d "$TEMPLATES" ]; then
  cp -r "$TEMPLATES"/. "$DEST"/ 2>/dev/null || true
fi

PROJECT_TITLE=$(echo "$PROJECT" | tr '[:lower:]-_' '[:upper:] ')
DATE=$(date +%Y-%m-%d)

# 프로젝트 이름·날짜 일괄 치환
find "$DEST" -type f \( -name "*.md" -o -name "*.tex" -o -name "*.yaml" -o -name "*.toml" -o -name "*.json" -o -name "Makefile" -o -name "*.sh" -o -name "*.lua" \) \
  -exec sed -i \
    -e "s/__PROJECT__/$PROJECT/g" \
    -e "s/__PROJECT_TITLE__/$PROJECT_TITLE/g" \
    -e "s/__DOMAIN__/${DOMAIN:-localhost}/g" \
    -e "s/__DATE__/$DATE/g" \
    {} +

# 심볼릭 링크
ln -sfn "$DEST" "$HOME_LINK"
echo "  심볼릭 링크: $HOME_LINK -> $DEST"

# ===== 3. .gitignore =====
echo "[3/8] .gitignore"
cat > "$DEST/.gitignore" << 'EOF'
__pycache__/
*.py[cod]
*.egg-info/
.venv/
venv/
.pytest_cache/
.mypy_cache/
.ruff_cache/
node_modules/
package-lock.json
docs/build/out/
docs/diagrams/svg/*.svg
*.pdf
*.docx
*.aux
*.log
*.toc
*.out
_data/*.db
_data/*.db-*
_data/*.sqlite-*
_logs/
*.pid
_trash/
.vscode/
.idea/
*.swp
.DS_Store
.env
.env.local
*.key
*.pem
.cache/
EOF

# ===== 4. README =====
echo "[4/8] README"
cat > "$DEST/README.md" << EOF
# $PROJECT

> Bilingual research+code project bootstrapped from project-bootstrap skill ($DATE).

## 구성

- \`src/\` — 코드
- \`docs/\` — 한/영 책, 매뉴얼, 논문, 다이어그램
- \`plan/\` — SPEC, ADR, 로드맵
- \`tests/\` — 단위/통합/부하 테스트

## 빌드

\`\`\`bash
make book-ko book-en      # 한/영 책 PDF
make paper-ko paper-en    # 한/영 논문 (KCI + IEEE)
make all                  # 6 targets × 4 formats
make diagrams             # Mermaid → SVG
\`\`\`

## 외부

- Repo: https://github.com/saintgo7/$PROJECT (Private)
${DOMAIN:+- Domain: https://$DOMAIN}

## License

Internal / Private
EOF

# ===== 5. Git init + commit =====
echo "[5/8] Git init"
cd "$DEST"
if [ ! -d .git ]; then
  git init -q
  git config user.name "saintgo7" 2>/dev/null || true
  git config user.email "saintgo7@wku.ac.kr" 2>/dev/null || true
fi
git add -A
git -c init.defaultBranch=main commit -q -m "feat: initial $PROJECT bootstrap

- Bilingual book skeleton (~500p × 2)
- Bilingual paper templates (KCI + IEEE)
- 40 Mermaid diagram catalog stubs
- Pandoc + XeTeX build pipeline
- 12 SPEC + 3 ADR + roadmap stubs

Bootstrapped via project-bootstrap skill." || echo "  (이미 commit 있음)"

# ===== 6. GitHub (master 통해) =====
echo "[6/8] GitHub repo 생성 + push"
if ssh -o ConnectTimeout=5 master 'echo OK' >/dev/null 2>&1; then
  ssh master "/home/jovyan/.local/bin/gh repo create saintgo7/$PROJECT --private --description '$PROJECT bootstrapped' 2>&1" | head -3 || true
  git branch -M main 2>/dev/null || true
  git remote remove origin 2>/dev/null || true
  git remote add origin "https://github.com/saintgo7/$PROJECT.git"
  if git push -u origin main 2>&1 | tail -3; then
    echo "  ✅ GitHub push 완료"
  else
    echo "  ⚠️  push 실패 — 수동 진행 필요"
  fi
else
  echo "  ⚠️  master SSH 실패 — GitHub 단계 skip. 수동: gh repo create saintgo7/$PROJECT --private"
fi

# ===== 7. Cloudflare DNS =====
if [ -n "$DOMAIN" ]; then
  echo "[7/8] Cloudflare DNS ($DOMAIN)"
  N1_CONFIG=~/.cloudflared/config.yml
  if [ -f "$N1_CONFIG" ]; then
    N1_TUNNEL=$(grep "^tunnel:" "$N1_CONFIG" | awk '{print $2}')
    if ssh -o ConnectTimeout=5 master 'echo OK' >/dev/null 2>&1 && [ -n "$N1_TUNNEL" ]; then
      ssh master "/home/jovyan/.local/bin/cloudflared tunnel route dns $N1_TUNNEL $DOMAIN 2>&1" | head -3 || true
      echo "  ✅ DNS 라우팅 추가됨. n1 cloudflared config 수동 추가 필요 (CHECKLIST.md 참조)"
    else
      echo "  ⚠️  master 접근 또는 tunnel UUID 부재 — 수동 진행"
    fi
  else
    echo "  ⚠️  n1 cloudflared config 없음 — 수동 셋업 필요"
  fi
else
  echo "[7/8] Cloudflare DNS — 도메인 미지정, skip"
fi

# ===== 8. 메모리 자동 작성 =====
echo "[8/8] 메모리 작성"
MEM_DIR=~/.claude/projects/-home-jovyan/memory
if [ -d "$MEM_DIR" ]; then
  cat > "$MEM_DIR/project_$PROJECT.md" << EOF
---
name: project_$PROJECT
description: $PROJECT 프로젝트 (bootstrap $DATE)
type: project
---

$PROJECT — bilingual research+code 프로젝트, project-bootstrap skill로 부트스트랩.

**위치:** /home/jovyan/wku-vs-01-datavol-1/$PROJECT (datavol-1) + ~/$PROJECT 심볼릭

**GitHub:** https://github.com/saintgo7/$PROJECT (Private)
${DOMAIN:+**Domain:** https://$DOMAIN}

**구조:**
- src/, docs/, plan/, tests/, scripts/
- 한/영 책 (5 Part, ~500p 골격)
- 한/영 매뉴얼 (~150p)
- 한/영 논문 (KCI + IEEE)
- 40 Mermaid 다이어그램 stub

**빌드:** make book-ko / book-en / paper-ko / paper-en / all

**Why:** 새 연구개발 프로젝트를 한 명령으로 부트스트랩하기 위한 GEM-LLM 패턴 재사용.

**How to apply:** 일반적인 코드 작업은 src/, 문서는 docs/, 계획은 plan/. 새 챕터/섹션 추가는 OUTLINE.md 업데이트 + 챕터 파일 생성. 빌드는 make.
EOF
  # MEMORY.md 인덱스 추가
  if [ -f "$MEM_DIR/MEMORY.md" ] && ! grep -q "project_$PROJECT.md" "$MEM_DIR/MEMORY.md"; then
    sed -i "/^## Project/a - [project_$PROJECT.md](project_$PROJECT.md) - $PROJECT 프로젝트 (project-bootstrap)" "$MEM_DIR/MEMORY.md"
  fi
  echo "  ✅ 메모리 등록"
else
  echo "  ⚠️  메모리 디렉토리 없음 — skip"
fi

# ===== 완료 =====
echo ""
echo "=== ✅ $PROJECT 부트스트랩 완료 ==="
echo ""
echo "다음 단계:"
echo "  cd $HOME_LINK"
echo "  make diagrams        # 40 SVG 빌드"
echo "  make book-ko         # 한국어 책 PDF"
echo "  vim docs/book-ko/parts/part-1/01-introduction.md  # 본문 작성 시작"
echo ""
echo "수동 단계 (필요 시):"
echo "  - n1 cloudflared config.yml에 ingress 추가 (도메인 사용 시)"
echo "  - 첫 챕터/섹션 본문 채우기"
echo "  - SPEC/ADR 본문 채우기"
echo ""
echo "체크리스트: $SKILLDIR/CHECKLIST.md"
