---
name: vllm-tool-calling
description: 'vLLM tool calling 운영 가이드 — 서버 옵션 + 모델 검증 + 클라이언트 fallback. 사용 시점 — "tool calling 안 됨", "tool_calls 빈 배열", "function call leak", "hermes parser", "qwen3_coder parser", "vllm tool format". 3단계 디펜스 — server (parser) + model (weight) + client (fallback).'
---

# vllm-tool-calling

vLLM tool calling 은 단순히 `--enable-auto-tool-choice --tool-call-parser <name>` 한 줄로 끝나지 않는다. 운영 환경에서 안정적으로 돌리려면 **3단계 디펜스**가 모두 필요하다 — 서버 옵션 (parser), 모델 weight (실제 출력 포맷), 클라이언트 fallback (leak 회수). 이 셋 중 하나라도 빠지면 `tool_calls=[]` 빈 배열, 또는 user-visible content 안에 `<tool_call>...</tool_call>` 텍스트가 새는 현상이 발생한다.

## 사용 시점

- "tool calling이 안 박힘", `tool_calls`가 항상 빈 배열로 나옴
- 응답 content 안에 `<tool_call>{"name":...}</tool_call>` 또는 `<function=...>` 가 그대로 노출 (leak)
- `--tool-call-parser` 를 바꿔도 동일 증상 재현 (모델 weight 의심)
- streaming 응답에서만 깨지고 non-stream 은 정상 (chunk 경계 문제)
- 모델 업그레이드 후 갑자기 tool calling 회귀 (regression)
- 새 vLLM 모델 production 배포 전 smoke test 가 필요할 때

## 3단계 디펜스 — 핵심 모델

| 계층 | 책임 | 도구 | 실패 증상 |
|---|---|---|---|
| **Server (vLLM)** | parser 가 raw 모델 출력에서 tool call 토큰을 인식 | `--enable-auto-tool-choice --tool-call-parser <name>` | `tool_calls=[]`, content 에 raw `<tool_call>` 노출 |
| **Model (weight)** | 모델이 학습된 정확한 포맷으로 출력 | HF checkpoint 자체 | parser 옵션 어떻게 바꿔도 회복 안 됨 (regression) |
| **Client (fallback)** | leak 된 content 를 OpenAI tool_calls 로 promote | gateway/SDK 클라이언트 측 regex 추출 | stream chunk 경계에서 매칭이 깨져 leak 통과 |

세 계층은 **AND 가 아니라 OR 백업** — 한 단계가 실패해도 다음 단계가 보강한다. server 만 믿으면 stream 케이스에서 깨지고, client fallback 만 믿으면 모든 응답에 regex 비용이 든다. 운영에서는 셋 다 켜고 telemetry 로 어디서 잡혔는지 분리해서 본다.

## parser 종류 + 모델 매핑

| Parser | 모델 패밀리 | raw 출력 형식 |
|---|---|---|
| `hermes` | Hermes / Qwen2 / Qwen2.5 / 일부 Qwen3 | `<tool_call>{"name":"...","arguments":{...}}</tool_call>` |
| `qwen3_coder` | Qwen3-Coder (480B/30B-A3B 등) | `<tool_call><function=name><parameter=k>v</parameter></function></tool_call>` |
| `pythonic` | Llama 3.2 / 3.3, Gemma 4 | Python-style: `[func1(arg=val), func2(...)]` |
| `mistral` | Mistral, Mixtral, Magistral | `[TOOL_CALLS] [{"name":...,"arguments":...}]` |
| `internlm` | InternLM 2 / 2.5 | InternLM2 native format |
| `jamba` | AI21 Jamba | Jamba native format |
| `granite` | IBM Granite 3.x | IBM native format |

