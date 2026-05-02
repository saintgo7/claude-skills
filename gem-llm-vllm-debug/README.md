# gem-llm-vllm-debug

vLLM 모델 서버 디버깅 스킬 (Qwen2.5-Coder-32B, Qwen3-Coder-30B-A3B 듀얼 서빙).

## 사용 시점

- "vLLM 안 떠", "모델 로딩 실패"
- "GPU OOM", "tool calling 안됨"
- "flashinfer 충돌", "DeepGEMM 에러"
- "transformers 호환", "vllm 버전"

## 설치

```bash
./install.sh gem-llm-vllm-debug
```

작동 검증된 의존성 매트릭스 (2026-05-02)와 부팅 실패 패턴은 [SKILL.md](SKILL.md) 참조.
