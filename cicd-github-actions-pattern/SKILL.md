---
name: cicd-github-actions-pattern
description: 'GitHub Actions CI/CD 검증된 패턴 — schema validation + 의존성 audit + atomic commit 강제. 사용 시점 — "github actions", "CI 워크플로", "pip-audit", "schema validation", "weekly cron", "atomic commit". claude-skills 41 run all green 검증.'
---

# cicd-github-actions-pattern

GitHub Actions CI/CD를 처음 셋업하거나 강화할 때 사용하는 검증된 패턴 모음. claude-skills `validate.yml` (41 run, 1 transient failure는 atomic commit 정책 위반 사례) + gem-llm `pip-audit.yml` (첫 push 18s 성공) 운영 경험에서 추출한 것이라, 일반 GitHub repo에도 그대로 적용 가능하다.

## 1. 사용 시점

- "GitHub Actions 셋업해야 한다", "CI 워크플로 작성"
- "schema/lint validation을 PR에서 강제하고 싶다"
- "pip-audit 같은 의존성 스캔을 주간 cron으로 돌리고 싶다"
- "REGISTRY ↔ 디렉토리 같은 cross-reference를 CI에서 검증"
- "atomic commit (관련 파일 묶음 commit)을 강제하고 싶다"
- "workflow 변경 시 re-trigger 누설/cache invalidation 함정 회피"

## 2. 핵심 워크플로 4가지

claude-skills + gem-llm 운영에서 검증된 4종 워크플로. 각각 templates/에 그대로 쓸 수 있는 파일이 있다.

### (1) Schema validation (claude-skills validate.yml 일반화)

PR/push마다 다음을 강제한다:

- **YAML frontmatter parse** — `yaml.safe_load`로 `---` 블록 파싱.
- **name == directory enforce** — `fm['name'] == skill_md.parent.name`. claude-skills에서 디렉토리/REGISTRY 불일치는 install.sh가 fail하므로 CI에서 미리 catch.
- **description ≤ 1024자** — Claude Code skill 제약. name ≤ 64자.
- **bash 문법 (`bash -n`)** — 모든 `*.sh` 파일에 대해. 실행은 안 한다.
- **REGISTRY ↔ 디렉토리 cross-check** — `install.sh`에서 `^\s*"name|type|"` 추출 → 실제 디렉토리 `<name>/SKILL.md` 또는 `commands/<name>.md` 존재 확인.

전체 코드는 `templates/validate.yml.template` 참조.

### (2) 의존성 audit (gem-llm pip-audit.yml 일반화)

```yaml
on:
  push:
    paths: ['requirements*.txt', 'pyproject.toml']
  schedule:
    - cron: '0 9 * * 1'   # 월요일 09:00 UTC
  workflow_dispatch:

jobs:
  audit:
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12', cache: 'pip' }
      - run: pip install pip-audit
      - run: pip-audit -r requirements.txt
        continue-on-error: true   # 차단 X, 정보 제공만
```

**핵심 결정**: `continue-on-error: true`. CVE는 발생 즉시 차단하면 PR 흐름이 막힌다. 대신 GitHub Actions UI 빨간 X로 인지 → `dependency-vulnerability-fix` skill로 별도 처리.

### (3) Test matrix

```yaml
strategy:
  fail-fast: false
  matrix:
    python: ['3.10', '3.11', '3.12']
    os: [ubuntu-latest, macos-latest]
```

`fail-fast: false`가 핵심 — 한 매트릭스가 실패해도 나머지를 계속 돌려 전체 실패 패턴을 본다 (3.10에서만 실패하는지, OS 의존인지 등).

### (4) Atomic commit 검증 (claude-skills CI 1 실패 사례 일반화)

claude-skills는 새 skill 추가 시 `<skill-name>/SKILL.md` 디렉토리와 `install.sh` REGISTRY 한 줄을 **같은 commit**에 넣어야 한다. 분리하면 validate.yml이 fail (case CI 1, 41 run 중 1 transient failure의 정확한 원인).

→ pre-commit hook으로 enforce. 본문 §11 참조.

## 3. trigger 설계

```yaml
on:
  push:
    branches: [main]
    paths:                   # 특정 파일 변경만
      - 'requirements*.txt'
      - '**/*.py'
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 9 * * 1'      # 주간 정기 audit
  workflow_dispatch:          # Actions UI에서 수동 트리거
```