선택 기준 — **모델 카드의 chat template 안에 어떤 special token 이 들어 있는지** 확인. `tokenizer_config.json` 의 `chat_template` 안에서 `<tool_call>`, `<function=`, `[TOOL_CALLS]` 중 어느 것을 출력하라고 되어 있는지 보면 100% 매핑된다. 모델 카드만 보고 추측하면 hermes 로 표기됐는데 실제로는 qwen3_coder 인 케이스가 흔하다.

## 흔한 실패 패턴

### Case A — 서버 옵션 누락
**증상:** `tool_calls` 항상 `[]`, content 에 `<tool_call>...</tool_call>` 가 그대로 박혀서 사용자에게 보임.
**원인:** `--enable-auto-tool-choice` 또는 `--tool-call-parser` 둘 중 하나라도 빠짐.
**확인:** `ps -ef | grep vllm` 로 실제 launch 명령 확인.
**해결:** 두 플래그 모두 추가 후 재시작.

### Case B — 모델 weight regression
**증상:** parser 를 hermes / qwen3_coder / 기타 어느 것으로 바꿔도 동일하게 leak.
**원인:** 모델 자체가 잘못된 토큰을 생성. 예를 들어 학습은 `<tool_call>` 로 시작해야 하는데 opening token 없이 bare JSON 만 출력. fine-tuning 으로 chat template 이 깨졌거나, base 모델 quantization 과정에서 special token id 가 어긋났거나.
**확인:** vLLM raw `--return-tokens-as-token-ids` 또는 직접 `/v1/completions` (chat 아닌) 로 호출해서 raw 출력 확인. `<tool_call>` opening token 자체가 없으면 weight 문제.
**해결:** 모델 다시 다운로드, 다른 quantization, base 모델로 회귀 테스트. parser 옵션은 무용.

### Case C — Stream chunk 경계 깨짐
**증상:** non-stream 정상, stream 만 leak. SSE chunk 사이에서 `<tool_` + `call>` 처럼 토큰이 나뉘면서 vLLM 의 스트리밍 parser 가 매칭에 실패.
**원인:** parser 가 정확한 토큰 경계를 가정하지만 byte-pair tokenizer 가 다르게 분할.
**해결:** 클라이언트 fallback parser 로 누적 buffer 에서 정규식 추출 (아래 템플릿).

### Case D — Bare JSON content leak
**증상:** content 가 `{"name":"search","arguments":{"q":"..."}}` 처럼 JSON 만 단독으로 나옴 (`<tool_call>` 래퍼 없이).
**원인:** 모델이 opening tag 를 생략. parser 는 tag 가 있어야 동작.
**해결:** client fallback 에서 bare JSON 도 try-parse. 단 일반 응답의 JSON 출력과 충돌하지 않게 — schema 가 `{"name": ..., "arguments": ...}` 형태일 때만 promote.

### Case E — XML opening token 누락
**증상:** `</tool_call>` 만 보이고 opening `<tool_call>` 가 없음.
**원인:** 모델 출력이 끊김 + opening 누락 (regression 변형).
**해결:** client fallback 에서 closing tag 만 보고도 안쪽 JSON 추출 시도.

## 클라이언트 fallback parser

server parser 와 model 둘 다 정상이어도 stream / regression 케이스를 위해 **클라이언트 측 fallback** 을 둔다. gateway 또는 SDK wrapper 에서 응답을 받기 직전 한 번 더 검사:

1. `tool_calls` 가 이미 비어있지 않으면 즉시 return (overhead 0)
2. content 에 hermes JSON regex (`<tool_call>(\{.*?\})</tool_call>`) 매치 시도
3. content 에 qwen3 XML regex (`<function=(\w+)>(.*?)</function>`) 매치 시도
4. bare JSON (`^\s*\{"name":.*"arguments":.*\}\s*$`) 시도
5. 매치 시 OpenAI 표준 `tool_calls` 형식으로 promote, content 에서 해당 부분 strip
6. tool_call ID 는 `f"call_{uuid.uuid4().hex[:24]}"` 로 자동 생성

