#!/bin/bash
# Post-exam security retro. Read-only checks for attack signatures.
#
# Required env:
#   CONTAINER_NAME      — Docker container running the app
#   LOCAL_PORT          — app port (for public-exposure check)
#
# Exits 0 if clean, 1 if any signal found (operator should review the output).

set -u
: "${CONTAINER_NAME:?set CONTAINER_NAME}"
: "${LOCAL_PORT:=5001}"

FOUND=0
report() { echo "$1"; FOUND=1; }

echo "=== 1. App container errors (24h) ==="
OUT=$(docker logs "$CONTAINER_NAME" --since 24h 2>&1 | grep -iE 'error|exception|traceback|500' | tail -20)
[ -n "$OUT" ] && report "$OUT" || echo "  clean"

echo
echo "=== 2. Injection-pattern probes in app logs ==="
OUT=$(docker logs "$CONTAINER_NAME" --since 24h 2>&1 | grep -iE '\.\./|/etc/passwd|/proc/self|<script|wp-admin|phpmyadmin|union.*select|drop.*table|%27|%22' | tail -20)
[ -n "$OUT" ] && report "$OUT" || echo "  clean"

echo
echo "=== 3. SSH auth failures (24h) ==="
OUT=$(sudo journalctl -u ssh --since '24 hours ago' 2>/dev/null | grep -iE 'failed|invalid' | tail -10)
OUT2=$(sudo tail -200 /var/log/auth.log 2>/dev/null | grep -iE 'failed|invalid' | tail -10)
[ -n "$OUT$OUT2" ] && report "$OUT$OUT2" || echo "  clean"

echo
echo "=== 4. fail2ban current bans ==="
sudo fail2ban-client status sshd 2>/dev/null | grep -E 'Banned IP|Currently banned'

echo
echo "=== 5. Exposed port check (should be 127.0.0.1 only) ==="
LINE=$(ss -tln | grep -E ":${LOCAL_PORT}")
echo "  $LINE"
if echo "$LINE" | grep -qE '0.0.0.0|^\*|::\*'; then
  report "  WARN: app port is externally exposed"
fi

echo
echo "=== 6. New privileged accounts (24h via app DB) ==="
docker exec "$CONTAINER_NAME" python - <<'PY'
import sys
sys.path.insert(0, '/app')
from app import app, User
from datetime import datetime, timezone, timedelta
with app.app_context():
    since = datetime.now(timezone.utc) - timedelta(hours=24)
    recent = User.query.filter(User.created_date >= since).all()
    print(f"  new accounts in 24h: {len(recent)}")
    priv = User.query.filter(User.role != 'STUDENT').all()
    print(f"  privileged accounts (total): {len(priv)}")
    for u in priv:
        print(f"    {u.student_id}  {u.name}  role={u.role}  created={u.created_date}")
PY

echo
echo "=== 7. Recent changes to sensitive dirs (7d) ==="
OUT=$(find /etc/ssh /etc/sudoers.d 2>/dev/null -type f -mtime -7 -printf '%TY-%Tm-%Td %TH:%TM %p\n')
[ -n "$OUT" ] && report "$OUT" || echo "  clean"

echo
if [ $FOUND -eq 0 ]; then
  echo "=== RESULT: CLEAN ==="
else
  echo "=== RESULT: SIGNALS FOUND — review above ==="
fi
exit $FOUND