- `paths` 필터로 무관 변경에는 안 돌게 한다 (markdown만 바꿨는데 test 매트릭스가 다 돌면 GHA quota 낭비).
- `workflow_dispatch`는 항상 추가 — 수동 재실행/디버깅에 필수.
- `schedule`은 UTC 기준. 한국 평일 18:00에 돌리려면 `0 9 * * 1-5`.

## 4. permissions 최소화

```yaml
permissions:
  contents: read              # 기본은 읽기만
  # security-events: write    # CodeQL/SARIF upload 시만
  # pull-requests: write      # PR comment 작성 시만
```

GitHub 토큰 기본값(read+write)은 너무 넓다. workflow 단위로 명시 → 사고 시 영향 범위 한정.

## 5. concurrency 제어

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

같은 PR에 push 연타 시 이전 run을 취소 → 마지막 push만 검증. CI quota 절약 + UI 깔끔.

## 6. caching 활용

```yaml
- uses: actions/setup-python@v5
  with:
    python-version: '3.12'
    cache: 'pip'              # requirements.txt hash로 자동 캐싱
    cache-dependency-path: |
      requirements.txt
      requirements-dev.txt
```

`actions/setup-python@v5`의 `cache: pip`이 가장 단순. `actions/cache@v4`로 직접 관리하는 것보다 hash 계산을 자동 처리한다.

## 7. matrix + fail-fast

```yaml
strategy:
  fail-fast: false
  matrix:
    python: ['3.11', '3.12']
    include:
      - python: '3.12'
        coverage: true        # 한 조합에서만 coverage
```

- `fail-fast: false` 기본값 (true는 한 셀 실패 시 전체 즉시 종료 — 디버깅 정보 손실).
- `include`로 특정 조합에만 추가 step.

## 8. continue-on-error vs fail

| 종류 | 정책 | 이유 |
|------|------|------|
| schema validation | fail-fast | 잘못된 YAML은 즉시 차단 |
| test (pytest) | fail | 회귀 차단 |
| pip-audit | `continue-on-error: true` | 정보 제공, PR flow 안 막음 |
| lint warning | `continue-on-error: true` | 점진 개선 |
| coverage threshold | fail | 명시적 기준 강제 |

## 9. notification

- **Slack**: webhook URL을 `secrets.SLACK_WEBHOOK`에 넣고 실패 step에서 `if: failure()` 조건으로 호출.
- **email**: GitHub 기본 — 실패 시 watcher에게 자동 발송.
- **GitHub issue 자동 생성**: `peter-evans/create-issue-from-file@v5` action으로 schedule 실패 시 issue 생성 (cron job 알림용).

## 10. 흔한 함정

1. **secrets를 logs에 노출**: `echo $SECRET`은 `***`로 마스킹되지만, `echo "key=$SECRET"`처럼 다른 텍스트와 섞이면 마스킹 회피되는 경우 있음. `set -x` 금지.
2. **main 외 branch에서도 push trigger**: feature branch마다 CI가 돌면 quota 낭비. PR trigger로 충분 (squash merge 권장).
3. **workflow yaml 자체 변경 시 re-trigger 누설**: `.github/workflows/*.yml` 변경은 다음 push에서야 새 정의가 적용된다. PR이 자기 자신을 검증하려면 `pull_request` trigger 필수.
4. **caching invalidation**: `requirements.txt` hash가 같으면 캐시 재사용 → lock 파일을 명시적으로 갱신해야 새 의존성이 반영된다.
5. **timeout 미설정**: 무한 hang 시 GHA 기본 6시간까지 quota 소진. `timeout-minutes: 10` job 단위로 명시.
6. **Python 3.12 default ctrace coverage 한계 (async/asyncio + httpx ASGI)**: Python 3.12 의 default ctrace coverage tool 이 async/await + httpx ASGI 라인 일부를 미계측한다. 실제로 도달된 라인이 missing 으로 표시됨. → `COVERAGE_CORE=sysmon` 환경변수로 PEP-669 sys.monitoring 사용 (gem-llm 라운드 99-100 발견, admin.py ctrace 60% → sysmon 100%).

