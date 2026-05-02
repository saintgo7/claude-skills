---
name: llm-eval-multi-model
description: '여러 LLM 모델 (Dense vs MoE, GPT vs Claude vs Llama 등) 동시 평가 및 비교. 사용 시점 — "두 모델 비교", "벤치마크", "모델 평가", "코딩 능력 비교", "한국어 응답 비교", "tool calling 정확도", "latency vs accuracy". 동일 prompt 다중 endpoint 호출 + 메트릭 (latency, token usage, response quality) + 통계 분석.'
---

# llm-eval-multi-model

여러 LLM endpoint를 동일 prompt로 동시에 두드려 메트릭/응답 품질을 비교하는 일반 패턴. Dense vs MoE, 동급 다른 vendor (Claude vs GPT vs Llama), fine-tune 전후, 또는 quantization 전후 비교에 모두 적용.

## 사용 시점

- "두 모델 비교", "A 모델 vs B 모델"
- "벤치마크 돌려줘", "모델 평가"
- "코딩 능력 비교", "한국어 응답 비교"
- "tool calling 정확도", "function call 잘 하는지"
- "latency vs accuracy trade-off"
- Dense (Qwen2.5-Coder-32B) vs MoE (Qwen3-Coder-30B-A3B)
- fine-tune 전후 회귀 검증 (regression eval)
- AWQ/GPTQ/FP8 quantization 후 quality drop 측정

## 핵심 원칙

1. **같은 prompt, 같은 sampling 파라미터** — temperature/top_p/seed 통일해야 비교 가능
2. **runs ≥ 5** — latency variance 크기 때문에 단발 측정은 의미 없음. p50/p95/p99 봐야 함
3. **응답 품질은 별도** — latency만 빠른 모델이 답을 망치면 의미 없음. ground truth 또는 LLM-judge로 채점
4. **첫 콜은 warm-up** — TTFT/cache 영향. 통계에서 제외하거나 별도 표시
5. **endpoint별 동시 호출** — `asyncio.gather`로 병렬, 같은 시점 부하에서 비교

## 동시 호출 패턴 (asyncio.gather)

```python
import asyncio, time
import httpx

async def call_one(client, endpoint, key, model, prompt):
    t0 = time.perf_counter()
    r = await client.post(
        f"{endpoint}/v1/chat/completions",
        headers={"Authorization": f"Bearer {key}"},
        json={
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.0,
            "max_tokens": 512,
        },
        timeout=120,
    )
    dt = time.perf_counter() - t0
    j = r.json()
    return {
        "endpoint": endpoint,
        "model": model,
        "latency_s": dt,
        "prompt_tokens": j["usage"]["prompt_tokens"],
        "completion_tokens": j["usage"]["completion_tokens"],
        "response": j["choices"][0]["message"]["content"],
    }

async def run_one_prompt(prompt, configs):
    async with httpx.AsyncClient() as client:
        tasks = [call_one(client, c["endpoint"], c["key"], c["model"], prompt)
                 for c in configs]
        return await asyncio.gather(*tasks, return_exceptions=True)
```

`return_exceptions=True` 가 중요 — 한 모델이 죽어도 다른 모델 결과는 살림.

## 메트릭 (무엇을 재나)

### Latency
- **TTFT (Time To First Token)** — streaming 응답 첫 chunk까지. UX 핵심
- **TPOT (Time Per Output Token)** — `(total - TTFT) / completion_tokens`. throughput 척도
- **End-to-end latency** — 비-streaming 시 가장 단순한 지표
- **p50 / p95 / p99** — 평균 대신 분포로 봐야 함. p99 spike가 사용자 체감 결정

### Token usage
- `prompt_tokens`, `completion_tokens`, `total_tokens`
- 모델별 tokenizer 다름 — 같은 프롬프트의 token 수가 다를 수 있음 (비용 계산에 영향)
- MoE 모델은 expert만 활성화돼도 KV cache는 전체 layer만큼 — throughput vs memory trade

### Throughput (서버 측)
- `tokens/sec` (output) = `completion_tokens / (latency - TTFT)`
- 동시 요청 시 per-request throughput는 떨어지지만 aggregate throughput은 오름

