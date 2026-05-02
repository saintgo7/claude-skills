# gem-llm-test-inference

Gemma 4 vLLM endpoint의 추론/tool calling 스모크 테스트 스킬.

## 사용 시점

- "추론 테스트", "tool calling 테스트"
- "vllm 응답 확인", "프롬프트 한 번 돌려봐"
- "OpenAI 클라이언트로 호출", "function calling 검증"
- "스트리밍 확인"

## 설치

```bash
./install.sh gem-llm-test-inference
```

curl + Python (openai SDK) 스크립트, JSON-mode/tool_choice/streaming 변형, transcript 저장 (`_logs/inference-*.jsonl`)은 [SKILL.md](SKILL.md) 참조.
