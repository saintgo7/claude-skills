---
name: multi-agent-git-collaboration-pattern
description: '멀티 에이전트 동시 git 작업 race condition 안전 회복 패턴. 사용 시점 — "multi-agent git", "concurrent file edits", "Edit modified since read", "git push race", "non-fast-forward 자동 회복", "atomic commit hook", "force push 회피", "claude code 병렬 에이전트". case 21 (push race) + case 22 (Edit race) 두 안전망 결합 + 56h 검증.'
---

# multi-agent-git-collaboration-pattern

Claude Code의 N 에이전트 병렬 작업 중 **두 종류 race**를 안전하게 자동 회복하는 패턴. gem-llm 프로젝트 56시간 / 76 라운드 / ~390 디스패치에서 **force push 0회 / 데이터 손실 0건**으로 검증되었다. case 21 (push race) + case 22 (Edit "modified since read" race) 두 사례를 일반화한 두 안전망 결합 패턴.

## 1. 사용 시점

- N 에이전트 병렬 작업이 **같은 파일** 수정 (install.sh REGISTRY, README, CHANGELOG, OUTLINE 등)
- 같은 git remote에 동시 push (Claude Code 멀티 디스패치, CI matrix runner, 협업자 다수)
- `multi-agent-autonomous-loop-pattern` 자율 루프 동반 운영
- "force push로 덮어쓸까?" 유혹이 들 때 **반드시 이 skill로 대체**

**비대상**: 단일 에이전트 작업, lock 기반 협업 (DB transaction), 전혀 겹치지 않는 파일.

## 2. 두 종류 race + 두 안전망

| race 종류 | 발생 단계 | 안전망 | 회복 |
|---|---|---|---|
| Edit "modified since read" | 파일 편집 | Claude Code Read-Edit consistency | grep + Re-Read + Re-Edit |
| push non-fast-forward | git push | atomic commit hook + git pull --rebase | rebase + retry |

두 race는 **완전 다른 단계**에서 발생하며 **서로 보완**한다. Edit race는 *작업 중* 차단되고, push race는 *공유 단계*에서 차단된다. 두 안전망 모두 **자동 회복 가능**하며 force push 없이 처리된다.

## 3. push race 회복 (case 21 패턴)

```bash
# Agent A 가 먼저 install.sh REGISTRY 추가 + push
# Agent B 의 push 는 거부 (non-fast-forward) → 즉시:
git pull --rebase origin main

# rebase 후 atomic commit hook 가 diff 비어있다고 거부할 수도 있음 (드물게):
# 그 경우 의도적 미세 갱신 (description tweak) 으로 diff 생성
git push origin main
```

핵심 원칙:

- **never force push** — `git push --force` / `+main` / `--force-with-lease` 모두 금지
- atomic commit hook 가 간섭하면 **추가 의도적 변경**으로 우회 (case 21)
- rebase conflict 발생 시 **둘 다 보존** (양쪽 카테고리 entry 모두 살림)
- retry는 **1-2회**로 충분 (race가 길게 누적되면 라운드 단위 재진입)

## 4. Edit race 회복 (case 22 패턴)

다른 에이전트가 같은 파일 수정 후, 본인의 Edit이 "modified since read"로 거부될 때:

```python
# Agent B 의 Edit 거부 시:
# 1. grep으로 다른 에이전트가 무엇을 추가했는지 확인
grep -n "<other-agent-pattern>" file.txt

# 2. Read tool 재실행 (최신 파일 상태 확보)
# 3. 자기 anchor 영향 없음 확인 (다른 line 에 추가됐는지)
# 4. Edit tool 재시도 → 성공
```

핵심 원칙:

- **never panic / no force overwrite** — Write tool로 전체 덮어쓰기 금지
- 자기 anchor + 다른 에이전트 anchor 가 **다른 위치**면 Re-Read + Re-Edit 만으로 충분
- 같은 위치 충돌은 §7 anchor 분리로 사전 회피
- grep으로 변경 내용 먼저 파악 → blind retry 금지

## 5. 에이전트 프롬프트 표준 — race 대비 한 단락

매 skill-author / 멀티 에이전트 prompt에 다음 한 단락 **반드시** 포함 (`templates/agent-prompt-snippet.md.template` 참조):

```
**중요 (race 대비)**: install.sh 다른 에이전트와 병렬 수정.
- Edit "modified since read" 시 → grep으로 변경 확인 + Read 재실행 + Edit 재시도
- push 거부 시 → git pull --rebase + retry (rebase 후 diff 비어있으면 description 미세 갱신으로 우회)
- force push 절대 금지
- 자기 anchor (예: production-postmortem 다음) 는 다른 에이전트 anchor 와 다르게 잡기
```

이 단락이 prompt에 들어가면 에이전트가 **자율적으로** race 회복을 시도하므로 사용자 개입이 불필요하다. gem-llm 76 라운드에서 사용자 개입 0회.