| 증상 | 원인 | 해결 |
|------|------|------|
| async route 일부 라인 missing | ctrace 한계 | `COVERAGE_CORE=sysmon` |
| httpx ASGI test 라인 누락 | ctrace 한계 | `COVERAGE_CORE=sysmon` |
| `pytest --cov-fail-under` 가 실측보다 낮게 fail | ctrace 한계 | `COVERAGE_CORE=sysmon` 후 게이트 재조정 |

## 10-1. Python 3.12 async coverage — sysmon 적용 패턴

```yaml
- name: pytest --cov
  env:
    COVERAGE_CORE: sysmon
  run: |
    pytest src/ \
      --cov=src/your_pkg \
      --cov-report=term \
      --cov-fail-under=85
```

**검증**: gem-llm coverage.yml (gateway/cli/admin-ui 3 job). ctrace 78.3% → sysmon 87~97% (admin-ui 97.41%, gateway 87.79%). 게이트는 실측치 -5pt 마진 유지 권장.

## 11. atomic commit 정책 (case CI 1 실패 일반화)

새 skill 추가 시 분리 commit 금지:

```bash
# 금지 (CI 1 실패 패턴):
git commit -m "feat: add new-skill directory"
git commit -m "feat: register new-skill in install.sh"
# → 첫 commit 시점에 validate.yml은 install.sh REGISTRY 누락으로 fail

# 정답:
git add new-skill/ install.sh
git commit -m "feat: add new-skill"
```

pre-commit hook으로 강제:

```bash
#!/bin/sh
# .git/hooks/pre-commit
NEW_SKILL_MDS=$(git diff --cached --name-only --diff-filter=A | grep "/SKILL.md$")
for skill_md in $NEW_SKILL_MDS; do
  name=$(dirname "$skill_md")
  if ! git diff --cached install.sh 2>/dev/null | grep -q "\"$name|"; then
    echo "ERROR: $name 디렉토리 추가했는데 install.sh REGISTRY 누락"
    echo "  같은 commit에 install.sh도 staging 하세요"
    exit 1
  fi
done
```

`.git/hooks/`는 repo에 commit되지 않는다 — `scripts/install-hooks.sh`로 배포하거나 `pre-commit` 프레임워크 사용.

## 12. GEM-LLM / claude-skills 사례 검증

| 워크플로 | 환경 | 결과 |
|----------|------|------|
| claude-skills `validate.yml` | 44 skill, 6 영역 검증 | 41 run, 1 transient failure (atomic commit 위반 1회 후 정책 enforce) |
| gem-llm `pip-audit.yml` | weekly + push trigger | 첫 push 18s 성공, 이후 정기 회귀 |
| atomic commit 정책 | claude-skills 30+ skill 추가 | 정책 enforce 후 사고 0건 |
| gem-llm `coverage.yml` (sysmon) | Python 3.12 async, 3 job | ctrace 78.3% → sysmon 87~97%, 게이트 75/65/75 → 85/68/90 |

`continue-on-error: true`를 pip-audit에 적용했더니 PR flow 차단 없이 CVE 인지 가능 — `dependency-vulnerability-fix` skill로 별도 처리하는 흐름이 안정.

## 13. 관련 skill

- `claude-code-skill-authoring` — skill 작성 시 이 CI를 통과시키는 frontmatter/REGISTRY 룰.
- `dependency-vulnerability-fix` — pip-audit이 잡은 CVE를 patch 업그레이드로 안전 fix하는 4단계.
- `bash-cli-best-practices` — workflow 안에 들어가는 inline bash (`set -euo pipefail`, heredoc) 작성 룰.

## 빠른 시작

```bash
# 1) workflow 파일 복사
mkdir -p .github/workflows
cp ~/.claude/skills/cicd-github-actions-pattern/templates/validate.yml.template \
   .github/workflows/validate.yml
cp ~/.claude/skills/cicd-github-actions-pattern/templates/pip-audit.yml.template \
   .github/workflows/pip-audit.yml

# 2) validate.yml의 검증 로직을 repo 형태에 맞게 수정 (frontmatter, REGISTRY 등)

# 3) 첫 push로 trigger
git add .github/workflows/
git commit -m "ci: add validate + pip-audit workflows"
git push

# 4) Actions 탭에서 결과 확인 → 빨간 X면 로그 보고 수정
```
