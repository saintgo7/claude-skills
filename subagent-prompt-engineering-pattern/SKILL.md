---
name: subagent-prompt-engineering-pattern
description: 'Claude Code Agent tool 서브에이전트 prompt 작성 패턴. 사용 시점 — "subagent prompt", "Agent tool", "claude code agent dispatch", "병렬 에이전트", "general-purpose agent", "race 대비 prompt", "보고 형식". 명확한 출력 + race 대비 + atomic commit + 보고 단어 제한. 60h 530 디스패치 검증.'
---

# subagent-prompt-engineering-pattern

Claude Code 의 `Agent` tool 로 **서브에이전트를 디스패치할 때** 매 호출에 그대로 붙여 쓸 수 있는 prompt 템플릿. gem-llm 60시간 자율 루프에서 ~530 디스패치 / force push 0 / 자동 race 회복 3건으로 검증되었다.

이 skill 은 멀티 에이전트 *오케스트레이션* (라운드 구성·페이싱) 이 아니라 **단일 에이전트 prompt 의 본문 작성** 에 초점을 둔다. 라운드 페이싱은 `multi-agent-autonomous-loop-pattern`, git race 회복은 `multi-agent-git-collaboration-pattern`, 절차서 작성은 `playbook-authoring-pattern` 을 본다.

## 1. 사용 시점

Claude Code 의 `Agent` tool 로 subagent 를 디스패치하는 모든 경우. 특히:

- 5+ 병렬 에이전트 동시 디스패치 (단일 메시지 다중 tool call)
- 자율 루프 (`multi-agent-autonomous-loop-pattern`) 의 라운드 내 5 agent
- skill 작성 / 테스트 추가 / 책 case 추가 / 문서 업데이트 같은 표준 작업
- atomic commit + push 가 필요한 협업 repo 작업
- 200-400단어 짜리 짧은 보고만 메인 컨텍스트로 받아야 할 때

**비대상**: 단일 작업 분할 디스패치 (→ `multi-agent-orchestrator`), Plan-only 조사 (→ Plan agent — 단, write 권한 없음 주의), 운영 변경 자율 (→ SPEC + 사용자 승인 분리).

## 2. Prompt 구조 표준 (7 섹션)

매 prompt 는 다음 7 섹션을 순서대로 갖는다.

```markdown
**컨텍스트:** <상위 라운드 / 프로젝트 한 단락>
**중요 (race 대비):** <표준 단락 — 섹션 3 그대로 붙여넣기>
**출력 파일 (N):** <절대 경로 + 라인 수 N개>
**작업 1:** <목적 / 명령 / 기대 출력>
**작업 2:** ...
...
**제약:** <rm -rf 금지 / atomic commit / 운영 무수정 등>
**완료 후 보고 (XXX단어 이내):** <핵심 항목 5-7개 bullet>
```

이 7 섹션이 **모두 있는** prompt 는 race 자동 회복률 ~99%, 보고 평균 250-400단어. 하나라도 빠지면 회복률 / 컨텍스트 효율 모두 떨어진다.

## 3. race 대비 표준 단락 (필수)

다음 단락은 **모든 prompt 에 그대로** 붙여 넣는다 (자기 anchor 부분만 교체).

```markdown
**중요 (race 대비)**: 다른 에이전트와 병렬로 install.sh / OUTLINE 수정 가능.
- Edit "modified since read" 시 → grep 으로 변경 확인 + Read 재실행 + Edit 재시도
- push 거부 시 → git pull --rebase + retry (rebase 후 diff 비어있으면 description 미세 갱신으로 우회)
- force push 절대 금지
- 자기 anchor (예: <카테고리> 다음) 는 다른 에이전트 anchor 와 다르게 잡기
```

이 단락이 없으면 ~5% 라운드에서 race 발생 시 에이전트가 force push 유혹에 빠지거나 무한 retry 로 stall 한다. gem-llm 60h 의 force push 0 기록은 이 단락 강제 덕분이다.

