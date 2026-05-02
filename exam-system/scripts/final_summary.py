"""
Post-exam comprehensive statistics report.

Env vars:
    QUIZ_ID            — Quiz row ID (default 1)
    STUDENT_ROLE       — default 'STUDENT'
    TEST_PREFIX        — default 'TEST'

Sections:
    - Submission rate (submitted / total, %)
    - Score stats (mean, median, max, min, perfect count, passing count)
    - Distribution histogram (by 10-point bins)
    - Missing students (for follow-up)
    - Top-5 fastest-high-scorer ranking
    - Per-question accuracy (flags < 30% accuracy as likely-bad questions)
"""
import os
import sys
import json

sys.path.insert(0, '/app')
from app import app, db, User, Quiz, QuizAttempt, QuizQuestion  # noqa

QUIZ_ID = int(os.environ.get('QUIZ_ID', '1'))
STUDENT_ROLE = os.environ.get('STUDENT_ROLE', 'STUDENT')
TEST_PREFIX = os.environ.get('TEST_PREFIX', 'TEST')

with app.app_context():
    quiz = db.session.get(Quiz, QUIZ_ID)
    print(f"=== {quiz.title} ===\n")

    students_q = User.query.filter_by(role=STUDENT_ROLE, is_active=True).filter(~User.student_id.startswith(TEST_PREFIX))
    total = students_q.count()
    attempts = QuizAttempt.query.filter_by(quiz_id=QUIZ_ID).all()
    submitted_ids = {a.user_id for a in attempts}
    missing = students_q.filter(~User.id.in_(submitted_ids)).all() if submitted_ids else students_q.all()

    print(f"Students registered : {total}")
    print(f"Submitted           : {len(attempts)}  ({len(attempts) * 100 / total:.1f}%)")
    print(f"Missing             : {len(missing)}\n")

    scores = [a.score for a in attempts]
    if scores:
        scores_sorted = sorted(scores, reverse=True)
        avg = sum(scores) / len(scores)
        median = scores_sorted[len(scores) // 2]
        perfect = sum(1 for s in scores if s == 100)
        passed = sum(1 for a in attempts if a.passed)
        print("--- Score stats ---")
        print(f"Mean    : {avg:.2f}")
        print(f"Median  : {median}")
        print(f"Max     : {max(scores)}   Min: {min(scores)}")
        print(f"Perfect : {perfect}")
        print(f"Passed (pass_score={quiz.passing_score}) : {passed} / failed: {len(attempts) - passed}\n")

        print("--- Distribution ---")
        for lo, hi in [(90, 100), (80, 89), (70, 79), (60, 69), (0, 59)]:
            cnt = sum(1 for s in scores if lo <= s <= hi)
            bar = '█' * cnt
            print(f"{lo:3d}-{hi:3d}: {cnt:3d}  {bar}")
        print()

    print("--- Missing students ---")
    for u in missing:
        print(f"  {u.student_id}  {u.name}")
    print()

    print("--- Top 5 (score desc, time asc) ---")
    top = (db.session.query(QuizAttempt, User).join(User)
           .filter(QuizAttempt.quiz_id == QUIZ_ID)
           .order_by(QuizAttempt.score.desc(), QuizAttempt.time_spent.asc())
           .limit(5).all())
    for a, u in top:
        print(f"  {u.student_id}  {u.name}  {a.score}pt  ({a.time_spent}s)")
    print()

    print("--- Per-question accuracy (flags <30%) ---")
    questions = QuizQuestion.query.filter_by(quiz_id=QUIZ_ID).order_by(QuizQuestion.order).all()
    for q in questions:
        correct = 0
        for a in attempts:
            answers = json.loads(a.answers) if a.answers else {}
            user_ans = (answers.get(str(q.id)) or '').strip().lower()
            if user_ans == q.correct_answer.strip().lower():
                correct += 1
        accuracy = (correct / len(attempts) * 100) if attempts else 0
        flag = '  ⚠ low-accuracy' if accuracy < 30 and len(attempts) > 0 else ''
        short = q.question[:60] + ('...' if len(q.question) > 60 else '')
        print(f"  Q{q.order + 1:2d} {accuracy:5.1f}%  {short}{flag}")
