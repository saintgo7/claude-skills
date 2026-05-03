---
name: multi-agent-autonomous-loop-pattern
description: 'Claude Code 멀티 에이전트 자율 루프 검증된 패턴. 사용 시점 — "autonomous loop", "long-running 자율 작업", "5 agent 병렬", "ScheduleWakeup", "atomic commit hook", "race condition 자동 해결", "55시간 무사고", "/loop dynamic", "백그라운드 진행". 5 agent + ScheduleWakeup 40-50min + atomic commit + 책 case 통합으로 8h+ 자율 진행을 안전하게 운영. gem-llm 71 라운드 / ~350 디스패치 / force push 0회 검증.'
---

# multi-agent-autonomous-loop-pattern

Claude Code의 `Agent` tool로 **5 에이전트를 병렬 디스패치**하고 `ScheduleWakeup`으로 다음 라운드를 트리거해 — **8시간 이상 자율 진행**을 안전하게 운영하는 검증된 패턴. gem-llm 프로젝트에서 55시간 연속 / 71 라운드 / ~350 에이전트 디스패치 / force push 0회로 검증되었다.

## 1. 사용 시점 — 장기 자율 작업 (8h+)

- "전체 자율 진행 멀티 / 백그라운드로" — 사용자 부재 중 진행
- 책 1000p+ 저작, skill 50+ 추가, case study 20+ 정리 등 라운드별 누적 작업
- 단일 작업이 아닌 **다축 병렬** (메타·기능·검증·문서·옵션)
- "/loop dynamic" 모드 (자체 페이싱 — `<<autonomous-loop-dynamic>>` 트리거)
- 운영 중인 시스템 옆에서 누적 개선 (cutover는 사용자 승인 분리)

**이 skill 비대상**:
- 단일 작업 분할 (→ `multi-agent-orchestrator`)
- 한 라운드짜리 (→ Agent tool 직접)
- 운영 변경 자율 (→ SPEC + 사용자 승인 분리)

## 2. 핵심 아키텍처

```
사용자 첫 메시지 ──▶ 5 Agent 병렬 ──▶ ScheduleWakeup
                                          │
   ┌──────────────────────────────────────┘
   ▼
다음 라운드 ◀── <<autonomous-loop-dynamic>> 트리거
   │
   ▼
5 Agent 병렬 ──▶ ScheduleWakeup ──▶ ...
```

라운드 간 상태는 **git repo 자체**가 보관 (commit log + STATUS.md + CHANGELOG.md). 메모리는 `~/.claude/projects/<path>/memory/MEMORY.md` 인덱스로 관리.

## 3. 라운드 구조 (검증된 5 agent / 라운드)

| # | 역할 | 산출 예시 |
|---|------|-----------|
| 1 | **메타** | STATUS.md / CHANGELOG.md / 메모리 갱신 / 다음 라운드 plan |
| 2 | **기능 추가** | gem-llm 기능 확장, 새 skill, 새 SPEC |
| 3 | **검증** | smoke test, integration test, e2e, 부하 검증 |
| 4 | **문서** | 책 챕터, 매뉴얼, README, case study |
| 5 | **옵션** | 성능 튜닝, 보안 점검, 부하 회복 검증 |

각 에이전트 prompt 끝에 200-400단어 보고 강제 (→ `multi-agent-orchestrator` 원칙 재사용).

## 4. ScheduleWakeup 설정

- `delaySeconds`: **2400-2700** (40-45분)
  - 캐시 TTL 5분 외부지만, 1 cache miss로 충분히 큰 라운드 분량 보상
  - 너무 짧으면 (300s) cache miss × N회 누적
- `prompt`: `<<autonomous-loop-dynamic>>` 사용 (자율 루프 sentinel)
- `reason`: 한 문장으로 "라운드 N+1 자율 진행 트리거" 명시

## 5. atomic commit hook (필수 — race 자동 해결)

```bash
# .githooks/pre-commit
# install.sh REGISTRY entry + skill 디렉토리 SKILL.md가 같은 commit에 안 들어가면 reject
```

병렬 에이전트가 **같은 install.sh를 동시 수정**할 때 race가 발생한다. atomic hook이 두 가지를 강제:

1. 새 `<skill>/SKILL.md` 추가 → install.sh REGISTRY entry 동시 추가 필수
2. 새 REGISTRY entry → 디렉토리/SKILL.md 동시 존재 필수

→ **부분 commit 차단**으로 race가 데이터 손상으로 이어지지 않음. CI에서 동일 검증 1회 더 (`cicd-github-actions-pattern` 통합).

템플릿: `templates/atomic-commit-hook.sh.template`

## 6. race condition 자동 회복 (case 21 일반화)

전형적 시나리오:

