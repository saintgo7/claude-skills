#!/usr/bin/env bash
# check-deps.sh — print vLLM dependency versions and warn on known-bad combos.
#
# Usage: ./check-deps.sh
#   PY_VENV=/path/to/venv/bin/python ./check-deps.sh   (override python)

set -euo pipefail

PY_BIN="${PY_VENV:-$(command -v python)}"

if [ ! -x "$PY_BIN" ] && ! command -v "$PY_BIN" >/dev/null 2>&1; then
  echo "ERROR: python not found ($PY_BIN). Set PY_VENV=/path/to/python" >&2
  exit 1
fi

echo "[check-deps] python=$($PY_BIN -c 'import sys;print(sys.executable)')"
echo "[check-deps] python version=$($PY_BIN --version 2>&1)"
echo

read_ver() {
  "$PY_BIN" -c "import importlib.metadata as m; print(m.version('$1'))" 2>/dev/null || echo "MISSING"
}

VLLM=$(read_ver vllm)
TRANSFORMERS=$(read_ver transformers)
MISTRAL=$(read_ver mistral_common)
FI_PY=$(read_ver flashinfer-python)
FI_CUBIN=$(read_ver flashinfer-cubin)
TORCH=$(read_ver torch)

printf "%-22s %s\n" "vllm"               "$VLLM"
printf "%-22s %s\n" "transformers"       "$TRANSFORMERS"
printf "%-22s %s\n" "mistral_common"     "$MISTRAL"
printf "%-22s %s\n" "flashinfer-python"  "$FI_PY"
printf "%-22s %s\n" "flashinfer-cubin"   "$FI_CUBIN"
printf "%-22s %s\n" "torch"              "$TORCH"
echo

WARN=0
warn() { echo "WARN: $*"; WARN=$((WARN + 1)); }

case "$VLLM" in
  MISSING) warn "vllm not installed. pip install vllm==0.19.1" ;;
  0.19.*) ;;
  0.20.*) warn "vLLM $VLLM may hit DeepGEMM/FP8 build issues. Verified: 0.19.1" ;;
  0.18.*) warn "vLLM $VLLM uses --disable-log-requests; 0.19+ requires --no-enable-log-requests" ;;
  *) warn "vLLM $VLLM is outside the verified band (0.19.x)" ;;
esac

case "$TRANSFORMERS" in
  MISSING) warn "transformers not installed" ;;
  4.*) warn "transformers $TRANSFORMERS may not recognize Gemma 4 / newer architectures (need 5.7+)" ;;
esac

if [ "$FI_PY" != "MISSING" ] && [ "$FI_CUBIN" != "MISSING" ] && [ "$FI_PY" != "$FI_CUBIN" ]; then
  warn "flashinfer-python ($FI_PY) != flashinfer-cubin ($FI_CUBIN) — must match"
fi

if [ "$MISTRAL" = "MISSING" ]; then
  warn "mistral_common missing — transformers 5.7 needs ReasoningEffort API"
fi

echo
if [ "$WARN" -eq 0 ]; then
  echo "[check-deps] OK"
else
  echo "[check-deps] $WARN warning(s)"
  exit 1
fi
