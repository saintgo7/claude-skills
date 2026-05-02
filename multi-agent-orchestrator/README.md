# multi-agent-orchestrator

Claude Code의 `Agent` tool로 8+ 에이전트를 병렬 디스패치해 대량 작업 (책 1000p, 코드 12K LOC, 문서 50개)을 빠르게 완료하는 검증된 패턴.

## 사용 시점

- "병렬로 작업", "여러 에이전트로"
- "한 번에 빠르게", "대량 문서 작성"
- "전체 멀티 에이전트로", "8 에이전트 동시"
- "ultrathink 병렬"

## 설치

```bash
./install.sh multi-agent-orchestrator
```

에이전트별 출력 경로 지정, 200~400단어 요약 보고, 컨텍스트 폭발 방지, 라운드별 동기화 패턴은 [SKILL.md](SKILL.md) 참조.
