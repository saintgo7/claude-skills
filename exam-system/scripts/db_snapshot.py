"""
One-shot DB snapshot for the monitor loop.

Run inside the app container:
    docker exec $CONTAINER_NAME python /tmp/db_snapshot.py

Env vars:
    QUIZ_ID            — Quiz row ID (default 1)
    STUDENT_ROLE       — role string for students (default 'STUDENT')
    TEST_PREFIX        — student_id prefix to exclude as test accounts (default 'TEST')

Adjust import paths (`from app import ...`) to your project.
"""
import os
import sys

# Your project's Flask app import — change as needed
sys.path.insert(0, '/app')
from app import app, db, Quiz, QuizAttempt, User  # noqa

from datetime import timezone, timedelta

QUIZ_ID = int(os.environ.get('QUIZ_ID', '1'))
STUDENT_ROLE = os.environ.get('STUDENT_ROLE', 'STUDENT')
TEST_PREFIX = os.environ.get('TEST_PREFIX', 'TEST')
KST = timezone(timedelta(hours=9))

with app.app_context():
    total = (User.query
             .filter_by(role=STUDENT_ROLE, is_active=True)
             .filter(~User.student_id.startswith(TEST_PREFIX))
             .count())
    submitted = QuizAttempt.query.filter_by(quiz_id=QUIZ_ID).count()
    print(f"[db]       students={total}  submitted={submitted}  missing={total - submitted}")

    recent = (db.session.query(QuizAttempt, User)
              .join(User, QuizAttempt.user_id == User.id)
              .filter(QuizAttempt.quiz_id == QUIZ_ID)
              .order_by(QuizAttempt.completed_at.desc())
              .limit(5).all())
    if recent:
        print("[recent]")
        for a, u in recent:
            t = a.completed_at.replace(tzinfo=timezone.utc).astimezone(KST).strftime('%H:%M:%S')
            print(f"           {t}  {u.student_id:>10}  {u.name:10}  score={a.score:3}  ({a.time_spent}s)")
