"""
Auto-delete accidental short submissions so the student can retry.

Default threshold: 180 seconds. Submissions below this are physically impossible
for any reasonable exam, so they're always accidental (student clicked submit
without answering).

Env vars:
    QUIZ_ID            — Quiz row ID (default 1)
    THRESHOLD_SEC      — seconds below which submissions are auto-reset (default 180)

Pair with a loop that runs this every 15–30s during the exam:
    while true; do docker exec CONTAINER python /tmp/auto_reset.py; sleep 15; done
"""
import os
import sys
from datetime import timezone, timedelta

sys.path.insert(0, '/app')
from app import app, db, QuizAttempt, User  # noqa

QUIZ_ID = int(os.environ.get('QUIZ_ID', '1'))
THRESHOLD_SEC = int(os.environ.get('THRESHOLD_SEC', '180'))
KST = timezone(timedelta(hours=9))

with app.app_context():
    short = (db.session.query(QuizAttempt, User)
             .join(User, QuizAttempt.user_id == User.id)
             .filter(QuizAttempt.quiz_id == QUIZ_ID)
             .filter(QuizAttempt.time_spent < THRESHOLD_SEC)
             .all())
    if not short:
        sys.exit(0)

    for a, u in short:
        t = a.completed_at.replace(tzinfo=timezone.utc).astimezone(KST).strftime('%H:%M:%S')
        print(f"RESET {t} {u.student_id} {u.name} attempt_id={a.id} time_spent={a.time_spent}s score={a.score}")
        db.session.delete(a)
    db.session.commit()
