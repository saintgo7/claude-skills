"""
Extend exam_end to a new timestamp (emergency use, usually for an individual
student's legitimate bug). Saves the original value to a file for later revert.

Env vars:
    QUIZ_ID     — Quiz row ID (default 1)
    NEW_END_UTC — new exam_end as 'YYYY-MM-DD HH:MM:SS' in UTC (required)
    SAVE_PATH   — where to write the original for revert (default /tmp/exam_original_end.txt)

Usage:
    NEW_END_UTC='2026-04-21 03:20:00' python extend_exam.py

IMPORTANT: This extends globally. Any student with the page still loaded can
submit within the extended window. Pair with a watcher loop (revert_on_submit.sh)
that reverts as soon as the target student submits.
"""
import os
import sys
from datetime import datetime, timezone, timedelta

sys.path.insert(0, '/app')
from app import app, db, Quiz  # noqa

QUIZ_ID = int(os.environ.get('QUIZ_ID', '1'))
SAVE_PATH = os.environ.get('SAVE_PATH', '/tmp/exam_original_end.txt')
new_end_str = os.environ.get('NEW_END_UTC')
if not new_end_str:
    print("ERROR: set NEW_END_UTC='YYYY-MM-DD HH:MM:SS' (UTC)", file=sys.stderr)
    sys.exit(2)

NEW_END = datetime.strptime(new_end_str, '%Y-%m-%d %H:%M:%S')  # naive UTC
KST = timezone(timedelta(hours=9))

with app.app_context():
    q = db.session.get(Quiz, QUIZ_ID)
    if q is None:
        print(f"ERROR: Quiz id={QUIZ_ID} not found", file=sys.stderr)
        sys.exit(2)
    orig = q.exam_end
    print(f"[before] exam_end (UTC) = {orig}   KST = {orig.replace(tzinfo=timezone.utc).astimezone(KST)}")

    q.exam_end = NEW_END
    db.session.commit()
    q2 = db.session.get(Quiz, QUIZ_ID)
    print(f"[after]  exam_end (UTC) = {q2.exam_end}   KST = {q2.exam_end.replace(tzinfo=timezone.utc).astimezone(KST)}")

    # Save original for later revert (only if we haven't already)
    if not os.path.exists(SAVE_PATH):
        with open(SAVE_PATH, 'w') as f:
            f.write(orig.isoformat())
        print(f"[saved] original → {SAVE_PATH}")
    else:
        print(f"[note]  {SAVE_PATH} already exists; NOT overwriting (preserves true original)")
