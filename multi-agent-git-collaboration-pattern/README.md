# multi-agent-git-collaboration-pattern

멀티 에이전트가 동시에 git 작업할 때 발생하는 두 종류 race를 안전하게 자동 회복하는 패턴.

- **case 21** (push non-fast-forward) → `git pull --rebase` + retry
- **case 22** (Edit "modified since read") → grep + Re-Read + Re-Edit
- **never force push** / **atomic commit hook** 두 안전망 결합

## 검증

gem-llm 56h 자율 진행 / 76 라운드 / ~390 에이전트 디스패치 / **force push 0회** / 데이터 손실 0건.

## 파일

- `SKILL.md` — 12 섹션 본문
- `templates/agent-prompt-snippet.md.template` — agent prompt 표준 단락 (3 변형)
- `templates/atomic-pre-commit.sh.template` — atomic commit hook 스크립트
- `CHECKLIST.md` — 신규 skill 추가 / race 회복 / hook 검증

## 설치

```bash
./install.sh multi-agent-git-collaboration-pattern
```

## 관련 skill

- `multi-agent-autonomous-loop-pattern` (자율 루프 동반)
- `production-postmortem-pattern` (case 21 + 22 분석)
- `cicd-github-actions-pattern` (CI atomic 검증)
