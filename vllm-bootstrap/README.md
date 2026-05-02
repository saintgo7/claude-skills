# vllm-bootstrap

vLLM OpenAI 호환 서버를 처음 띄울 때의 일반화된 부팅 가이드.

## 사용 시점

- "vllm 처음 띄우기", "model 로딩"
- "tensor parallel 설정", "max-model-len GPU OOM"
- "tool-call-parser", "flashinfer DeepGEMM 충돌"
- "vllm 버전 호환"

## 설치

```bash
./install.sh vllm-bootstrap
```

의존성 매트릭스 (vllm/transformers/flashinfer/mistral_common), 부팅 실패 패턴, TP=1/2/4/8 선택, tool-call-parser 종류는 [SKILL.md](SKILL.md) 참조.
