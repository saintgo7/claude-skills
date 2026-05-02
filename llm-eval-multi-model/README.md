# llm-eval-multi-model

여러 LLM 모델을 동일 prompt로 동시에 평가/비교하는 일반 패턴.

## 사용 시점

- "두 모델 비교", "벤치마크"
- "코딩 능력 비교", "한국어 응답 비교"
- "tool calling 정확도", "latency vs accuracy"
- Dense vs MoE, fine-tune 전후, quantization 전후

## 설치

```bash
./install.sh llm-eval-multi-model
```

메트릭 (TTFT, TPOT, p50/p95/p99), LLM-as-judge 패턴, tool call 정확도 채점은 [SKILL.md](SKILL.md) 참조. 실행은 `scripts/eval-bench.py`.
