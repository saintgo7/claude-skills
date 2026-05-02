# Exam Day Playbook

End-to-end runbook for a single online exam session. All times below are relative to `T` = exam start moment.

## T−24h : Pre-exam prep

- [ ] Verify `Quiz` row: `is_exam=True`, `is_published=True`, `exam_start` / `exam_end` in UTC, `shuffle_questions=True`, `max_attempts=1`.
- [ ] Verify question count and question-type distribution matches the announced spec.
- [ ] Announce exam in two places (written notice file + in-app bulletin board). **Cross-check the weekday label.** We once shipped a notice saying "April 21 (Mon)" when April 21 was a Tuesday — students noticed.
- [ ] Confirm the announced *time zone* on the notice. Students read raw times and forget KST/UTC distinction.
- [ ] Verify student accounts: count active non-TEST accounts, confirm all have passwords set. Post a reminder that password resets must happen *before* exam day.

## T−1h : Dry-run checks

Run these in parallel:

```bash
# Site reachability
curl -sk -o /dev/null -w "public=%{http_code}|%{time_total}s\n" https://$EXAM_URL/
curl -s  -o /dev/null -w "local=%{http_code}|%{time_total}s\n"  http://127.0.0.1:$LOCAL_PORT/

# Clock drift check — host UTC vs public Date header (should match to the second)
date -u '+%a, %d %b %Y %H:%M:%S GMT'
curl -sI https://www.google.com | grep -i '^date:'

# DB sanity — print the exam row's UTC/KST times and question count
docker exec $CONTAINER_NAME python /path/to/db_snapshot.py
```

**Sign-off criteria:** site 200 OK, local latency < 10 ms, public latency < 1 s, clock drift = 0, DB times match the announcement (to the second and microsecond — both should be `:00.000000`).

## T−0 : Exam opens

```bash
# Start 30-second live monitor
CONTAINER_NAME=... QUIZ_ID=... EXAM_URL=... \
  EXAM_START_KST='...' EXAM_END_KST='...' \
  bash scripts/monitor.sh

# Also kick off auto-reset loop (15-second cadence, 180 s threshold)
bash scripts/auto_reset_loop.sh &
```

**Signals of a clean opening:**
- `exam_status` transitions `NOT_STARTED` → `ACTIVE` within 1 second of `T`.
- Container network I/O jumps +20 to +60 MB in the first minute (students downloading the page + question JSON).
- `ss` shows TCP connections to the gunicorn port appear and drain quickly (short-lived HTTP).

**Signals to escalate:**
- Container CPU pegged > 50 % for more than 30 s → likely a pathological loop, not traffic.
- Public HTTP > 2 s or 5xx → reverse-proxy or tunnel issue.
- Zero network I/O at `T+30s` → nobody could actually load the page; something is blocking between cloudflared / nginx / gunicorn.

## T+0 to T+5 : Accidental-submit wave

Expect 1–3 students to accidentally click submit within the first minute. Typical `time_spent` = 10 – 90 seconds, score = 0 – 4.

Auto-reset loop handles these if `time_spent < 180`. If the user disagrees with the threshold, adjust `THRESHOLD_SEC` in `scripts/auto_reset.py`.

**Policy note to confirm with the user before running:** "Any submission with `time_spent < N` seconds will be auto-deleted so the student can retry. Proceed?"

## T+5 to T+40 : Steady state

Most activity is client-side; server traffic is near zero. Students submit one-by-one starting around T+8 to T+15.

Continue showing a monitor snapshot every minute or on user request. Report:
- New submissions since last snapshot
- Any submissions with `time_spent < 180` that the auto-reset loop caught (they re-appear in the reset log)
- Network I/O delta (proxy for late-joiners)

## T+40 to T+50 : Final-minute rush

Submission rate peaks in the last 10 minutes. Expect +5 to +10 submissions per minute around T+45 to T+50.

Watch for edge cases:
- A student reports "submit button does nothing" — could be network blip, session timeout, or anti-cheat auto-submit triggered. Check their user row for any `QuizAttempt`. If none, they haven't submitted and need to refresh + retry.
- A student reports "page is frozen" — usually fullscreen-exit warning loop. Tell them to press Esc → refresh → re-enter → submit.

**Do not restart gunicorn.** Do not modify Flask session secrets. Do not touch cloudflared.

## Individual deadline extension (emergency)

**Use case:** One student had a legitimate client-side bug and needs extra minutes beyond `exam_end`.

**The model has no per-student override.** The only levers:
1. Extend `exam_end` globally.
2. Start a watcher that reverts `exam_end` the moment that student submits.
3. Accept the blast radius: any other student who still has the page open *could* also submit during the extension window.

```bash
# Extend by N minutes (e.g., 20 → 12:10 KST became 12:30 KST)
docker exec $CONTAINER_NAME python /path/to/extend_exam.py --new-end 'YYYY-MM-DD HH:MM:SS'

# Start watcher (polls every 30 s, reverts on submit by target_student_id)
TARGET_SID=20263194 bash scripts/revert_on_submit.sh &
```

**Always confirm with the user** before extending. The confirmation should state: "Extending to {new_end} globally; auto-revert as soon as {student} submits; exposure window max {minutes} min."

## T+50 : Exam ends

Status transitions `ACTIVE` → `ENDED`. The monitor shows `[[시험 종료]]`.

Tear down loops:
```bash
# Kill the background monitors and auto-reset loops
pkill -f monitor.sh
pkill -f auto_reset_loop
```

Cancel any cron jobs scheduled for the live monitoring cadence (e.g., the CronCreate `*/1 * * * *` status prompt).

## T+50 onward : Post-exam

Generate the final report:

```bash
docker exec $CONTAINER_NAME python /path/to/final_summary.py
```

Report sections:
1. Submission rate (submitted / total, percentage)
2. Score distribution (mean, median, max, min, histogram by 10-point bin)
3. Top-N fastest high-scorers
4. Per-question accuracy (flag any with < 30 % correct — likely a bad question)
5. List of non-submitters (for individual follow-up)
6. Any auto-reset / extension incidents from the logs

## Security retrospective

Run within the first few hours:

```bash
bash scripts/security_check.sh
```

Looks at:
- App container logs for error patterns, SQL injection probes, path traversal, XSS probes
- New user accounts created in the last 24 hours (should be 0 — students don't self-register)
- Privileged accounts (should only be pre-existing admin/professor)
- Host-level SSH auth failures, fail2ban bans, suspicious cron changes

**Expected result: clean.** An exam shouldn't introduce attack surface; the page is read-heavy with one POST per student per exam.

## Known limitations to communicate to the user

- **Cannot count "currently taking the exam"** — no server-side session list; sessions are signed cookies. Use network I/O deltas as a proxy.
- **Cannot audit individual HTTP requests after the fact** — gunicorn access logs are off by default and cloudflared tunnel doesn't log per-request. Plan for this before the next exam, not during.
- **No per-user exam_end override** — the global extend + watcher-revert is a workaround, not a clean solution. If per-user deadlines become frequent, add a `QuizAttemptExtension` model in the post-retro code change.
