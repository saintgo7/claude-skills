"""
Flask routes for exam start (GET quiz) and submit (POST answers).

Key logic:
- UTC time gating with 60s grace on submit
- Professor/Admin bypass (is_privileged)
- Deterministic per-user question shuffle
- Already-submitted + time-window state machine (NOT_STARTED / ACTIVE / ALREADY_SUBMITTED / ENDED)
"""
import json
import random
from datetime import datetime, timezone, timedelta
from flask import Blueprint, request

from models import db, Quiz, QuizQuestion, QuizAttempt, _aware

exam_bp = Blueprint('exam', __name__)

GRACE_SECONDS = 60


def api_response(success, message='', data=None, status_code=200):
    from flask import jsonify
    return jsonify({'success': success, 'message': message, 'data': data}), status_code


# ---- Replace with your own auth + role helpers ----
def get_current_user():
    """Return the logged-in user or None. Implement using your auth system."""
    raise NotImplementedError


def is_privileged_user(user):
    """Return True for PROFESSOR / ADMIN roles."""
    return user is not None and getattr(user, 'role', None) in ('PROFESSOR', 'ADMIN')


@exam_bp.route('/api/quizzes/<int:quiz_id>', methods=['GET'])
def api_quiz_detail(quiz_id):
    user = get_current_user()
    quiz = db.session.get(Quiz, quiz_id)
    if not quiz:
        return api_response(False, 'Quiz not found', status_code=404)

    is_privileged = is_privileged_user(user)

    if not quiz.is_exam:
        return api_response(True, data=quiz.to_dict(include_questions=True, hide_answers=not is_privileged))

    now_utc = datetime.now(timezone.utc)
    exam_ended = quiz.exam_end and now_utc > _aware(quiz.exam_end)

    if is_privileged:
        d = quiz.to_dict(include_questions=True, hide_answers=False)
        d['exam_status'] = 'ACTIVE'
        d['is_privileged'] = True
        return api_response(True, data=d)

    if not user:
        return api_response(False, 'Login required to take exam', status_code=401)

    attempt_count = QuizAttempt.query.filter_by(user_id=user.id, quiz_id=quiz.id).count()
    already_submitted = quiz.max_attempts > 0 and attempt_count >= quiz.max_attempts

    if quiz.exam_start and now_utc < _aware(quiz.exam_start):
        d = quiz.to_dict(include_questions=False)
        d['exam_status'] = 'NOT_STARTED'
        return api_response(True, data=d)

    if already_submitted and exam_ended:
        d = quiz.to_dict(include_questions=True, hide_answers=False)
        d['exam_status'] = 'ALREADY_SUBMITTED'
        d['show_answers'] = True
        return api_response(True, data=d)

    if already_submitted:
        d = quiz.to_dict(include_questions=False)
        d['exam_status'] = 'ALREADY_SUBMITTED'
        d['show_answers'] = False
        return api_response(True, data=d)

    if exam_ended:
        d = quiz.to_dict(include_questions=False)
        d['exam_status'] = 'ENDED'
        return api_response(True, data=d)

    # ACTIVE: serve questions, hide answers, deterministic shuffle
    d = quiz.to_dict(include_questions=True, hide_answers=True)
    d['exam_status'] = 'ACTIVE'
    d['is_privileged'] = False

    if quiz.shuffle_questions and user:
        rng = random.Random(user.id * 10000 + quiz.id)
        rng.shuffle(d['questions'])
        for i, q in enumerate(d['questions']):
            q['order'] = i

    return api_response(True, data=d)


@exam_bp.route('/api/quizzes/<int:quiz_id>/submit', methods=['POST'])
def api_quiz_submit(quiz_id):
    user = get_current_user()
    if not user:
        return api_response(False, 'Login required', status_code=401)

    quiz = db.session.get(Quiz, quiz_id)
    if not quiz:
        return api_response(False, 'Quiz not found', status_code=404)
    if not quiz.is_published:
        return api_response(False, 'Quiz is unpublished', status_code=400)

    is_privileged = is_privileged_user(user)

    if quiz.is_exam and not is_privileged:
        now_utc = datetime.now(timezone.utc)
        grace = timedelta(seconds=GRACE_SECONDS)
        if quiz.exam_start and now_utc < _aware(quiz.exam_start):
            return api_response(False, 'Exam has not started yet', status_code=400)
        if quiz.exam_end and now_utc > _aware(quiz.exam_end) + grace:
            return api_response(False, 'Exam has ended', status_code=400)
        if quiz.max_attempts > 0:
            existing = QuizAttempt.query.filter_by(user_id=user.id, quiz_id=quiz.id).count()
            if existing >= quiz.max_attempts:
                return api_response(False, 'Already submitted — no re-attempt allowed', status_code=400)

    payload = request.get_json(silent=True) or {}
    answers = payload.get('answers', {})
    time_spent = int(payload.get('time_spent', 0))

    if not answers:
        return api_response(False, 'No answers provided', status_code=400)

    questions = QuizQuestion.query.filter_by(quiz_id=quiz_id).order_by(QuizQuestion.order).all()
    if not questions:
        return api_response(False, 'Quiz has no questions', status_code=400)

    total_points = sum(q.points for q in questions)
    earned = 0
    results = []
    for q in questions:
        user_ans = (answers.get(str(q.id)) or '').strip()
        is_correct = user_ans.lower() == q.correct_answer.lower() if user_ans else False
        if is_correct:
            earned += q.points
        results.append({
            'question_id': q.id,
            'user_answer': user_ans,
            'correct_answer': q.correct_answer,
            'is_correct': is_correct,
            'explanation': q.explanation,
            'points': q.points,
        })

    score = int((earned / total_points) * 100) if total_points > 0 else 0
    passed = score >= quiz.passing_score

    attempt = QuizAttempt(
        user_id=user.id, quiz_id=quiz_id,
        answers=json.dumps(answers, ensure_ascii=False),
        score=score, passed=passed, time_spent=time_spent,
        started_at=datetime.now(timezone.utc) - timedelta(seconds=time_spent),
        completed_at=datetime.now(timezone.utc),
    )
    db.session.add(attempt)
    db.session.commit()

    # Exam mode: hide score/answers from student until exam ends
    if quiz.is_exam and not is_privileged:
        return api_response(True, 'Submitted', data={
            'attempt_id': attempt.id, 'submitted': True, 'is_exam': True,
        })

    return api_response(True, 'Submitted', data={
        'attempt_id': attempt.id,
        'score': score, 'passed': passed,
        'results': results,
    })