전체 구현은 `templates/fallback-parser.py.template` 참조 — 그대로 복붙해서 쓸 수 있게 placeholder 없는 형태로 작성.

스트림 응답에서는 chunk 누적 buffer 에 같은 함수를 적용하되, partial match 가 풀릴 때까지 chunk 를 hold (closing tag `</tool_call>` 가 들어올 때까지 buffer flush 하지 않음).

## Smoke test 패턴

배포 직후 (또는 CI 매 빌드) 한 번씩 다음 두 케이스를 자동으로 돌린다:

1. **non-stream** + 실제 tool 정의 + 응답에 `tool_calls` 배열 존재 검증
2. **stream** (`stream: true`) + 마지막 chunk 까지 누적 후 `tool_calls` 검증
3. **content leak 검증** — `tool_calls` 가 채워져 있을 때 content 안에 `<tool_call>` / `<function=` substring 이 **없어야** 함

전체 스크립트는 `templates/smoke-test.sh.template` 참조 (curl + jq 기반, 외부 의존 없이 CI 에 박을 수 있음).

운영에서는 hourly cron 또는 deploy hook 에서 한 번씩 실행 — regression 을 30분 내에 잡는다.

## 성능 영향

- fallback parser overhead: **응답당 ~1ms** (regex 3개 시도, 정상 응답은 첫 분기에서 즉시 return)
- regex 는 module-level 에서 `re.compile` 로 precompile
- `tool_calls` 가 이미 채워져 있으면 *추가 비용 0* — 정상 path 영향 없음
- stream 의 경우 chunk 마다가 아니라 **buffer flush 시점**에만 호출 (closing tag 발견 시)
- prometheus counter 로 어느 layer 가 잡았는지 telemetry: `vllm_tool_call_extracted_total{layer="server"|"client_hermes"|"client_qwen3"|"client_bare_json"}`

## 디버깅 워크플로

증상 → 원인 → 액션 순서로 좁힌다. 진단을 잘못하면 옵션만 계속 바꾸면서 시간을 잃는다 (case 16 의 함정).

```
[Q1] tool_calls 가 비어있나, content 에 leak 됐나?
  ├─ 빈 배열 + content 에도 tool 흔적 없음 → 모델이 tool 자체를 부르지 않음
  │   → tool_choice="auto" 외에 prompt 명시도 시도 (모델이 보수적)
  │   → temperature 너무 높으면 grounding 실패. 0.0~0.2 로 시도
  └─ content 에 leak 됐음 → 다음 단계

[Q2] non-stream 도 leak 인가, stream 만 leak 인가?
  ├─ stream 만 → Case C (chunk 경계). client fallback 충분
  └─ 둘 다 leak → 다음 단계

[Q3] parser 변경으로 회복되나?
  ├─ hermes/qwen3_coder/pythonic 시도해서 한 번이라도 성공 → Case A (옵션 선택 잘못됨)
  └─ 어느 parser 로도 실패 → 다음 단계

[Q4] 직접 /v1/completions 로 raw 출력을 받았을 때
     <tool_call> opening token 이 있나?
  ├─ 있음, 형식만 다름 → parser 매트릭스 재확인. chat_template 직접 읽기
  └─ 없음 (bare JSON 또는 빈 출력) → Case B (weight regression)
                                     → 모델 재다운로드 / quantization 변경
```

## Stream parser 구현 노트

stream 의 fallback 은 non-stream 보다 까다롭다. SSE chunk 가 들어올 때마다 fallback 을 호출하면 `<tool_call>` 가 절반만 들어온 상태에서 매치 실패하고 그 절반을 user 에게 흘려보낸다. 안전한 패턴:

