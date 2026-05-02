---
name: vllm-bootstrap
description: 'vLLM을 처음부터 띄우는 일반화된 부팅 가이드. 사용 시점 — "vllm 처음 띄우기", "model 로딩", "tensor parallel 설정", "max-model-len GPU OOM", "tool-call-parser", "flashinfer DeepGEMM 충돌", "vllm 버전 호환". 의존성 매트릭스(vllm/transformers/flashinfer/mistral_common) + 부팅 실패 패턴 + tensor-parallel TP=1/2/4/8 선택 + tool calling parser 종류.'
---

# vllm-bootstrap

vLLM OpenAI-compatible 서버를 처음 띄울 때의 일반화된 가이드. 의존성 매트릭스, 부팅 실패 패턴, TP 선택, tool-call-parser 매핑까지.

## 사용 시점

- vLLM 환경을 처음 만들고 `vllm.entrypoints.openai.api_server` 를 처음 띄움
- 모델 로딩이 멈추거나 실패함 (60-100초 정상, 5분 초과 시 비정상)
- GPU OOM (`CUDA out of memory`) 또는 KV cache 부족
- tool calling이 응답에 안 박힘 (parser 불일치)
- `flashinfer-cubin version mismatch`, `DeepGEMM not available`, `cannot import ReasoningEffort` 류 import 에러
- 어떤 TP (1/2/4/8) 가 적절한지 결정
- vLLM/transformers 업그레이드 후 부팅 실패

## 검증된 의존성 매트릭스 (2026 Q2 기준)

| 패키지 | 버전 | 비고 |
|---|---|---|
| Python | 3.12 | conda/venv 권장 |
| vLLM | **0.19.1** | 0.20.x 는 DeepGEMM/FP8 빌드 이슈 있음 |
| transformers | **5.7.0+** | Gemma 4 등 신규 architecture 인식 |
| mistral_common | 최신 | transformers 5.7과 ReasoningEffort API 호환 필수 |
| flashinfer-python | 0.6.8.post1 | flashinfer-cubin과 동일 버전 |
| flashinfer-cubin | 0.6.8.post1 | python과 정합 |
| torch | vLLM과 함께 설치 | 수동 설치 비권장 |

설치:

```bash
pip install vllm==0.19.1 transformers==5.7.0 mistral_common \
            flashinfer-python==0.6.8.post1 flashinfer-cubin==0.6.8.post1
```

### 다른 조합 주의사항

- **vLLM 0.18.x**: `--disable-log-requests` 가 그대로 동작. 0.19+ 는 `--no-enable-log-requests` 사용해야 함.
- **vLLM 0.20.x**: DeepGEMM (FP8 fused kernel) 의존이 강화돼 빌드/런타임 에러가 잦음. 검증되지 않았다면 0.19.1 고정 권장.
- **transformers 4.x**: Gemma 4 / 일부 신규 모델 architecture 미인식 → `KeyError: gemma4` 류.
- **flashinfer python ≠ cubin**: 둘 중 하나만 업그레이드되면 mismatch. 항상 같이 업그레이드.

## 표준 launch 명령

```bash
CUDA_VISIBLE_DEVICES=0,1,2,3 setsid nohup <PY_VENV>/bin/python \
  -m vllm.entrypoints.openai.api_server \
  --model <HF_REPO_OR_LOCAL_PATH> \
  --tensor-parallel-size 4 \
  --host 0.0.0.0 --port <PORT> \
  --served-model-name <SHORT_NAME> \
  --max-model-len 32768 \
  --gpu-memory-utilization 0.85 \
  --enable-prefix-caching \
  --enable-auto-tool-choice --tool-call-parser hermes \
  > <LOG_PATH> 2>&1 < /dev/null &
```

### 인자 의미

| 인자 | 의미 |
|---|---|
| `setsid nohup ... < /dev/null &` | 부모 셸 종료 후에도 살아있는 분리된 프로세스 |
| `CUDA_VISIBLE_DEVICES` | 사용할 GPU 인덱스 (TP 수 = 갯수) |
| `--tensor-parallel-size N` | weight를 N개 GPU에 분할 (NCCL 필요) |
| `--gpu-memory-utilization 0.85` | 전체 GPU 메모리의 85%만 사용 — KV cache + 다른 process 여유 (기본값 0.9는 OOM 잘 남) |
| `--max-model-len` | context 길이 상한. 모델 capability와 KV cache 메모리의 trade-off |
| `--enable-prefix-caching` | system prompt 등 공통 prefix 재사용 (~30% TTFT 개선) |
| `--enable-auto-tool-choice` | OpenAI 호환 function/tool calling 활성화 |
| `--tool-call-parser` | 모델별 tool call format (아래 표) |
| `--served-model-name` | API에서 노출할 모델 이름 (`/v1/models` 응답) |

