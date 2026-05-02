#!/bin/bash
# Exam-day live monitor snapshot.
#
# Required env vars:
#   CONTAINER_NAME   — Docker container running the Flask app
#   QUIZ_ID          — Quiz row ID being monitored (used by db_snapshot.py)
#   EXAM_URL         — Public HTTPS endpoint for reachability check
#   LOCAL_URL        — Local endpoint (e.g., http://127.0.0.1:10291/)
#   EXAM_START_KST   — "YYYY-MM-DD HH:MM:SS" in KST
#   EXAM_END_KST     — "YYYY-MM-DD HH:MM:SS" in KST
#   LOCAL_PORT       — port the reverse proxy hits (for TCP connection count)
#   RESET_LOG        — (optional) path to auto_reset log to display tail of
#
# Usage:
#   CONTAINER_NAME=myapp QUIZ_ID=1 EXAM_URL=https://exam.example.com \
#     LOCAL_URL=http://127.0.0.1:5001 LOCAL_PORT=5001 \
#     EXAM_START_KST='2026-04-21 11:00:00' EXAM_END_KST='2026-04-21 11:50:00' \
#     ./monitor.sh

set -u

: "${CONTAINER_NAME:?set CONTAINER_NAME}"
: "${QUIZ_ID:=1}"
: "${EXAM_URL:?set EXAM_URL}"
: "${LOCAL_URL:=http://127.0.0.1:5001/}"
: "${LOCAL_PORT:=5001}"
: "${EXAM_START_KST:?set EXAM_START_KST}"
: "${EXAM_END_KST:?set EXAM_END_KST}"
: "${RESET_LOG:=/tmp/exam_auto_reset.log}"

NOW_KST=$(TZ=Asia/Seoul date '+%Y-%m-%d %H:%M:%S')
NOW_EPOCH=$(date +%s)
START_EPOCH=$(TZ=Asia/Seoul date -d "$EXAM_START_KST" +%s)
END_EPOCH=$(TZ=Asia/Seoul date -d "$EXAM_END_KST" +%s)
DELTA_START=$((START_EPOCH - NOW_EPOCH))
DELTA_END=$((END_EPOCH - NOW_EPOCH))

if [ $DELTA_START -gt 0 ]; then
  M=$((DELTA_START / 60)); S=$((DELTA_START % 60))
  COUNT="T-${M}:${S}  (exam opens in ${M}m ${S}s)"
elif [ $DELTA_END -gt 0 ]; then
  M=$((DELTA_END / 60)); S=$((DELTA_END % 60))
  COUNT="[[IN PROGRESS]]  ${M}m ${S}s to end"
else
  COUNT="[[ENDED]]"
fi

echo "════════════════════════════════════════════════════════"
echo "  Exam Monitor   ${NOW_KST} KST"
echo "  ${COUNT}"
echo "════════════════════════════════════════════════════════"

HTTP=$(curl -sk -o /dev/null -w '%{http_code}|%{time_total}s' "$EXAM_URL" --max-time 5 || echo 'err')
LOCAL=$(curl -s  -o /dev/null -w '%{http_code}|%{time_total}s' "$LOCAL_URL" --max-time 5 || echo 'err')
echo "[site]     public=${HTTP}   local=${LOCAL}"

EXAM_JSON=$(curl -sk "${EXAM_URL%/}/api/exams/current" --max-time 5 2>/dev/null || true)
STATUS=$(echo "$EXAM_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['exam_status'])" 2>/dev/null || echo "?")
echo "[exam]     exam_status=${STATUS}"

STATS=$(docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}|{{.PIDs}}' "$CONTAINER_NAME" 2>/dev/null || echo 'err|err|err|err')
IFS='|' read -r CPU MEM NETIO PIDS <<< "$STATS"
echo "[container] CPU=${CPU}  MEM=${MEM}  NET=${NETIO}  PIDs=${PIDS}"

ACTIVE=$(ss -tn state established "( dport = :${LOCAL_PORT} or sport = :${LOCAL_PORT} )" 2>/dev/null | tail -n +2 | wc -l)
echo "[conn]     active TCP to :${LOCAL_PORT} = ${ACTIVE}"

docker exec "$CONTAINER_NAME" python /tmp/db_snapshot.py 2>/dev/null || echo "[db]       (db_snapshot.py not deployed in container — copy it with: docker cp scripts/db_snapshot.py ${CONTAINER_NAME}:/tmp/)"

if [ -s "$RESET_LOG" ]; then
  RESET_COUNT=$(wc -l < "$RESET_LOG")
  echo "[reset]    total ${RESET_COUNT} (last 5)"
  tail -5 "$RESET_LOG" | sed 's|^|           |'
fi

echo "════════════════════════════════════════════════════════"