## 6. atomic commit hook (필수)

`.githooks/pre-commit`:

```bash
# 새 SKILL.md 가 staging 됐으면 install.sh REGISTRY 도 staging 됐어야 함
NEW_SKILLS=$(git diff --cached --name-only --diff-filter=A | grep -E '^[^/]+/SKILL\.md$' | xargs -I {} dirname {})

errors=0
for skill in $NEW_SKILLS; do
  if ! git diff --cached install.sh 2>/dev/null | grep -qE "^\+\s*\"$skill\|"; then
    echo "ERROR: '$skill/' 추가됐지만 install.sh REGISTRY 누락"
    errors=$((errors+1))
  fi
done
[ "$errors" -eq 0 ] || exit 1
echo "atomic commit OK"
```

각 노드 활성화: `git config core.hooksPath .githooks` (1회). + CI에서 동일 검증 (PR 단계, §8).

전체 템플릿: `templates/atomic-pre-commit.sh.template`.

## 7. anchor 분리 전략

여러 카테고리별로 anchor 분리하면 **위치 충돌이 0에 수렴**한다:

```
# REGISTRY 카테고리 (skill 추가 시 자기 카테고리 마지막 다음에)
"meta-skill-1|skill|..."         ← 메타 anchor
"meta-skill-2|skill|..."
...
"infra-skill-1|skill|..."        ← 인프라 anchor
"infra-skill-2|skill|..."
...
"pattern-skill-1|skill|..."      ← 패턴 anchor
"pattern-skill-2|skill|..."
```

각 에이전트가 **자기 카테고리** 마지막 줄 다음에 추가 → 동시에 다른 카테고리에 추가하는 경우 anchor가 겹치지 않아 **Edit 충돌 자체가 발생하지 않는다**. 같은 카테고리 동시 추가만 race 대상이며, 이 경우만 §4로 처리.

## 8. PR 단계 CI 검증

local pre-commit hook은 우회 가능 (`--no-verify`)하므로 **CI에서 한번 더** 검증 필수:

```yaml
- name: Atomic commit check
  run: |
    BASE_SHA="${{ github.event.pull_request.base.sha }}"
    NEW=$(git diff --name-only --diff-filter=A "$BASE_SHA"...HEAD | grep -E "^[^/]+/SKILL\.md$" | xargs -I {} dirname {})
    for skill in $NEW; do
      git diff "$BASE_SHA"...HEAD install.sh | grep -qE "^\+\s*\"$skill\|" || (echo "atomic 위반: $skill"; exit 1)
    done
```

`cicd-github-actions-pattern` skill에 통합 (claude-skills 41+ run green).

## 9. 검증 메트릭 (gem-llm 56h 자율 진행)

| 지표 | 수치 |
|---|---|
| 라운드 | 76 |
| 평균 에이전트/라운드 | 5 |
| 총 디스패치 | ~390 |
| **force push** | **0** |
| **데이터 손실** | **0** |
| Edit race 자동 회복 | 1+ (case 22) |
| Push race 자동 회복 | 1+ (case 21) |
| 무사고 시간 | 56h |
| atomic commit hook 통과 | 모든 push |

## 10. 흔한 함정

| 증상 | 원인 | 해결 |
|---|---|---|
| force push 유혹 | non-fast-forward 회복 모름 | git pull --rebase |
| Edit 거부 후 즉시 force overwrite | "modified since read" 의미 모름 | grep + Re-Read |
| 같은 anchor 충돌 | anchor 정책 X | 카테고리 분리 (§7) |
| atomic hook 비활성 | hooks 미설치 | `git config core.hooksPath .githooks` |
| race 검출 늦음 | CI 만 의존 | local pre-commit hook 추가 |
| diff 비어 commit 실패 | rebase 후 변경 사라짐 | 의도적 description tweak |
| 메모리 commit 사고 | gitignore X | 메모리 외부 파일 |
| 부하 후 시스템 손상 | 회복 검증 X | 모든 부하 후 health check |

## 11. ScheduleWakeup 와의 결합

자율 루프 (`<<autonomous-loop-dynamic>>`) 에서 매 라운드 5+ 에이전트 디스패치. 이 skill의 패턴이 **모든 라운드에 적용**되어 — 76 라운드 검증된 안정성을 제공한다. 자율 루프 자체는 `multi-agent-autonomous-loop-pattern`이 담당하고, 이 skill은 **그 안의 git 공유 단계**만 다룬다.

## 12. 관련 skill

- `multi-agent-autonomous-loop-pattern` — 자율 루프 (이 skill을 포함)
- `production-postmortem-pattern` — case 21 + 22 분석 절차
- `cicd-github-actions-pattern` — CI atomic 검증
- `claude-code-skill-authoring` — skill 작성 메타
