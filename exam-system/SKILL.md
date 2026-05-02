---
name: exam-system
description: Flask-based online exam system template with anti-cheat, per-student time gating, and exam-day operational tooling. TRIGGER when the user wants to build, deploy, or operate an online exam/quiz/test system; asks about exam timing/grace/shuffle logic; needs real-time monitoring of student submissions during a live exam; wants to extend an individual student's deadline; or asks about anti-cheat (tab switching, copy/paste block, fullscreen, F12 block). SKIP for general programming questions unrelated to exams.
---

# Online Exam System

Reusable template and operational playbook for running online exams.  
Battle-tested on a 66-student university midterm (Apr 2026) with 92% submission rate, 0 server errors, and successful handling of accidental-submit recovery and individual deadline extension.

## What this skill provides

| Category | Asset |
|---|---|
| **Backend template** | `templates/models.py` — Flask-SQLAlchemy `Quiz` / `QuizQuestion` / `QuizAttempt` models with exam fields (start/end, max_attempts, shuffle) |
| | `templates/exam_api.py` — start/submit endpoints with UTC time gating, 60-second grace, deterministic per-user shuffle, role-based answer visibility |
| **Frontend template** | `templates/anti_cheat.js` — tab-switch detection (3-strike auto-submit), copy/paste block, contextmenu block, F12 / Ctrl+Shift+I block, fullscreen enforcement, deterministic option shuffle |
| **Deployment** | `templates/docker-compose.yml`, `templates/Dockerfile.prod` — gunicorn + SQLite volume pattern |
| **Seeding** | `templates/seed_exam_example.py` — seed quiz + questions idempotently |
| **Exam-day scripts** | `scripts/monitor.sh` — parameterized live dashboard (site health, TCP sessions, submission count, recent submitters, reset log) |
| | `scripts/db_snapshot.py` — submission stats snapshot |
| | `scripts/auto_reset.py` — auto-delete extremely short submissions (accidental-submit recovery) |
| | `scripts/extend_exam.py` — emergency exam_end extension with auto-revert watcher pattern |
| | `scripts/final_summary.py` — post-exam comprehensive stats (score distribution, per-question accuracy, top-N) |
| | `scripts/check_student.py` — per-student status lookup |
| **Operations** | `playbook.md` — T-1h → T+50min runbook covering pre-exam health checks, 11:00 gate verification, live monitoring loop, accidental-submit handling, individual extension workflow, post-exam security check |

## When to use

- Building a Flask/Python online exam system from scratch (fork the templates)
- Adding exam mode (time-bound, anti-cheat, shuffle) to an existing quiz app
- Operating a live exam today: start monitoring, diagnose student issues, extend deadlines, run post-exam reporting
- Doing post-incident analysis on an exam that already happened

## How to use

### For new projects (copy templates)
```bash
cp -r ~/.claude/skills/exam-system/templates/* <your_project>/
# Then wire up the models into your Flask app, register routes, adjust field names to your schema
```

### For live exam operations (parameterize scripts)
All scripts accept these env vars (see inline docs in each script):
- `CONTAINER_NAME` — Docker container running the Flask app
- `QUIZ_ID` — Quiz row ID to monitor
- `EXAM_URL` — Public HTTPS endpoint (e.g. `https://exam.example.com`)
- `LOCAL_URL` — Local gunicorn endpoint (e.g. `http://127.0.0.1:5001`)
- `EXAM_START_KST` / `EXAM_END_KST` — e.g. `2026-04-21 11:00:00`

```bash
# Live monitoring (30s interval)
CONTAINER_NAME=myapp QUIZ_ID=1 EXAM_URL=https://exam.example.com \
  EXAM_START_KST='2026-04-21 11:00:00' EXAM_END_KST='2026-04-21 11:50:00' \
  bash ~/.claude/skills/exam-system/scripts/monitor.sh
```

### For operational decisions (follow the playbook)
`playbook.md` contains the T-1h → T+50min runbook with decision trees for:
- Short-submission auto-reset threshold (180s default — why)
- Individual deadline extension workaround (global extend + watcher-revert) since the underlying model has no per-user override
- Sign-off criteria (what counts as "exam went well")

## Key design decisions (from experience)

1. **All exam times in UTC.** Store `exam_start` / `exam_end` as naive UTC `datetime`. Compare with `datetime.now(timezone.utc)`. The client-side timer computes from `exam_end` so server and browser agree. Rendering to local time only happens at the presentation layer.

2. **60-second grace on submit.** The server-side submit endpoint accepts submissions up to 60 s past `exam_end` to account for network/click latency. Student-facing timer uses exact `exam_end` so they see the countdown end on time.

3. **Deterministic shuffle.** Both backend and frontend use `(user_id * 10000 + quiz_id)` as the seed. Guarantees: same student gets same order across refreshes; different students get different orders; reproducible for grading disputes. The frontend shuffle for OPTIONS uses `seed + question_id` so option order is stable per-question per-student.

4. **Submit records the only authoritative attempt data.** No "started" event is stored. This means you cannot count "who is taking the exam right now" from the DB. Use `ss` / network I/O deltas as proxy indicators. Document this limitation with the user.

5. **Accidental submit recovery.** Students sometimes click submit within seconds of the exam starting. Default policy: auto-reset any `QuizAttempt` where `time_spent < 180` seconds, giving them re-attempt capability. Threshold is a `sysadmin × professor` policy call — 180 s is the floor for "physically impossible to have read 50 questions."

6. **No per-student deadline override in the model.** If one student needs extra time (exam bug, disability accommodation), you must extend `exam_end` globally and revert as soon as they submit. `scripts/extend_exam.py` + a watcher loop is the workaround. Document the blast radius for the user before extending.

7. **Professors and admins bypass all gating.** `is_privileged` short-circuits the time window, max_attempts, and answer-hiding logic. This makes it easy to preview or grade-override without temporarily modifying data.

## Anti-pattern to avoid

**Don't restart gunicorn during an exam to enable access logs.** The urge to add `--access-logfile` mid-exam for monitoring is strong but any restart drops in-flight students. Accept the audit-log gap, use DB + network I/O proxies, and add access logging in the post-exam retro instead.

## References in this skill

- `playbook.md` — exam-day runbook
- `templates/` — backend / frontend / deployment starting points
- `scripts/` — exam-day operational tools (parameterized by env vars)