### 응답 품질
- **Ground truth 일치** — 정답이 명확한 경우 (수학, 코딩 unit test 통과 등)
- **LLM-as-judge** — 다른 모델 (가능하면 더 큰 모델)에게 채점 시킴. rubric을 명확히
- **String 일치율 / BLEU / ROUGE** — 번역/요약 류
- **Tool call 정확도** — function name + arguments JSON schema 일치

## 정확도 평가: ground truth vs LLM-judge

### Ground truth (선호)
정답이 결정론적인 task에 적합:

```python
# 예: 코딩 - unit test 통과 여부
def grade_code(response, test_cases):
    code = extract_code_block(response)
    try:
        exec_in_sandbox(code)
        return all(run_test(t) for t in test_cases)
    except Exception:
        return False
```

### LLM-as-judge
주관적 task (응답 품질, 어조, 정확도) 에 사용:

```python
JUDGE_PROMPT = """다음 두 응답을 비교해 채점하라.
질문: {question}
응답 A (model={model_a}): {answer_a}
응답 B (model={model_b}): {answer_b}

기준:
1. 정확성 (0-10)
2. 명료성 (0-10)
3. 한국어 자연스러움 (0-10)

출력 형식 (JSON only):
{{"a": {{"correctness":n,"clarity":n,"korean":n}},
  "b": {{"correctness":n,"clarity":n,"korean":n}},
  "winner": "a" | "b" | "tie",
  "reason": "..."}}
"""
```

**주의:**
- judge 자기 자신을 평가 대상에 포함하면 self-preference bias — 가급적 다른 vendor / 다른 모델 사용
- A/B 위치 swap 절반씩 (position bias 제거)
- judge 비용 = `runs × prompts × 1` 호출 추가 — 실험 design 시 고려

## 한국어 vs 영어 응답 품질 비교

K-EXAONE 같은 한국어 특화 모델 / 영어 위주 모델 (Llama, Mistral) 비교 시:

```python
KO_PROMPTS = ["...한국어 프롬프트..."]
EN_PROMPTS = ["...English prompts..."]

# 1) 두 언어 각각 별도 세트로 평가
# 2) 응답 언어 자동 감지 (langdetect / lingua) — 영어 프롬프트인데 한국어 응답하면 감점
# 3) 같은 의미 한/영 짝 (parallel set) — 동일 의미 응답 일관성 평가
```

평가 포인트:
- **응답 언어 정합성** — 한국어 프롬프트 → 한국어 응답이어야 함 (모델이 영어로 새지 않는지)
- **Code-switching** — "이 함수는 returns a list" 같이 섞이면 감점
- **한자 빈도** — 너무 한자 많으면 일반 사용자에 부적합
- **존댓말 / 반말** — system prompt 지시 따르는지

## Tool calling 정확도

```python
GROUND_TRUTH = {
    "name": "get_weather",
    "arguments": {"city": "Seoul", "unit": "celsius"}
}

def grade_tool_call(response_msg, gt):
    tc = response_msg.get("tool_calls", [])
    if not tc:
        return {"called": False, "name_match": False, "args_match": False}
    call = tc[0]["function"]
    name_ok = call["name"] == gt["name"]
    try:
        args = json.loads(call["arguments"])
    except Exception:
        return {"called": True, "name_match": name_ok, "args_match": False, "args_parse": False}
    args_ok = args == gt["arguments"]
    return {"called": True, "name_match": name_ok, "args_match": args_ok, "args_parse": True}
```

집계:
- **호출률** — `tool_choice=auto` 일 때 호출이 필요한 prompt에 실제 호출했는가
- **Name 정확도** — 후보 함수 중 맞는 걸 골랐는가
- **Args 정확도** — 인자 JSON이 schema 통과 + 의미상 정답인가
- **Hallucinated function** — 정의되지 않은 함수 호출 (즉시 fail)

## 통계 분석 (statistics 모듈로 충분)