1. Agent A: install.sh + skillA/ commit → push 성공
2. Agent B: install.sh + skillB/ commit → push 거부 (non-fast-forward)
3. Agent B 자동 회복:
   ```
   git pull --rebase origin main
   # rebase 충돌 없으면 곧바로 push retry → 성공
   # 충돌 시 install.sh REGISTRY 라인만 재정렬 후 push
   ```
4. **force push 불필요** — hook + rebase가 자동 처리, 데이터 손실 0

이 절차를 모든 commit 절차에 디폴트로 (`git push || (git pull --rebase && git push)`).

## 7. 메모리 정책 (auto-memory)

- 위치: `~/.claude/projects/<path>/memory/MEMORY.md` (인덱스) + 개별 파일
- 4 타입: `project_*` / `feedback_*` / `user_*` / `reference_*`
- **commit 금지** — 외부 파일 (repo 밖)
- `.gitignore`에 명시적으로 안 들어가지만, 절대 경로가 외부라 자연 격리

`CLAUDE.md`에 `IMPORTANT: 메모리는 외부 ~/.claude/ 아래 — repo 안에 commit 금지` 명시.

## 8. 운영 무수정 원칙

자율 루프가 운영 시스템을 침해하지 않도록:

- **cutover 도구는 작성만** — `scripts/cutover.sh`, SPEC 등을 만들고 실제 적용은 사용자 승인 (`"SPEC-N 적용해"`)
- **부하 테스트 후 회복 검증** 필수 — 200동접 테스트 후 health check, supervisor status, log tail
- **env 격리** — `env-isolation-pattern` 적용 (테스트가 prod env 누설 X)
- **DB 백업 후 마이그레이션** — `postgres-migration-from-sqlite` 패턴 따라

## 9. 검증된 통계 (gem-llm 55h)

| 지표 | 수치 |
|------|------|
| 총 라운드 | 71 |
| 평균 에이전트 / 라운드 | 5 |
| 총 에이전트 디스패치 | ~350 |
| 무사고 시간 | 55h 연속 |
| force push | 0 |
| race condition 자동 해결 | 1+ (case 21) |
| 추가된 skill | 52 |
| 책 페이지 | 한 383 / 영 404 |
| 부하 검증 | 50/100/200 동접 + sustained 5R 100% |
| 통합 테스트 | 220+ |
| commit | 67 |

## 10. 사용자 인터페이스

| 입력 | 의미 |
|------|------|
| `<<autonomous-loop-dynamic>>` | 자율 루프 트리거 (ScheduleWakeup이 주입) |
| "현재 상태" / "status" | 메인 컨텍스트에서 STATUS.md 보고 |
| "SPEC-N 적용해" | 운영 변경 사용자 승인 |
| "전체 자율 진행 멀티" | 다중 에이전트 자율 모드 시작 |
| "stop loop" / "그만" | ScheduleWakeup 취소 (다음 라운드 prompt 미스케줄) |

## 11. 흔한 함정

| 증상 | 원인 | 해결 |
|------|------|------|
| race condition force push | atomic hook 없음 | `.githooks/pre-commit` 의무 |
| 메모리 commit 사고 | 정책 부재 | gitignore + CLAUDE.md 명시 |
| 운영 변경 자율 적용 | 승인 절차 없음 | SPEC 작성 + 사용자 명시 승인 |
| 부하 후 시스템 손상 | 회복 검증 X | 모든 부하 후 health check |
| Plan agent로 작성 시도 | 권한 부족 | `general-purpose` agent 사용 |
| 라운드별 파일 충돌 | 출력 경로 모호 | 에이전트별 절대 경로 명시 |
| 컨텍스트 폭발 | 보고 미강제 | 200-400단어 요약 강제 |
| ScheduleWakeup 누락 | 마지막에 호출 안 함 | 라운드 마감 직전 ScheduleWakeup 호출 |

## 12. 관련 skill

- `multi-agent-orchestrator` — 단일 작업 분할 (이 skill의 라운드 1회분)
- `claude-code-skill-authoring` — 새 skill 추가 패턴
- `production-postmortem-pattern` — case 분석 및 책 통합
- `cicd-github-actions-pattern` — CI에서 atomic 검증 1회 더
- `concurrent-load-testing-pattern` — 부하 검증 라운드
- `env-isolation-pattern` — 운영 누설 방지

## 빠른 시작

1. `.githooks/pre-commit` 설치 (`templates/atomic-commit-hook.sh.template`)
2. `git config core.hooksPath .githooks`
3. CI에 동일 검증 추가 (`cicd-github-actions-pattern`)
4. 첫 라운드 디스패치 (`templates/round-orchestrator.md` 따라 5 에이전트)
5. 라운드 끝에 `ScheduleWakeup(delaySeconds=2400, prompt="<<autonomous-loop-dynamic>>")`
6. 무사고 누적 — STATUS.md / CHANGELOG.md로 라운드별 상태 확인
