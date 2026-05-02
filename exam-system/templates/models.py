"""
Quiz / QuizQuestion / QuizAttempt models for Flask-SQLAlchemy.

Extracted from a production exam system. All exam times are UTC in DB.
Attach to your existing Flask app and adapt User.id foreign key target to your schema.
"""
from datetime import datetime, timezone
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()


class Quiz(db.Model):
    __tablename__ = 'quizzes'
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text, default='')
    passing_score = db.Column(db.Integer, default=70)
    time_limit = db.Column(db.Integer, nullable=True)       # minutes
    is_published = db.Column(db.Boolean, default=True)
    created_date = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))

    # ---- Exam-mode fields ----
    is_exam = db.Column(db.Boolean, default=False)
    exam_start = db.Column(db.DateTime, nullable=True)      # naive UTC
    exam_end = db.Column(db.DateTime, nullable=True)        # naive UTC
    max_attempts = db.Column(db.Integer, default=0)         # 0 = unlimited
    shuffle_questions = db.Column(db.Boolean, default=False)
    show_score_to_student = db.Column(db.Boolean, default=False)

    questions = db.relationship(
        'QuizQuestion', backref='quiz', lazy=True,
        order_by='QuizQuestion.order', cascade='all, delete-orphan',
    )

    def to_dict(self, include_questions=False, hide_answers=True):
        d = {
            'id': self.id,
            'title': self.title,
            'description': self.description,
            'passing_score': self.passing_score,
            'time_limit': self.time_limit,
            'is_published': self.is_published,
            'question_count': len(self.questions),
            'is_exam': bool(self.is_exam),
            'exam_start': self.exam_start.isoformat() if self.exam_start else None,
            'exam_end': self.exam_end.isoformat() if self.exam_end else None,
            'max_attempts': self.max_attempts or 0,
            'shuffle_questions': bool(self.shuffle_questions),
            'show_score_to_student': bool(self.show_score_to_student),
        }
        if include_questions:
            d['questions'] = [q.to_dict(hide_answer=hide_answers) for q in self.questions]
        return d


class QuizQuestion(db.Model):
    __tablename__ = 'quiz_questions'
    id = db.Column(db.Integer, primary_key=True)
    quiz_id = db.Column(db.Integer, db.ForeignKey('quizzes.id'), nullable=False)
    question = db.Column(db.Text, nullable=False)
    question_type = db.Column(db.String(20), default='MULTIPLE_CHOICE')  # or TRUE_FALSE, SHORT_ANSWER
    options = db.Column(db.Text, default='[]')                           # JSON array string
    correct_answer = db.Column(db.String(500), nullable=False)
    explanation = db.Column(db.Text, default='')
    points = db.Column(db.Integer, default=1)
    order = db.Column(db.Integer, default=0)

    def to_dict(self, hide_answer=True):
        d = {
            'id': self.id,
            'quiz_id': self.quiz_id,
            'question': self.question,
            'question_type': self.question_type,
            'options': self.options,
            'points': self.points,
            'order': self.order,
            'explanation': '' if hide_answer else self.explanation,
        }
        if not hide_answer:
            d['correct_answer'] = self.correct_answer
        return d


class QuizAttempt(db.Model):
    __tablename__ = 'quiz_attempts'
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    quiz_id = db.Column(db.Integer, db.ForeignKey('quizzes.id'), nullable=False)
    answers = db.Column(db.Text, default='{}')               # JSON {question_id: "answer"}
    score = db.Column(db.Integer, default=0)                 # 0-100
    passed = db.Column(db.Boolean, default=False)
    time_spent = db.Column(db.Integer, default=0)            # seconds
    started_at = db.Column(db.DateTime)                      # naive UTC
    completed_at = db.Column(db.DateTime)                    # naive UTC


def _aware(dt):
    """Treat naive UTC datetimes from DB as tz-aware UTC for comparison."""
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt
