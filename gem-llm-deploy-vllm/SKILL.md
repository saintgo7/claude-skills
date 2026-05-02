---
name: gem-llm-deploy-vllm
description: Start, stop, and health-check the GEM-LLM project's two vLLM model servers (Gemma-based serving + auxiliary model). Use when the user says "vllm 띄워", "vllm 재시작", "vllm 헬스체크", "모델 서버 기동", "vllm 종료/내려", "포트 충돌", "GPU OOM", "vllm 로그 확인", or anything about running OpenAI-compatible endpoints on this single-node 8xB200 box. Generates vllm serve commands with proper tensor-parallel size, dtype, served-model-name, port, and gpu-memory-utilization. Honors single-node constraint (no NCCL multi-node). Logs go to /home/jovyan/gem-llm/_logs/vllm-*.log.
---

# gem-llm-deploy-vllm

vLLM 두 모델 (Gemma 4 main + auxiliary) 의 기동/정지/헬스체크 스킬.

## When to use

- "vllm 띄워줘", "vllm 시작", "model serve"
- "vllm 종료", "vllm 내려"
- "vllm 헬스체크", "/v1/models 확인"
- "포트 8000 충돌", "OOM", "GPU 메모리 부족"
- vllm 로그/에러 디버깅

## Environment constraints (memory)

- 단일 노드 `wku-vs-01-0` 8xB200 (NCCL/RDMA 멀티노드 불가)
- 분산 학습/서빙 X — 항상 `--tensor-parallel-size N`은 1~8 사이, **never** `--pipeline-parallel-size > 1` cross-node
- RAM 2.2TB / vCPU 288 — KV cache 여유 충분
- K8s pod 환경 — `nvidia-smi`는 컨테이너 내부에서 동작

## Standard launch (Gemma 4 main, port 8000)

```bash
mkdir -p /home/jovyan/gem-llm/_logs
nohup vllm serve <model-path-or-hf-id> \
  --tensor-parallel-size 8 \
  --dtype bfloat16 \
  --gpu-memory-utilization 0.90 \
  --max-model-len 32768 \
  --served-model-name gemma-4-main \
  --port 8000 \
  --host 0.0.0.0 \
  --enable-auto-tool-choice \
  --tool-call-parser hermes \
  > /home/jovyan/gem-llm/_logs/vllm-main-$(date +%Y%m%d-%H%M%S).log 2>&1 &
echo "PID: $!"
```

## Auxiliary model (port 8001)

```bash
nohup vllm serve <aux-model> \
  --tensor-parallel-size 2 \
  --dtype bfloat16 \
  --gpu-memory-utilization 0.45 \
  --served-model-name aux-model \
  --port 8001 \
  --host 0.0.0.0 \
  > /home/jovyan/gem-llm/_logs/vllm-aux-$(date +%Y%m%d-%H%M%S).log 2>&1 &
```

두 모델 동시 기동 시 GPU 분리 사용:
- main: `CUDA_VISIBLE_DEVICES=0,1,2,3,4,5` (TP=6) 또는 `0..5`
- aux : `CUDA_VISIBLE_DEVICES=6,7` (TP=2)

## Health check

```bash
curl -s http://localhost:8000/v1/models | jq .
curl -s http://localhost:8001/v1/models | jq .
```

기대 응답: `{"object":"list","data":[{"id":"gemma-4-main",...}]}`

GPU 상태:
```bash
nvidia-smi --query-gpu=index,memory.used,memory.total,utilization.gpu --format=csv
```

## Graceful stop

```bash
# 포트로 PID 찾기
PID=$(lsof -ti :8000)
[ -n "$PID" ] && kill -INT $PID
# 30초 후에도 살아있으면 SIGTERM
sleep 30 && kill -TERM $PID 2>/dev/null
```

`pkill -9 vllm` 같은 광역 kill은 사용자 명시 승인 후에만.

## Troubleshooting

- **CUDA OOM**: `--gpu-memory-utilization` 낮추거나 `--max-model-len` 줄임
- **포트 충돌**: `lsof -i :8000` 후 기존 프로세스 확인 — 임의 kill 금지
- **NCCL 에러**: 단일노드만 — `NCCL_P2P_DISABLE=1`, `NCCL_IB_DISABLE=1` 설정
- **Tool calling 실패**: `--enable-auto-tool-choice --tool-call-parser hermes` 누락 여부

## Logs

모든 vllm 로그는 `/home/jovyan/gem-llm/_logs/vllm-*.log`. 오래된 로그는 `mv` 로 `_trash/`에 격리, `rm` 금지.
