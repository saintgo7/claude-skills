#!/usr/bin/env bash
# launch-vllm.sh — generalized vLLM launcher with healthcheck polling.
#
# Usage: ./launch-vllm.sh <model> <tp> <port> [served-name]
#   model        HF repo (e.g. Qwen/Qwen2.5-Coder-32B-Instruct) or local path
#   tp           tensor-parallel size (1/2/4/8)
#   port         HTTP port (e.g. 8001)
#   served-name  optional API model name (defaults to basename of model)
#
# Behavior:
#   - setsid + nohup so the server survives the parent shell
#   - logs to ${VLLM_LOG_DIR:-./_logs}/vllm-<port>.log
#   - polls /v1/models for up to 5 minutes
#   - never uses rm -rf
#
# Required env (optional but recommended):
#   PY_VENV          path to python venv (default: $(which python))
#   CUDA_VISIBLE_DEVICES  comma-list of GPU indices (default: 0..tp-1)
#   TOOL_CALL_PARSER hermes (default) | mistral | pythonic | ...
#   MAX_MODEL_LEN    default 32768
#   GPU_MEM_UTIL     default 0.85

set -euo pipefail

if [ $# -lt 3 ]; then
  echo "Usage: $0 <model> <tp> <port> [served-name]" >&2
  exit 64
fi

MODEL="$1"
TP="$2"
PORT="$3"
SERVED_NAME="${4:-$(basename "$MODEL" | tr '[:upper:]' '[:lower:]')}"

PY_BIN="${PY_VENV:-$(command -v python)}"
LOG_DIR="${VLLM_LOG_DIR:-./_logs}"
LOG_FILE="${LOG_DIR}/vllm-${PORT}.log"
TOOL_PARSER="${TOOL_CALL_PARSER:-hermes}"
MAX_LEN="${MAX_MODEL_LEN:-32768}"
GPU_UTIL="${GPU_MEM_UTIL:-0.85}"

# Default GPU mask = 0..TP-1 if not provided
if [ -z "${CUDA_VISIBLE_DEVICES:-}" ]; then
  GPUS=$(seq -s, 0 $((TP - 1)))
else
  GPUS="$CUDA_VISIBLE_DEVICES"
fi

mkdir -p "$LOG_DIR"

echo "[launch] model=$MODEL tp=$TP port=$PORT served=$SERVED_NAME gpus=$GPUS"
echo "[launch] log=$LOG_FILE parser=$TOOL_PARSER max_len=$MAX_LEN gpu_util=$GPU_UTIL"

CUDA_VISIBLE_DEVICES="$GPUS" setsid nohup "$PY_BIN" \
  -m vllm.entrypoints.openai.api_server \
  --model "$MODEL" \
  --tensor-parallel-size "$TP" \
  --host 0.0.0.0 --port "$PORT" \
  --served-model-name "$SERVED_NAME" \
  --max-model-len "$MAX_LEN" \
  --gpu-memory-utilization "$GPU_UTIL" \
  --enable-prefix-caching \
  --enable-auto-tool-choice --tool-call-parser "$TOOL_PARSER" \
  > "$LOG_FILE" 2>&1 < /dev/null &

VLLM_PID=$!
echo "[launch] pid=$VLLM_PID — polling /v1/models for up to 5 minutes"

DEADLINE=$(( $(date +%s) + 300 ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if ! kill -0 "$VLLM_PID" 2>/dev/null; then
    echo "[launch] FAIL: process exited. Tail of log:" >&2
    tail -40 "$LOG_FILE" >&2 || true
    exit 1
  fi
  if curl -fsS "http://127.0.0.1:${PORT}/v1/models" >/dev/null 2>&1; then
    echo "[launch] OK: /v1/models responding (pid=$VLLM_PID)"
    exit 0
  fi
  sleep 5
done

echo "[launch] TIMEOUT after 5 minutes. Tail of log:" >&2
tail -60 "$LOG_FILE" >&2 || true
exit 2
