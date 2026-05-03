# subagent-prompt-engineering-pattern

Claude Code `Agent` tool 서브에이전트 prompt 작성 검증된 7-섹션 패턴. race 대비 + atomic commit + 보고 단어 제한 강제로 60h 530 디스패치 / force push 0 / 자동 race 회복 3건 검증.

## 검증

- gem-llm 60h 자율 루프 ~530 에이전트 디스패치
- force push 0 / 데이터 손실 0
- 평균 라운드 5 agent × 보고 280단어 ≈ 7K 토큰 / 라운드
- 자동 race 회복 3건 (case 21 push / 22 Edit / 23 도구 한계)

## 설치

```bash
curl -L https://raw.githubusercontent.com/saintgo7/claude-skills/main/install.sh | bash -s subagent-prompt-engineering-pattern
```

## 파일

- `SKILL.md` — 13 섹션 본문
- `templates/skill-author-prompt.md.template` — 새 skill 추가 에이전트 prompt
- `templates/test-author-prompt.md.template` — 테스트 보강 에이전트 prompt
- `CHECKLIST.md` — 작성 / 디스패치 / race 점검

## 관련

- `multi-agent-autonomous-loop-pattern` — 5 agent 자율 루프 페이싱
- `multi-agent-git-collaboration-pattern` — git race 회복
- `playbook-authoring-pattern` — 4-tuple 절차
- `claude-code-skill-authoring` — skill 자체 메타