## TP=1/2/4/8 선택 가이드

| 모델 weight (FP16) | 가능한 TP | 권장 |
|---|---|---|
| ≤ 14B (~28 GB) | 1, 2, 4 | TP=1 (단일 80GB GPU) — 통신 오버헤드 0 |
| 14B~32B (~28-64 GB) | 2, 4 | TP=2 또는 TP=4 (80GB GPU 2~4장) |
| 30B MoE (active 3-4B) | 2, 4 | TP=4 (전체 weight 로딩 필요, active만 작음) |
| 70B (~140 GB) | 4, 8 | TP=4 (80GB×4) 또는 TP=8 (40GB×8) |
| 100B+ | 8 | TP=8 필수, 나아가 PP 검토 |

**규칙:**
- TP는 모델의 attention head 수의 약수여야 함 (대부분 1/2/4/8 OK)
- KV cache까지 포함한 실제 메모리는 weight × 1.3~1.8 배. `--gpu-memory-utilization 0.85` 와 함께 계산
- TP가 클수록 latency는 줄지만 communication 오버헤드 증가. 단일 GPU에 들어가면 TP=1이 최선
- Multi-node TP는 NCCL/IB 가 안 되면 불가능 — 단일 노드 안에서 끝내는 것 권장

## gpu-memory-utilization 디폴트가 왜 0.85인가

vLLM 기본값은 0.9 인데, 실제 운영에서:
- 같은 GPU에 다른 process(예: 모니터링 도구) 가 ~1-2GB 잡고 있으면 0.9는 OOM
- 두 개 vLLM을 같은 GPU에 놓으면 0.85×2=1.7로 자동 분배는 안 되지만 사용자가 명시적으로 합칠 때 안전
- 50+ 동시 요청 시 KV cache가 갑자기 늘어나 일시적 spike — 15% 여유는 그 cushion

→ **0.85 를 기본으로 시작, GPU usage 모니터링 후 0.90까지 튜닝**

## tool-call-parser 종류

| parser | 모델군 |
|---|---|
| `hermes` | Qwen2.5/3 Coder, Hermes 계열 (가장 보편적) |
| `mistral` | Mistral, Mixtral, Magistral |
| `pythonic` | Llama 3.2/3.3, Gemma 4 |
| `granite` | IBM Granite |
| `internlm` | InternLM |
| `jamba` | AI21 Jamba |

미지정 + `--enable-auto-tool-choice` → 모델별 fallback 시도하지만 결과 불안정. **항상 명시 권장.**

## 부팅 정상 로그 (참고)

```
[utils.py:238] non-default args: {...}
[model.py:531] Resolved architecture: Qwen2ForCausalLM
[scheduler.py:231] Chunked prefill is enabled
[selector.py:124] Using HND KV cache layout for FLASHINFER backend
Loading safetensors checkpoint shards: 100% Completed | 16/16
[launcher.py:46] Route: /v1/models, ...
INFO:     Started server process
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:<PORT>
```

총 60-100초 (~30B 모델 기준). 5분 초과 시 멈춤이거나 download 진행 중. log를 tail 해서 확인.

## 흔한 부팅 실패 + 해결

### 1. `--disable-log-requests: unrecognized arguments`
**원인:** vLLM 0.19+ 에서 옵션명 변경
**해결:** `--no-enable-log-requests` 로 교체

### 2. `flashinfer-cubin version mismatch`
```
flashinfer-cubin (0.6.8.post1) does not match flashinfer (0.6.4)
```
**해결:**
```bash
pip install --upgrade flashinfer-python flashinfer-cubin
# 임시 우회
export FLASHINFER_DISABLE_VERSION_CHECK=1
```

### 3. `DeepGEMM backend not available`
**원인:** vLLM 0.20.x FP8 fused kernel 의존
**해결:** vLLM 0.19.1 로 다운그레이드

### 4. `gemma4 architecture not recognized` / `KeyError: <model_type>`
**원인:** transformers < 5.7 (또는 신규 모델)
**해결:** `pip install --upgrade transformers`

