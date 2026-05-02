---
name: gem-llm-vllm-debug
description: vLLM 모델 서버 디버깅 (Qwen2.5-Coder-32B, Qwen3-Coder-30B-A3B). 사용 시점 — "vLLM 안 떠", "모델 로딩 실패", "GPU OOM", "tool calling 안됨", "flashinfer 충돌", "DeepGEMM 에러", "transformers 호환", "vllm 버전". 가동/실패 진단 + 의존성 호환 매트릭스.
---

# gem-llm-vllm-debug

## 작동 검증된 의존성 매트릭스 (2026-05-02)

| 패키지 | 버전 | 비고 |
|---|---|---|
| Python | 3.12 (`/home/jovyan/vllm-env`) | conda 환경 |
| vLLM | **0.19.1** | 0.20.0 DeepGEMM 빌드 실패 |
| transformers | **5.7.0** | Gemma 4 model_type 인식 (4.x는 안 됨) |
| mistral_common | 최신 | transformers 5.7와 ReasoningEffort 호환 |
| flashinfer-python | 0.6.8.post1 | |
| flashinfer-cubin | 0.6.8.post1 | python과 정합 |
| torch | (vllm과 동기화) | |

## 표준 launch (현재 운영 모델)

### Qwen2.5-Coder-32B Dense (port 8001, GPU 0-3 TP=4)

```bash
CUDA_VISIBLE_DEVICES=0,1,2,3 setsid nohup /home/jovyan/vllm-env/bin/python \
  -m vllm.entrypoints.openai.api_server \
  --model Qwen/Qwen2.5-Coder-32B-Instruct \
  --tensor-parallel-size 4 \
  --host 0.0.0.0 --port 8001 \
  --served-model-name qwen2.5-coder-32b \
  --max-model-len 32768 \
  --gpu-memory-utilization 0.85 \
  --enable-prefix-caching \
  --enable-auto-tool-choice --tool-call-parser hermes \
  > /home/jovyan/gem-llm/_logs/vllm-31b.log 2>&1 < /dev/null &
```

### Qwen3-Coder-30B-A3B MoE (port 8002, GPU 4-7 TP=4)

```bash
CUDA_VISIBLE_DEVICES=4,5,6,7 setsid nohup /home/jovyan/vllm-env/bin/python \
  -m vllm.entrypoints.openai.api_server \
  --model Qwen/Qwen3-Coder-30B-A3B-Instruct \
  --tensor-parallel-size 4 \
  --host 0.0.0.0 --port 8002 \
  --served-model-name qwen3-coder-30b \
  --max-model-len 32768 \
  --gpu-memory-utilization 0.85 \
  --enable-prefix-caching \
  --enable-auto-tool-choice --tool-call-parser hermes \
  > /home/jovyan/gem-llm/_logs/vllm-26b.log 2>&1 < /dev/null &
```

## 옵션 의미

| | |
|---|---|
| `setsid nohup ... < /dev/null &` | 부모 셸 종료 시에도 살아있음 |
| `--tensor-parallel-size 4` | 4 GPU 분산 |
| `--gpu-memory-utilization 0.85` | KV cache용 15% 여유 |
| `--enable-prefix-caching` | 시스템 프롬프트 재사용 (~30% 속도) |
| `--tool-call-parser hermes` | OpenAI-compatible function calling (Qwen은 hermes 형식) |
| `--max-model-len 32768` | 64K → 32K (KV cache 절감, 50동접 안정) |

## 부팅 순서 정상 로그

```
[utils.py:238] non-default args: {...}
[model.py:531] Resolved architecture: ...
[scheduler.py:231] Chunked prefill is enabled
[selector.py:124] Using HND KV cache layout for FLASHINFER backend
Loading safetensors checkpoint shards: 100% Completed | 16/16
[launcher.py:46] Route: /v1/models, ...
INFO:     Started server process
INFO:     Application startup complete.
```

총 60-100초 (정상). 5분 넘으면 멈춤.

