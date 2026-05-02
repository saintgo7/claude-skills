#!/usr/bin/env bash
# 사용: bash scaffold.sh <skill-name> "<one-line-description>"
#
# 새 skill 디렉토리 + SKILL.md + README.md 생성.
# frontmatter는 템플릿에서 자동 채움.
# 실행 후 install.sh REGISTRY 등록은 수동.

set -euo pipefail

NAME="${1:-}"
DESC="${2:-TODO: description}"

if [ -z "$NAME" ]; then
  echo "사용: $0 <skill-name> '<description>'"
  exit 1
fi

# 이름 규칙 검증 (소문자/숫자/하이픈, 64자 이내)
if ! echo "$NAME" | grep -qE '^[a-z0-9-]+$'; then
  echo "ERROR: name은 소문자/숫자/하이픈만 허용 — '$NAME'"
  exit 1
fi
if [ "${#NAME}" -gt 64 ]; then
  echo "ERROR: name 64자 초과 (${#NAME}자)"
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$REPO_ROOT/$NAME"
TEMPLATE="$REPO_ROOT/claude-code-skill-authoring/templates/SKILL.md.template"

if [ -d "$DEST" ]; then
  echo "ERROR: $NAME 이미 존재 — _trash로 격리 후 재시도"
  echo "  mv '$DEST' '$REPO_ROOT/_trash/$NAME-$(date +%s)'"
  exit 1
fi

if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: 템플릿 없음 — $TEMPLATE"
  exit 1
fi

mkdir -p "$DEST"
sed "s/__SKILL_NAME__/$NAME/g; s|__ONE_LINE_DESCRIPTION__|$DESC|g; s|__ROLE_DESCRIPTION__|TODO|g" \
  "$TEMPLATE" > "$DEST/SKILL.md"

cat > "$DEST/README.md" << EOF
# $NAME

$DESC

## 사용 시점

- (TODO: 트리거 phrase)

## 설치

\`\`\`bash
./install.sh $NAME
\`\`\`

## 자세한 사용법

[SKILL.md](SKILL.md)
EOF

echo "✓ Created $DEST"
echo ""
echo "다음 단계:"
echo "  1. SKILL.md 본문 작성 (5~10 트리거 phrase, 핵심 명령, 흔한 함정)"
echo "  2. install.sh REGISTRY에 한 줄 추가:"
echo "     \"$NAME|skill|$DESC\""
echo "  3. install/uninstall 검증:"
echo "     mkdir -p /tmp/test-\$\$ && HOME=/tmp/test-\$\$ ./install.sh $NAME"
echo "  4. git add, commit, push"
