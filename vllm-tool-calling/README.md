# vllm-tool-calling

vLLM tool calling 운영 가이드 — **3단계 디펜스** (server parser + model weight + client fallback). leak / regression / stream chunk 경계 깨짐을 한 번에 잡는다.

## 사용 시점

- "tool calling 안 됨", `tool_calls` 빈 배열
- content 에 `<tool_call>` / `<function=` leak
- parser 옵션 바꿔도 그대로 (weight regression 의심)
- stream 만 깨짐, non-stream 정상

## 설치

```bash
./install.sh vllm-tool-calling
```

3계층 책임 분리, parser 매핑 테이블, 흔한 실패 5 패턴, fallback parser 구현, smoke test 자동화는 [SKILL.md](SKILL.md) 참조.
