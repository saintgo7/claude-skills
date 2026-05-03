# 자율 라운드 #N 템플릿

> 이 템플릿은 multi-agent-autonomous-loop-pattern의 1 라운드 진행 절차다.
> 라운드별로 복사해 채워 넣고, 라운드 끝에 ScheduleWakeup으로 다음 라운드를 트리거한다.

## 사전 점검 (라운드 시작 직후)

- [ ] 시스템 헬스: `bash scripts/supervisor.sh status` (또는 동등 명령)
- [ ] git 동기화: `git pull --rebase` (양 repo 모두 — gem-llm + claude-skills)
- [ ] 이전 라운드 task 정리: TaskList → 완료된 항목 completed로 마킹
- [ ] STATUS.md 마지막 라운드 번호 확인
- [ ] CHANGELOG.md 미정리 항목 정리 (있으면)
- [ ] 디스크/메모리: `df -h $HOME && free -g` 임계 미만 확인

## 5 에이전트 병렬 디스패치

각 Agent tool 호출은 `subagent_type=general-purpose`로 (plan agent는 권한 부족).

### Agent 1: 메타

산출:
- STATUS.md vN+1 (라운드 N 결과 반영)
- CHANGELOG.md (라운드 N 변경)
- 메모리 인덱스 갱신 (`~/.claude/projects/.../memory/MEMORY.md`)
- 다음 라운드 task 3-5개 plan

### Agent 2: 기능 / skill 추가

산출:
- 새 기능 코드 + 단위 테스트 OR
- 새 skill 디렉토리 (SKILL.md + templates/ + README.md) + install.sh REGISTRY 1줄 동시 commit (atomic)

### Agent 3: 검증

산출:
- pytest smoke / integration 결과
- e2e 또는 부하 검증 (선택)
- 회귀 테스트 결과

### Agent 4: 문서

산출:
- 책 챕터 추가/보강 (한/영)
- 매뉴얼/README 갱신
- case study 1건 (postmortem 형식)

### Agent 5: 옵션

산출 중 1택:
- 성능 튜닝 (vLLM/Gateway 파라미터 + 회귀 측정)
- 부하 회복 검증 (200동접 후 health 정상화)
- 보안 점검 (key rotation, env 격리, pip-audit)
- 운영 cutover 계획 (작성만, 적용은 사용자 승인)

## 에이전트 prompt 공통 규칙

- 절대 경로 명시 (`Write` 도구 출력 경로)
- 200-400단어 보고 강제 (메인 컨텍스트 폭발 방지)
- atomic commit 강제 (install.sh + 디렉토리 동시 staging)
- push 실패 시 `git pull --rebase && git push` retry

## 라운드 종료 후 검증

- [ ] 5 에이전트 보고 수신
- [ ] commit log 확인 (5 에이전트 → 평균 3-7 commits)
- [ ] CI 상태 확인 (claude-skills GitHub Actions)
- [ ] STATUS v(N+1) push 완료
- [ ] 시스템 health 재확인 (cutover 미적용)

## ScheduleWakeup (라운드 마감 직전 호출)

```
ScheduleWakeup(
  delaySeconds=2400,   # 40분 — 캐시 외부 1회로 충분
  prompt="<<autonomous-loop-dynamic>>",
  reason="라운드 N+1 자율 진행 트리거 (5 agent 병렬)"
)
```

- 너무 짧으면 (≤300s) cache miss 누적
- 너무 길면 (≥3600s) 라운드 간 간격 과대
- 검증된 sweet spot: **2400-2700**

## 사용자 인터럽트 처리

- "그만" / "stop loop" → ScheduleWakeup 호출 안 함 (다음 라운드 미트리거)
- "현재 상태" → STATUS.md 마지막 섹션 보고
- "SPEC-N 적용해" → 운영 cutover 승인 (자율 X)