```python
import statistics

def summary(values):
    s = sorted(values)
    return {
        "n": len(s),
        "mean": statistics.mean(s),
        "stdev": statistics.stdev(s) if len(s) > 1 else 0,
        "p50": statistics.median(s),
        "p95": s[int(len(s) * 0.95)],
        "p99": s[int(len(s) * 0.99)] if len(s) >= 100 else s[-1],
        "min": s[0],
        "max": s[-1],
    }
```

`numpy` 없이 표준 라이브러리만으로 가능. 큰 샘플이면 `numpy.percentile` 권장.

### 두 분포 차이 검정
- **Welch's t-test** (`scipy.stats.ttest_ind(equal_var=False)`) — 평균 차이 유의성
- **Mann-Whitney U** (`scipy.stats.mannwhitneyu`) — 비모수 (latency 분포는 long-tail 이라 정규성 안 따름)
- 효과 크기 (Cohen's d) — p-value만 보면 sample 크기에 휘둘림

## 비교 보고서 markdown 형식

```markdown
# Eval Results — 2026-05-02

| Metric | model-a | model-b | Δ |
|---|---|---|---|
| latency_p50 (s) | 1.2 | 0.9 | -25% |
| latency_p99 (s) | 3.4 | 2.1 | -38% |
| TTFT_p50 (ms) | 280 | 180 | -36% |
| output tps | 45 | 62 | +38% |
| accuracy (judge) | 87% | 81% | -6pp |
| tool name match | 94% | 89% | -5pp |
| tool args match | 81% | 73% | -8pp |

## 응답 샘플
### Prompt 1: "..."
**model-a:** ...
**model-b:** ...
**judge:** winner=a, reason="..."
```

핵심: **모든 메트릭을 한 표** + **각 prompt별 응답 샘플** (10개 prompt면 10개 셋). cherry-pick 방지.

## 흔한 함정

1. **Warm-up 미포함** — 첫 호출은 cache miss / model load 잔재. 1-2회 버려야 함
2. **Sampling temperature ≠ 0** — randomness가 있으면 같은 prompt에 매번 다른 응답. 비교 시 `temperature=0` 또는 `seed` 고정
3. **Judge가 자기 자신** — model-a가 judge면 model-a 편들음. 항상 외부 judge
4. **Token count 비교를 그대로** — tokenizer가 다르면 같은 텍스트도 token 수 다름. 비용 계산 시 주의
5. **단발 prompt** — prompts ≥ 10, 가능하면 20-50. 한 prompt만으로 결론 X
6. **Network jitter** — 동시 호출 (asyncio.gather) 으로 같은 시점에서 비교. 순차 호출은 시간차로 결과 흔들림

## 포함 스크립트

`scripts/eval-bench.py`

```bash
python scripts/eval-bench.py \
  --endpoints http://host1:8001,http://host2:8002 \
  --keys sk-key1,sk-key2 \
  --models model-a,model-b \
  --prompts prompts.txt \
  --runs 10 \
  --judge-endpoint http://judge:8003 --judge-key sk-judge --judge-model gpt-4
```

출력: `eval-results-<timestamp>.md` — 메트릭 표 + prompt별 응답 샘플.

옵션:
- `--temperature 0.0` (default) — 결정론적 비교
- `--max-tokens 512`
- `--warmup 2` — 통계에서 제외할 첫 N runs
- `--concurrency 5` — endpoint당 동시 호출 수

## 참고 (운영 사례)

GEM-LLM 프로젝트에서 **Qwen2.5-Coder-32B (Dense, port 8001)** vs **Qwen3-Coder-30B-A3B (MoE, active ~3B, port 8002)** 비교에 사용:
- Dense는 일정한 latency, MoE는 token 별 expert 라우팅으로 spike 있음 — p50은 비슷, p99에서 MoE가 +20-30%
- MoE가 throughput은 1.4x 높음 (active param 적음)
- 코딩 정확도 (HumanEval 류 unit test) 는 동급, 한국어 자연스러움은 Dense가 약간 우위
- Tool call args JSON 정확도는 두 모델 모두 95%+, name match는 99%+

위 사례는 본 skill의 검증 케이스. 다른 vendor/모델로 일반화해서 사용.
