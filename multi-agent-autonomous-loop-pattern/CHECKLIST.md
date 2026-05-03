# multi-agent-autonomous-loop-pattern CHECKLIST

자율 루프 1 라운드 진행 시 점검 항목.

## 라운드 시작 전

- [ ] 시스템 헬스 정상 (supervisor / health endpoint)
- [ ] 양 repo `git pull --rebase` 완료
- [ ] 디스크/메모리 임계 미만 (`df -h`, `free -g`)
- [ ] 이전 라운드 task 정리 (TaskList 상태 확인)
- [ ] STATUS.md 마지막 라운드 번호 확인
- [ ] CI green (claude-skills GitHub Actions)
- [ ] atomic commit hook 활성 (`git config core.hooksPath` = `.githooks`)

## 에이전트 디스패치 시 주의사항

- [ ] `subagent_type=general-purpose` (plan agent X — 권한 부족)
- [ ] 에이전트별 절대 출력 경로 명시
- [ ] 200-400단어 보고 강제 (컨텍스트 폭발 방지)
- [ ] install.sh + 디렉토리 동시 commit (atomic)
- [ ] push 실패 시 `git pull --rebase && git push` 디폴트
- [ ] 메모리 파일 절대 commit 금지 (`~/.claude/...`)
- [ ] 운영 cutover는 작성만 (적용 X — 사용자 승인 필요)

## 라운드 종료 후 검증

- [ ] 5 에이전트 보고 모두 수신
- [ ] commit log 정상 (3-7 commits 평균)
- [ ] CI run green
- [ ] STATUS.md / CHANGELOG.md 갱신 push
- [ ] 시스템 health 재확인 (cutover 발생 안 함)
- [ ] race 발생 시 force push 0 확인
- [ ] ScheduleWakeup 호출 (`delaySeconds=2400-2700`, `prompt=<<autonomous-loop-dynamic>>`)

## 사용자 인터럽트 시

- [ ] "그만" / "stop" → ScheduleWakeup 미호출
- [ ] "현재 상태" → STATUS 보고만 (다음 라운드 진행 X)
- [ ] "SPEC-N 적용해" → 자율 X, 사용자 명령으로 cutover

## 사고 발생 시

- [ ] 즉시 ScheduleWakeup 취소 (다음 라운드 미트리거)
- [ ] postmortem 작성 (`production-postmortem-pattern` 형식)
- [ ] 책 case study로 통합
- [ ] 재발 방지 — atomic hook 강화 / CI 검증 추가
