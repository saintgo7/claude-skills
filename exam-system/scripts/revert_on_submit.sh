#!/bin/bash
# Watcher loop: polls the DB every 30s, and as soon as TARGET_SID submits,
# reverts exam_end to the original saved in SAVE_PATH.
#
# Required env vars:
#   CONTAINER_NAME      — Docker container running the app
#   QUIZ_ID             — Quiz row ID (default 1)
#   TARGET_SID          — student_id that needs the extension
#   SAVE_PATH           — file where extend_exam.py saved the original exam_end
#                         (default /tmp/exam_original_end.txt)
#   HARD_DEADLINE_KST   — KST time after which we force-revert regardless
#                         (e.g., '2026-04-21 12:20:30')
#
# Usage:
#   CONTAINER_NAME=myapp QUIZ_ID=1 TARGET_SID=20263194 \
#     HARD_DEADLINE_KST='2026-04-21 12:20:30' \
#     ./revert_on_submit.sh &

set -u
: "${CONTAINER_NAME:?set CONTAINER_NAME}"
: "${QUIZ_ID:=1}"
: "${TARGET_SID:?set TARGET_SID}"
: "${SAVE_PATH:=/tmp/exam_original_end.txt}"
: "${HARD_DEADLINE_KST:?set HARD_DEADLINE_KST like '2026-04-21 12:20:30'}"
: "${LOG:=/tmp/exam_revert.log}"

DEADLINE_EPOCH=$(TZ=Asia/Seoul date -d "$HARD_DEADLINE_KST" +%s)

ORIG_ISO=$(cat "$SAVE_PATH" 2>/dev/null)
if [ -z "$ORIG_ISO" ]; then
  echo "[$(date '+%F %T')] ERROR: $SAVE_PATH missing or empty" >> "$LOG"
  exit 2
fi

while true; do
  TS=$(TZ=Asia/Seoul date '+%H:%M:%S')
  OUT=$(docker exec "$CONTAINER_NAME" env QUIZ_ID="$QUIZ_ID" TARGET_SID="$TARGET_SID" ORIG_ISO="$ORIG_ISO" python - <<'PY' 2>&1
import os, sys
from datetime import datetime
sys.path.insert(0, '/app')
from app import app, db, User, QuizAttempt, Quiz
QUIZ_ID = int(os.environ['QUIZ_ID'])
TARGET_SID = os.environ['TARGET_SID']
ORIG_ISO = os.environ['ORIG_ISO']
with app.app_context():
    u = User.query.filter_by(student_id=TARGET_SID).first()
    if not u:
        print('USER_NOT_FOUND'); sys.exit(1)
    att = QuizAttempt.query.filter_by(user_id=u.id, quiz_id=QUIZ_ID).first()
    if not att:
        print('NO_SUBMIT_YET'); sys.exit(0)
    original = datetime.fromisoformat(ORIG_ISO)
    q = db.session.get(Quiz, QUIZ_ID)
    if q.exam_end != original:
        q.exam_end = original
        db.session.commit()
        print(f"REVERTED after {TARGET_SID} submit: score={att.score} time={att.time_spent}s")
    else:
        print('ALREADY_REVERTED')
PY
)

  case "$OUT" in
    NO_SUBMIT_YET)
      echo "[$TS] still waiting for $TARGET_SID" >> "$LOG"
      ;;
    REVERTED*)
      echo "[$TS] $OUT" >> "$LOG"
      echo "[$TS] watcher exiting" >> "$LOG"
      break
      ;;
    ALREADY_REVERTED)
      echo "[$TS] already reverted — exiting" >> "$LOG"
      break
      ;;
    *)
      echo "[$TS] UNEXPECTED: $OUT" >> "$LOG"
      ;;
  esac

  NOW_EPOCH=$(date +%s)
  if [ "$NOW_EPOCH" -gt "$DEADLINE_EPOCH" ]; then
    # Force-revert past hard deadline, regardless of submit status
    docker exec "$CONTAINER_NAME" env QUIZ_ID="$QUIZ_ID" ORIG_ISO="$ORIG_ISO" python - <<'PY'
import os, sys
from datetime import datetime
sys.path.insert(0, '/app')
from app import app, db, Quiz
with app.app_context():
    q = db.session.get(Quiz, int(os.environ['QUIZ_ID']))
    q.exam_end = datetime.fromisoformat(os.environ['ORIG_ISO'])
    db.session.commit()
PY
    echo "[$TS] hard deadline reached — forced revert" >> "$LOG"
    break
  fi

  sleep 30
done
