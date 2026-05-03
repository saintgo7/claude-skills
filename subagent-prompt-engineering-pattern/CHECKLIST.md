# subagent-prompt-engineering-pattern CHECKLIST

서브에이전트 prompt 작성 / 디스패치 / race 발생 시 점검 항목.

## prompt 작성 시 (10 항목)

- [ ] 7 섹션 (컨텍스트 / race 단락 / 출력 / 작업 N / 제약 / 보고) 모두 포함
- [ ] race 대비 표준 단락 그대로 붙여넣음 (force push 금지 명시)
- [ ] 출력 파일 절대 경로 + 라인 수 목표 명시
- [ ] 작업 단계마다 4-tuple ([목적] [명령] [기대] [복구]) 적용
- [ ] atomic commit + push 블록 (`||` retry 1회 포함)
- [ ] 제약 4 항목 (rm -rf / 운영 무수정 / race / atomic) 명시
- [ ] 보고 단어 cap (200-400) 명시
- [ ] description / commit 메시지 ≤1024자 (skill description 한해)
- [ ] 메모리 파일 (`~/.claude/...`) commit 금지 명시
- [ ] 자기 anchor 가 다른 에이전트와 다른지 확인

## 디스패치 시 (5 항목)

- [ ] `subagent_type=general-purpose` (Plan agent X — write 거부됨)
- [ ] 단일 메시지에 N개 Agent tool 호출 (병렬)
- [ ] 각 에이전트 작업 독립 (서로 산출 의존 X)
- [ ] atomic commit hook 활성 (`git config core.hooksPath`)
- [ ] sleep > 60s 사용 시 Monitor / run_in_background 로 교체

## race 발생 시 (5 항목)

- [ ] Edit "modified since read" → grep 확인 + Re-Read + Re-Edit (force write X)
- [ ] push non-fast-forward → pull --rebase + retry (force push X)
- [ ] paused 에이전트 → 새 에이전트 디스패치 또는 메인이 직접 마무리
- [ ] race 회복 후 보고에 "어디서, 어떻게 회복" 명시
- [ ] 사고면 case study 변환 (`production-postmortem-pattern`)
