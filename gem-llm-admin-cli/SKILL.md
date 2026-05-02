---
name: gem-llm-admin-cli
description: GEM-LLM 사용자/API 키 관리. 사용 시점 — "사용자 추가", "키 발급", "키 회수", "사용량 조회", "alice 한테 키 줘", "bulk 사용자 등록", "사용자 목록", "권한 관리". `bash scripts/admin-cli.sh` 또는 직접 admin REST API 호출. raw_key는 한 번만 표시되므로 발급 후 즉시 안전하게 저장.
---

# gem-llm-admin-cli

`bash /home/jovyan/gem-llm/scripts/admin-cli.sh <command>`

## 명령

| | |
|---|---|
| `add-user <username> <email> [plan=free\|pro\|enterprise]` | 사용자 추가 |
| `list-users` | 전체 사용자 |
| `issue-key <user_id> [name]` | API 키 발급 — **raw_key 1회 노출** |
| `list-keys <user_id>` | 사용자별 키 목록 (해시만) |
| `revoke-key <key_id>` | 회수 (revoked=True) |
| `usage [days=7]` | 토큰 사용량 |
| `bulk-users <csv>` | CSV 일괄 추가 (username,email,plan) |

## .env 자동 로드

스크립트가 `/home/jovyan/gem-llm/.env`의 `GATEWAY_ADMIN_KEY`를 자동 사용. 미설정 시 에러.

## 워크플로 1: 신규 사용자 + 키

```bash
RESP=$(bash scripts/admin-cli.sh add-user alice alice@wku.ac.kr pro)
USER_ID=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
bash scripts/admin-cli.sh issue-key "$USER_ID" "laptop"
# raw_key를 안전하게 저장
```

## 워크플로 2: bulk-users CSV

```csv
# username,email,plan
alice,alice@wku.ac.kr,pro
bob,bob@wku.ac.kr,pro
carol,carol@wku.ac.kr,free
# 주석 라인은 #으로 시작
```

```bash
bash scripts/admin-cli.sh bulk-users users.csv
```

키 발급은 별도 — bulk-users는 사용자만. 키는 사용자 ID 받은 후 issue-key 반복.

## 워크플로 3: 키 회수

```bash
# 1. 어떤 키가 있는지 확인
bash scripts/admin-cli.sh list-keys "$USER_ID"
# 2. key_id로 회수
bash scripts/admin-cli.sh revoke-key 01KQM...
```

## REST API 직접 (스크립트 안 거치고)

```bash
ADMIN=$(grep "^GATEWAY_ADMIN_KEY=" /home/jovyan/gem-llm/.env | cut -d= -f2)

# 사용자 추가
curl -s -X POST http://localhost:8080/admin/users \
  -H "X-Admin-Key: $ADMIN" -H "Content-Type: application/json" \
  -d '{"username":"alice","email":"alice@wku.ac.kr","plan":"pro"}'

# 키 발급
curl -s -X POST http://localhost:8080/admin/keys \
  -H "X-Admin-Key: $ADMIN" -H "Content-Type: application/json" \
  -d '{"user_id":"01K...","name":"laptop"}'
```

## quota 변경 (개별 사용자 한도)

현재 admin-cli에는 quota 명령이 없음. DB 직접:

```bash
sqlite3 /home/jovyan/gem-llm/_data/gateway.db \
  "UPDATE quotas SET daily_token_limit=200000, rpm_limit=120 WHERE user_id='01K...'"
```

또는 향후 `admin-cli.sh set-quota <user_id> --daily=N --rpm=M` 추가 권장.

## 키 형식

- prefix: `gem_live_` (8자)
- body: 32자 hex (16 바이트 random)
- DB 저장: SHA256 + salt 해시 (`utils/crypto.py`)
- 노출 채널: 발급 시 응답에만 (raw_key) — 그 후 prefix 8자만 노출

## 보안 주의

- raw_key는 chat 또는 로그에 절대 출력 X (현재 logging middleware는 prefix 8자만 기록)
- bulk-users 사용 시 csv 파일도 commit 금지 (`.gitignore`에 `*.csv` 추가 검토)
- 회수된 키는 즉시 인증 거부 — 재사용 시도하면 401

## 관련 코드

- `src/gateway/gateway/routes/admin.py` — REST endpoint
- `src/gateway/gateway/utils/crypto.py` — 해시 로직
- `src/gateway/gateway/models.py` — User/ApiKey 스키마
