# multi-llm-routing-pattern

여러 LLM 백엔드(vLLM, OpenAI, TGI 등)를 단일 OpenAI 호환 게이트웨이에서 라우팅하는 5 패턴 — 정적 매핑, weighted, fallback chain, 사용자/플랜별, A/B canary. GEM-LLM Gateway 의 `upstream_map` (qwen2.5-coder-32b → :8001, qwen3-coder-30b → :8002) 가 28일 + 100 동접에서 검증.

## 사용 시점

- "모델 라우팅 / upstream_map / fallback / weighted"
- "사용자 플랜별 LLM" 또는 "A/B canary"
- 새 모델 추가 워크플로 정립

## 설치

```bash
./install.sh multi-llm-routing-pattern
```

5 패턴 코드, 새 모델 추가 atomic 워크플로, fallback 4xx/5xx 분기, 흔한 함정 7가지는 [SKILL.md](SKILL.md) 참조.
