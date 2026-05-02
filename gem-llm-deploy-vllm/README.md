# gem-llm-deploy-vllm

GEM-LLM의 두 vLLM 모델 서버 (Gemma 메인 + auxiliary) 기동/정지/헬스체크 스킬.

## 사용 시점

- "vllm 띄워/재시작/내려"
- "vllm 헬스체크", "모델 서버 기동"
- "포트 충돌", "GPU OOM"
- "vllm 로그 확인"

## 설치

```bash
./install.sh gem-llm-deploy-vllm
```

tensor-parallel size, dtype, served-model-name, gpu-memory-utilization 옵션과 로그 위치 (`/home/jovyan/gem-llm/_logs/vllm-*.log`)는 [SKILL.md](SKILL.md) 참조.