### 5. `cannot import name 'ReasoningEffort' from 'mistral_common'`
**원인:** transformers 5.7 가 새 mistral_common API 요구
**해결:** `pip install --upgrade mistral_common`

### 6. `KeyError: <weight_layer>` 로딩 도중
**원인:** transformers 와 모델 weight 사이 architecture 호환 깨짐 (특히 신규 모델 초창기)
**해결:** transformers 버전 매칭 — 모델 README 의 minimum 버전 확인

### 7. `CUDA out of memory` (모델 로딩 단계)
**원인:** weight 자체가 GPU 메모리 초과
**해결:** TP를 늘리거나 (`--tensor-parallel-size 8`), 양자화 모델 (AWQ/GPTQ/FP8) 사용

### 8. `CUDA out of memory` (request 처리 중)
**원인:** KV cache 부족
**해결:** `--max-model-len` 축소 (예: 65536 → 32768), 또는 `--gpu-memory-utilization` 상향

### 9. Port already in use
```
[Errno 98] Address already in use
```
**원인:** 좀비 vLLM 또는 다른 프로세스 점유
**해결:**
```bash
# 1) 표준
ss -ltnp | grep :<PORT>
fuser -k <PORT>/tcp

# 2) ss/lsof 없는 환경 — /proc/net/tcp 직접
PORT_HEX=$(printf '%04X' <PORT>)
INODE=$(awk -v p=":$PORT_HEX" '$2 ~ p"$" && $4=="0A" {print $10}' /proc/net/tcp)
for pid in $(ls /proc | grep -E '^[0-9]+$'); do
  ls -l /proc/$pid/fd 2>/dev/null | grep -q "$INODE" && echo "PID=$pid"
done
kill -9 <PID>
```

### 10. GPU 메모리 잔재 (이전 프로세스 죽음 후)
```bash
nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader
# 점유 PID kill
kill -9 <PID>
sleep 3
nvidia-smi  # 메모리 0 확인
```

### 11. NCCL init 멈춤 (TP > 1)
**원인:** GPU 간 P2P 통신 불가능 (가상화 환경, MIG, 일부 K8s)
**해결:** TP=1 로 단일 GPU 사용 또는 `NCCL_P2P_DISABLE=1` 시도

### 12. `Trust remote code required`
**원인:** 모델이 custom code 사용 (Qwen, ChatGLM 등 일부)
**해결:** `--trust-remote-code` 추가. 단 신뢰할 수 있는 모델에만.

### 13. tool calling이 응답 본문에 string으로 나옴
**원인:** parser 불일치 (Llama인데 hermes 사용 등)
**해결:** 위 parser 매트릭스대로 교체. 그래도 안 되면 chat template 확인 (`--chat-template`)

## 검증 절차

서버가 뜬 뒤:

```bash
# 1) 모델 노출 확인
curl -s http://localhost:<PORT>/v1/models | python3 -m json.tool

# 2) chat completion smoke test
curl -s http://localhost:<PORT>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"<served-name>","messages":[{"role":"user","content":"hi"}],"max_tokens":10}'

# 3) tool calling
curl -s http://localhost:<PORT>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "<served-name>",
    "messages": [{"role":"user","content":"What is the weather in Seoul?"}],
    "tools": [{
      "type":"function",
      "function":{"name":"get_weather","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}
    }],
    "tool_choice":"auto"
  }' | python3 -m json.tool
```

응답에 `tool_calls` 배열이 박히면 OK.

## 모니터링

```bash
# log tail
tail -f <LOG_PATH>

# GPU 활용률
watch -n 1 'nvidia-smi --query-gpu=index,utilization.gpu,memory.used --format=csv,noheader'

# vLLM 자체 메트릭 (활성화돼있을 때)
curl http://localhost:<PORT>/metrics 2>/dev/null | head -50
```

50+ 동시 요청 정상 시 GPU util 60-90%. 100% 길게 = 큐 적체, scaling 검토.

## 포함 스크립트

- `scripts/launch-vllm.sh <model> <tp> <port> [served-name]` — setsid + nohup + 5분 healthcheck
- `scripts/check-deps.sh` — 의존성 매트릭스 dry-run 검증

## 참고 (운영 사례)

`gem-llm-vllm-debug` 는 이 일반 패턴을 Qwen Coder 32B + Qwen3-Coder-30B-A3B (port 8001/8002) 에 적용한 특화 사례. 처음 띄우는 사용자는 이 `vllm-bootstrap` 부터.