변형 3종 (claude-skills repo / OUTLINE / 일반 협업) 은 `multi-agent-git-collaboration-pattern/templates/agent-prompt-snippet.md.template` 참조.

## 4. 출력 파일 명확화

prompt 는 **만들 파일 N개 + 각 라인 수 목표** 를 명시한다.

```markdown
**출력 파일 (4):**
1. `/home/jovyan/claude-skills/<name>/SKILL.md` (~250 lines)
2. `/home/jovyan/claude-skills/<name>/templates/<x>.md.template` (~80 lines)
3. `/home/jovyan/claude-skills/<name>/CHECKLIST.md` (~40 lines)
4. `/home/jovyan/claude-skills/<name>/README.md` (~25 lines)
+ install.sh REGISTRY 1줄 추가 (current 60 → +1 = 61 entries)
```

라인 수는 **목표** — 정확히 일치할 필요 없다. ±20% 범위면 충분. 너무 짧거나 길면 보고 단계에서 발견되어 다음 라운드에 보강할 수 있다.

절대 경로 명시 = 에이전트가 cwd 추측을 안 한다. (서브에이전트는 매 Bash 호출마다 cwd 가 리셋됨.)

## 5. 작업 단계 (4-tuple 적용)

각 작업 단계는 `playbook-authoring-pattern` 의 4-tuple 을 따른다.

```markdown
**작업 2: install.sh REGISTRY 1줄 추가**

[목적] new skill 을 install.sh 에서 노출
[명령]
  cd /home/jovyan/claude-skills && git pull --rebase origin main
  Edit install.sh → REGISTRY 배열 끝에 1줄 추가
[기대 출력] grep -c '^  "' install.sh → 61
[실패 복구] "modified since read" 시 → Read 재실행 + Edit 재시도
```

복잡한 작업은 4-tuple 풀 형태, 단순한 작업은 [명령] 만 inline. 4-tuple 이 명시되면 에이전트가 실패 단계에서 *재량 행동* 을 줄인다.

## 6. atomic commit + push 절차

prompt 끝부분은 항상 다음 절차를 명시한다.

```bash
cd /path/to/repo && git pull --rebase origin main
git add <자기 변경 파일들 명시>          # NOT git add . / -A
git commit -m "<conventional commit>"
git push origin main || (git pull --rebase origin main && git push origin main)
```

핵심 3 가지:

1. **pull --rebase 먼저** — 에이전트 작업 시작 시 / commit 후 push 직전 양쪽 모두
2. **자기 변경 파일만 add** — `git add .` / `-A` 는 다른 에이전트 작업을 누설할 수 있다 (atomic 위반)
3. **`||` retry 한 번** — 실패 시 자동 rebase + push (force push 절대 금지)

atomic commit hook (`multi-agent-git-collaboration-pattern/templates/atomic-pre-commit.sh.template`) 을 활성화하면 install.sh 추가와 디렉토리 commit 이 누락되었을 때 차단된다.

## 7. 제약 표준 (필수)

prompt 끝의 **제약** 섹션은 4 항목 미니멈.

```markdown
**제약:**
- `rm -rf` 금지 (대신 `_trash/` 격리 — 메모리 파일 참조)
- 운영 무수정 (코드 변경 X, spec / skill / test / docs 만)
- race 대비 (다른 에이전트 병렬 — 위 단락 따름)
- atomic commit (자기 변경만 add — git add . X)
```

프로젝트별 추가 제약 (예: gem-llm 의 description ≤1024자, 메모리 파일 commit 금지) 은 여기 추가.

## 8. 보고 형식

```markdown
**완료 후 보고 (XXX단어 이내):**
- 출력 파일 라인 수 (N개 모두)
- 핵심 결과 1-2 줄 (skill 의 핵심 가치)
- REGISTRY entry 변화 (current → new count)
- commit hash + push 성공 여부
- race 발생 여부 (Edit / push 어디서, 어떻게 회복)
- 제약 준수 확인 (rm -rf 0, force push 0, 자기 변경만)
- 다음 라운드 권장 (선택)
```

