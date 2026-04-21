"""
Per-student status lookup. Useful when a student reports a problem.

Env vars:
    QUIZ_ID     — default 1
    STUDENT     — student_id or name to look up (required)

Finds the user, reports their submission status, and prints any QuizAttempt
rows. Doesn't modify anything — safe to run during a live exam.
"""
import os
import sys
from datetime import timezone, timedelta

sys.path.insert(0, '/app')
from app import app, db, User, QuizAttempt  # noqa

QUIZ_ID = int(os.environ.get('QUIZ_ID', '1'))
STUDENT = os.environ.get('STUDENT')
if not STUDENT:
    print("ERROR: set STUDENT=<student_id or name>", file=sys.stderr)
    sys.exit(2)

KST = timezone(timedelta(hours=9))

with app.app_context():
    # Try student_id exact first, then name LIKE
    users = User.query.filter_by(student_id=STUDENT).all()
    if not users:
        users = User.query.filter(User.name.like(f'%{STUDENT}%')).all()

    if not users:
        print(f'No match for "{STUDENT}"')
        sys.exit(1)

    for u in users:
        print(f'[user] id={u.id}  student_id={u.student_id}  name={u.name}  role={u.role}  active={u.is_active}')
        atts = (QuizAttempt.query
                .filter_by(user_id=u.id, quiz_id=QUIZ_ID)
                .order_by(QuizAttempt.completed_at)
                .all())
        print(f'  submissions: {len(atts)}')
        for a in atts:
            t = a.completed_at.replace(tzinfo=timezone.utc).astimezone(KST).strftime('%H:%M:%S')
            print(f'   - attempt_id={a.id}  submitted={t}  score={a.score}  time={a.time_spent}s  passed={a.passed}')
        if not atts:
            print('   → not yet submitted')
