# cicd-github-actions-pattern

GitHub Actions CI/CD 검증된 패턴 — claude-skills `validate.yml` (41 run) + gem-llm `pip-audit.yml` 운영 경험.

## 사용 시점

- "GitHub Actions 셋업" / "CI 워크플로 작성"
- "schema validation" / "pip-audit weekly" / "atomic commit 강제"

## 설치

```bash
./install.sh cicd-github-actions-pattern
```

## 빠른 시작

```bash
mkdir -p .github/workflows
cp ~/.claude/skills/cicd-github-actions-pattern/templates/*.template .github/workflows/
# 확장자 .template 제거 후 repo 형태에 맞게 수정
```

## 자세한 사용법

[SKILL.md](SKILL.md)
