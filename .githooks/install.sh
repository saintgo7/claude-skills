#!/usr/bin/env bash
# claude-skills git hooks 설치 (사용자 옵션)
# 사용: bash .githooks/install.sh
#
# 효과: git config core.hooksPath .githooks
#   → 이후 commit 시 .githooks/pre-commit 실행
#   → atomic REGISTRY <-> 디렉토리 검증으로 case CI transient failure 회피

set -e

git config core.hooksPath .githooks
chmod +x .githooks/pre-commit
echo "pre-commit hook 활성화 (.githooks/pre-commit)"
echo "비활성화: git config --unset core.hooksPath"
