"""
Example exam seed script. Idempotent: re-running updates the existing quiz.

Run inside your Flask app's runtime context:
    docker exec $CONTAINER_NAME python /app/seed_exam_example.py
"""
import json
from datetime import datetime, timezone

from models import db, Quiz, QuizQuestion
# from your_flask_app import app  # Replace with your Flask app import

# Adjust to your exam's actual times (always UTC in DB).
EXAM_TITLE = 'Midterm Example (2026)'
EXAM_START = datetime(2026, 4, 21, 2, 0, tzinfo=timezone.utc)   # 11:00 KST
EXAM_END   = datetime(2026, 4, 21, 2, 50, tzinfo=timezone.utc)  # 11:50 KST
TIME_LIMIT_MINUTES = 50
PASSING_SCORE = 60

# Each question: dict with question, type, options (MCQ only), answer, explanation, points.
QUESTIONS = [
    {
        'question': 'Example multiple-choice question?',
        'type': 'MULTIPLE_CHOICE',
        'options': ['A', 'B', 'C', 'D'],
        'answer': 'B',
        'explanation': 'B is correct because ...',
        'points': 2,
    },
    {
        'question': 'Example true/false statement.',
        'type': 'TRUE_FALSE',
        'options': [],
        'answer': 'true',
        'explanation': 'This is true because ...',
        'points': 2,
    },
    # ...add more
]


def seed():
    # with app.app_context():  # uncomment and wire up to your app
    quiz = Quiz.query.filter_by(title=EXAM_TITLE).first()
    if not quiz:
        quiz = Quiz(title=EXAM_TITLE)
        db.session.add(quiz)

    quiz.description = 'Example exam seeded by seed_exam_example.py'
    quiz.passing_score = PASSING_SCORE
    quiz.time_limit = TIME_LIMIT_MINUTES
    quiz.is_published = True
    quiz.is_exam = True
    quiz.exam_start = EXAM_START.replace(tzinfo=None)  # store as naive UTC
    quiz.exam_end = EXAM_END.replace(tzinfo=None)
    quiz.max_attempts = 1
    quiz.shuffle_questions = True
    db.session.flush()

    # Clear existing questions and re-seed (idempotent)
    QuizQuestion.query.filter_by(quiz_id=quiz.id).delete()

    for i, q in enumerate(QUESTIONS):
        db.session.add(QuizQuestion(
            quiz_id=quiz.id,
            question=q['question'],
            question_type=q['type'],
            options=json.dumps(q.get('options', []), ensure_ascii=False),
            correct_answer=q['answer'],
            explanation=q.get('explanation', ''),
            points=q.get('points', 1),
            order=i,
        ))

    db.session.commit()
    print(f'Seeded quiz id={quiz.id} with {len(QUESTIONS)} questions')
    print(f'  exam_start (UTC): {quiz.exam_start}')
    print(f'  exam_end   (UTC): {quiz.exam_end}')


if __name__ == '__main__':
    seed()
