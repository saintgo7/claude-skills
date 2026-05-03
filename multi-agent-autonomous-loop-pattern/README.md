# multi-agent-autonomous-loop-pattern

Claude Code 멀티 에이전트 자율 루프 검증된 패턴. 5 agent 병렬 + ScheduleWakeup 40-50min + atomic commit hook으로 8h+ 자율 진행을 안전하게 운영.

## 검증

- gem-llm 프로젝트 55h 무사고 (71 라운드)
- 평균 5 agent / 라운드 × 70 라운드 = ~350 디스패치
- force push 0회
- race condition 1+ 자동 해결 (case 21)
- 새 skill 52 / 책 한 383p, 영 404p / 부하 50/100/200 동접

## 설치

```bash
curl -L https://raw.githubusercontent.com/saintgo7/claude-skills/main/install.sh | bash -s multi-agent-autonomous-loop-pattern
```

## 파일

- `SKILL.md` — 12 섹션 본문
- `templates/round-orchestrator.md` — 1 라운드 진행 템플릿
- `templates/atomic-commit-hook.sh.template` — race 차단 hook
- `CHECKLIST.md` — 라운드별 점검

## 관련

- `multi-agent-orchestrator` — 단일 작업 분할
- `claude-code-skill-authoring` — 새 skill 추가
- `production-postmortem-pattern` — case 분석
- `cicd-github-actions-pattern` — CI 통합
