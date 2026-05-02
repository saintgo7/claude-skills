# gem-llm-supervisor

GEM-LLM 전체 스택 (vLLM 듀얼 + Gateway + Admin UI) 통합 운영 스킬.

## 사용 시점

- "gem-llm 시작/재시작", "전체 상태 확인"
- "스택 다 내려", "재부팅 후 복구"
- "어떤 서비스가 죽었지"

## 설치

```bash
./install.sh gem-llm-supervisor
```

단일 컴포넌트 디버깅이 아닌 *통합 운영* 용도. 모델 로딩 5분 대기 포함. 명령은 [SKILL.md](SKILL.md) 참조.