## 흔한 부팅 실패

### `--disable-log-requests` 미지원
**원인:** vLLM 0.18+에서 옵션명 변경  
**해결:** `--no-enable-log-requests` 사용

### `flashinfer version mismatch`
```
flashinfer-cubin (0.6.8.post1) does not match flashinfer (0.6.4)
```
**해결:** 두 패키지 동일 버전 강제
```bash
pip install --upgrade flashinfer-python flashinfer-cubin  # 버전 일치
# 또는 우회
export FLASHINFER_DISABLE_VERSION_CHECK=1
```

### `DeepGEMM backend not available`
**원인:** vLLM 0.20.0 FP8 kernel 의존  
**해결:** vLLM 0.19.1로 다운그레이드 (현재 권장)

### `gemma4 architecture not recognized`
**원인:** transformers < 5.7  
**해결:** `pip install --upgrade transformers` (단 vllm 호환 경고는 무시 가능)

### `cannot import name 'ReasoningEffort'`
**원인:** transformers 5.7가 새 mistral_common API 요구  
**해결:** `pip install --upgrade mistral_common`

### `KeyError: layer_scalar`
**Gemma 4 weight 호환 깨짐.** Qwen Coder로 전환 (case 11). 현재 시스템은 이미 Qwen.

### Port 8001/8002 already in use
**원인:** 이전 vLLM 좀비 또는 다른 프로세스 (예: `python3 -m http.server 8001`)
**해결:**
```bash
# 점유자 찾기
awk '$2 ~ /:1F41$/ && $4=="0A" {print $10}' /proc/net/tcp  # inode
for pid in $(ls /proc | grep -E '^[0-9]+$'); do
  ls -l /proc/$pid/fd 2>/dev/null | grep -q "<inode>" && echo "PID=$pid"
done
kill -9 <PID>
```

### GPU 메모리 잔재 (이전 vLLM 죽음 후)
```bash
nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader
kill -9 <PID>
sleep 3
nvidia-smi  # 메모리 0 확인
```

## 직접 검증 (Gateway 우회)

```bash
# /v1/models
curl -s http://localhost:8001/v1/models | python3 -m json.tool

# Chat
curl -s http://localhost:8001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen2.5-coder-32b","messages":[{"role":"user","content":"hi"}],"max_tokens":10}'

# Tool calling
curl -s http://localhost:8001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-coder-32b",
    "messages": [{"role":"user","content":"What is the weather in Seoul?"}],
    "tools": [{
      "type": "function",
      "function": {
        "name": "get_weather",
        "parameters": {"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}
      }
    }],
    "tool_choice": "auto"
  }'
```

## tool_call_parser 종류

- `hermes` — Qwen2.5-Coder, Qwen3-Coder 권장 (검증됨)
- `pythonic` — Gemma 4 (현재 미사용)
- `mistral` — Mistral 계열
- 미지정 시 일부 모델은 fallback

## 모델 캐시 위치

`~/.cache/huggingface/hub/` (datavol-1 심볼릭). 다운로드 후:
- `models--Qwen--Qwen2.5-Coder-32B-Instruct/` ~64GB
- `models--Qwen--Qwen3-Coder-30B-A3B-Instruct/` ~60GB

다른 모델로 전환 시 vLLM이 자동 다운로드 (HF_TOKEN 환경변수 권장 — rate limit 회피).

## 부하 시 vLLM 메트릭

```bash
# vLLM 자체 metrics (별도 enable 필요)
curl http://localhost:8001/metrics  # 기본 disable일 수도

# nvidia-smi GPU 활용률
watch -n 1 'nvidia-smi --query-gpu=index,utilization.gpu,memory.used --format=csv,noheader'
```

50동접 정상 시 GPU util 60-90%. 100% 길게 = 큐 적체.

## 관련

- 책 Part III Ch.8 — vLLM 서빙 깊이
- SPEC-02 — vLLM 서빙 결정사항
- `src/vllm-serve/` — launch 스크립트