1. chunk 의 delta.content 를 별도 buffer 에 누적
2. buffer 안에 `<tool_call>` 또는 `<function=` 또는 leading `{"name"` 시작 토큰이 보이면 그 시점부터 chunk 를 user 에게 emit 하지 않고 **hold**
3. closing tag (`</tool_call>` / `}`) 가 도착하면 누적 buffer 에 fallback 적용
4. tool_calls 추출 성공 시 별도 SSE event 로 emit, content 는 strip
5. 추출 실패 (정말로 그냥 텍스트였음) 시 hold 했던 buffer 를 그대로 user 에게 flush

이 hold 로직 없이 chunk-by-chunk fallback 만 돌리면 stream UX 가 깨진다. gateway 가 stream proxy 라면 이 buffer 는 per-request 상태로 잡아야 한다.

## Telemetry / observability

각 layer 가 얼마나 자주 trigger 됐는지 분리 카운팅 하면 어느 단계가 약한지 즉시 보인다.

```python
# Prometheus
vllm_tool_call_extracted_total{layer="server"}        # vLLM 이 정상 추출 (이상적)
vllm_tool_call_extracted_total{layer="client_hermes"} # client fallback 이 hermes 패턴 잡음
vllm_tool_call_extracted_total{layer="client_qwen3"}  # client fallback 이 qwen3 패턴 잡음
vllm_tool_call_extracted_total{layer="client_bare"}   # bare JSON 패턴 잡음
vllm_tool_call_leaked_total                           # 어느 layer 도 못 잡고 user 에게 노출 (alert)
```

운영 시그널:
- `client_*` 비율이 늘기 시작 → 모델 또는 vLLM 버전 변경의 부작용. 즉시 조사.
- `client_bare` 가 급증 → 모델 weight regression 강한 신호 (Case B/D).
- `leaked_total` > 0 → 즉시 alert. fallback 패턴 추가 필요.

## 모델 카드 vs 실제 동작 — 흔한 미스매치

모델 카드에 "supports tool calling with hermes format" 이라고 적혀 있어도 실제 weight 가 다른 경우가 있다. 검증 절차:

1. `tokenizer_config.json` 의 `chat_template` 안에서 `tools` 변수가 어떻게 렌더되는지 grep
2. 렌더된 문자열에 `<tool_call>` 가 있으면 hermes 또는 qwen3 계열
3. `[TOOL_CALLS]` 가 있으면 mistral
4. Python 함수 호출 텍스트 (`func(arg=val)`) 가 있으면 pythonic
5. 그 외 → granite / internlm / jamba 중 모델명으로 좁힘

정 안 되면 vLLM 을 parser **없이** 띄우고 raw output 을 sample 100개 모아서 패턴 분석. 그 후 매핑 결정.

## 운영 체크리스트

- [ ] 모델 카드의 chat_template 확인 → parser 정확히 매핑
- [ ] vLLM 부팅 시 `--enable-auto-tool-choice --tool-call-parser <name>` 둘 다 명시
- [ ] 클라이언트 (gateway / SDK) 에 fallback parser 추가
- [ ] stream proxy 라면 buffer hold 로직까지 구현 (chunk-by-chunk fallback 금지)
- [ ] Smoke test (non-stream + stream) CI 또는 deploy hook 에 박음
- [ ] Prometheus counter 로 layer 별 telemetry
- [ ] `vllm_tool_call_leaked_total > 0` alert
- [ ] 모델 변경 시 — 옵션만 바꾸지 말고 raw 출력 (`/v1/completions`) 으로 weight 검증
- [ ] regression 의심 시 base 모델 / 이전 quantization 으로 A/B 테스트
- [ ] 모델 카드 description 만 믿지 말고 실제 chat_template grep 으로 parser 결정

## 참고

- vLLM 공식: https://docs.vllm.ai/en/latest/features/tool_calling.html
- OpenAI tool calling 응답 schema (gateway 가 호환해야 하는 표준)
- 관련 skill: `vllm-bootstrap` (부팅 자체), `gem-llm-cli-client` (REPL 에서 tool 호출 흐름), `gem-llm-troubleshooting` (실전 사례)