단어 제한은 200-400 사이. 보고가 길어지면 메인 컨텍스트가 5 에이전트 × 1000단어 = 5K 토큰으로 비대해진다. 250단어가 sweet spot.

## 9. 흔한 실패 패턴

| 증상 | 원인 | 해결 |
|---|---|---|
| Edit "modified since read" | 다른 에이전트 병렬 race | grep 확인 + Re-Read + Re-Edit |
| push non-fast-forward | 다른 에이전트 push 선행 | pull --rebase + retry |
| sleep 후 paused | Monitor 미사용 | sleep 짧게 (60s 이하) 또는 즉시 진행 |
| Plan agent 가 write 거부 | 권한 부족 (case 7) | `subagent_type=general-purpose` |
| SendMessage 미지원 | 도구 deferred | 새 에이전트 디스패치 또는 직접 마무리 |
| install.sh REGISTRY 누락 | atomic 위반 | atomic commit hook 활성화 |
| 다른 에이전트 작업 누설 | `git add .` 사용 | 명시 파일만 `git add <files>` |
| 보고 너무 김 | 단어 제한 미강제 | prompt 에 단어 cap 명시 |

`paused` 위험은 특히 sleep > 60s 일 때 — `Monitor` 또는 `Bash run_in_background` 로 대체할 것.

## 10. 디스패치 패턴 (5 agent / 라운드)

자율 루프 1 라운드 표준은 5 에이전트 병렬:

```python
# 단일 메시지에 5개 Agent tool 호출 (병렬 — 독립 작업)
agents = [
    {"description": "Meta (STATUS/CHANGELOG/memory)",   ...},
    {"description": "기능 / skill 추가",                  ...},
    {"description": "검증 (smoke/e2e/coverage)",         ...},
    {"description": "문서 (책/매뉴얼/README)",            ...},
    {"description": "옵션 (부하/보안/성능)",              ...},
]
```

각 에이전트는 **독립 작업** (서로의 산출에 의존 X), atomic commit hook 으로 race 자동 처리. 의존이 있으면 라운드를 쪼갠다 (라운드 N → N+1).

## 11. 검증된 사례 (gem-llm 60h)

- ~530 디스패치 (라운드 ~106 × 5 agent)
- force push 0 / 데이터 손실 0
- 평균 라운드 처리 시간 ~30분 (디스패치 → 5 에이전트 보고 수신)
- 새 skill 60 / 책 23 cases / 코드 +33 commits
- 자동 race 회복 3건 (case 21 push, case 22 Edit, case 23 도구 한계 detour)
- 컨텍스트 효율: 5 보고 × 평균 280단어 ≈ 7K 토큰 / 라운드

## 12. 관련 skill

- `multi-agent-autonomous-loop-pattern` — 5 에이전트 자율 루프 페이싱
- `multi-agent-git-collaboration-pattern` — git race 자동 회복 (atomic hook + Edit / push 회복)
- `multi-agent-orchestrator` — 단일 작업 분할 (1 task → N agent)
- `playbook-authoring-pattern` — 4-tuple 절차 작성
- `claude-code-skill-authoring` — skill 자체 메타 작성 (frontmatter / REGISTRY / install)
- `production-postmortem-pattern` — 사고 case 변환

## 13. 빠른 시작

1. `templates/skill-author-prompt.md.template` 복사 → 자리표시자 (`<NAME>` / `<DESC>`) 채움
2. 단일 메시지에 5개 `Agent` tool 호출 (각 prompt 끝에 race 단락 + 보고 cap 포함)
3. 보고 5건 수신 → race 발생 여부 확인 → 다음 라운드 / 종료 판단
4. CHECKLIST.md 점검 후 `ScheduleWakeup` (자율) 또는 사용자 보고 (수동)
