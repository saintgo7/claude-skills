---
name: gem-llm-test-inference
description: Run inference and tool-calling smoke tests against the GEM-LLM Gemma 4 vLLM endpoint. Use when the user says "추론 테스트", "tool calling 테스트", "vllm 응답 확인", "프롬프트 한 번 돌려봐", "OpenAI 클라이언트로 호출", "function calling 검증", "스트리밍 확인". Builds curl commands and short Python (openai SDK) scripts targeting localhost:8000/v1/chat/completions. Includes JSON-mode, tool_choice=auto, and streaming variants. Saves transcripts to /home/jovyan/gem-llm/_logs/inference-*.jsonl.
---

# gem-llm-test-inference

Gemma 4 vLLM endpoint 의 추론/tool calling 스모크 테스트 스킬.

## When to use

- "vllm 잘 떴는지 추론 테스트해봐"
- "tool calling 동작하나"
- "JSON mode 확인"
- "스트리밍 응답 보고싶다"
- "응답 속도/토큰레이트"
- "prompt 한번 돌려봐"

## Pre-condition

vllm 서버 실행 중인지 먼저 헬스체크:
```bash
curl -fsS http://localhost:8000/v1/models | jq -r '.data[0].id'
```
실패 시 `gem-llm-deploy-vllm` 스킬로 fallback 안내.

## Test 1 — basic chat

```bash
curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma-4-main",
    "messages": [{"role":"user","content":"한국의 수도는?"}],
    "max_tokens": 64,
    "temperature": 0.2
  }' | jq -r '.choices[0].message.content'
```

K-EXAONE 계열은 영어 CoT 특성이 있으므로 한국어 응답을 강제하려면 system prompt에 명시.

## Test 2 — tool calling

```bash
curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d @- <<'JSON' | jq .
{
  "model": "gemma-4-main",
  "messages": [
    {"role":"system","content":"You are a helpful assistant."},
    {"role":"user","content":"서울의 현재 날씨를 알려줘."}
  ],
  "tools": [{
    "type":"function",
    "function":{
      "name":"get_weather",
      "description":"현재 날씨 조회",
      "parameters":{
        "type":"object",
        "properties":{"city":{"type":"string"}},
        "required":["city"]
      }
    }
  }],
  "tool_choice":"auto"
}
JSON
```
기대: `choices[0].message.tool_calls[0].function.name == "get_weather"`

## Test 3 — streaming

```bash
curl -N http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gemma-4-main","stream":true,"messages":[{"role":"user","content":"3까지 세어"}],"max_tokens":32}'
```

## Test 4 — Python (openai SDK)

```python
from openai import OpenAI
c = OpenAI(base_url="http://localhost:8000/v1", api_key="EMPTY")
r = c.chat.completions.create(
    model="gemma-4-main",
    messages=[{"role":"user","content":"hello"}],
    max_tokens=32,
)
print(r.choices[0].message.content)
```

## Logging

모든 테스트 결과를 jsonl로 보존:
```bash
mkdir -p /home/jovyan/gem-llm/_logs
TS=$(date +%Y%m%d-%H%M%S)
... | tee -a /home/jovyan/gem-llm/_logs/inference-${TS}.jsonl
```

## Reporting

사용자에게 요약: TTFT(첫 토큰까지 ms), tokens/sec, 응답 길이, tool_call 성공 여부, finish_reason.

## Safety

- 토큰 키 하드코드 금지 (vllm은 `EMPTY`, 외부 API는 환경변수)
- 대량 부하 테스트는 사용자 승인 후
