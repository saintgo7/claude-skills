---
name: bulk-user-onboarding-pattern
description: 'CSV/JSON 사용자 일괄 등록 검증된 패턴. 사용 시점 — "bulk add", "bulk register", "bulk users", "CSV 일괄", "사용자 마이그레이션", "idempotent 사용자 등록", "신규 vs 중복 카운트". admin API + 1회 캐싱 + 신규/중복/실패 카운터.'
---

# bulk-user-onboarding-pattern

CSV/JSON 한 줄 = 사용자 1명을 admin API 로 등록하는 *idempotent* 일괄 패턴. 핵심은 (1) 기존 사용자 목록을 **1회만** 조회해 in-memory set 으로 중복을 검사하고, (2) **신규/중복/실패** 3카운터를 명시적으로 출력하며, (3) 같은 입력을 다시 돌려도 dup_count 만 증가하도록 하는 것이다. GEM-LLM 운영에서 76명 (50명 bulk + 26명 수동) 등록 + dup_count 50/50 검증 + 100동접 부하에서 모든 키 인증 통과로 검증.

## 1. 사용 시점

- "bulk add users", "bulk register", "CSV 일괄 등록"
- "사용자 마이그레이션" (legacy → 새 시스템)
- "idempotent 사용자 등록" (재실행 안전)
- "신규 vs 중복 카운트" 가 필요한 admin 도구
- 부하 테스트용 *가짜 사용자* 일괄 생성
- 외부 시스템 (Google Sheet / HR 시스템) 동기화

매 사용자마다 list-users API 를 다시 호출하거나, 등록 결과 카운터 없이 silent fail 이 나는 prototype → production 강화 시점에 적용.

## 2. CSV 형식

```csv
# username,email,plan
# `#` 시작은 주석, 빈 줄 skip
alice,alice@example.com,pro
bob,bob@example.com,free
carol,carol@example.com,pro
```

규칙:
- **`#` 시작 줄** — 주석 (헤더 자동 감지에도 유리)
- **빈 줄** — skip
- **컬럼 순서 고정** — `username,email,plan,[device_label]` (옵션 컬럼은 뒤쪽)
- **인코딩** — UTF-8 (BOM X), Unix LF (CRLF X — `dos2unix` 권장)

JSON 변형이 필요하면 §6.

## 3. idempotent 보장 — 핵심 패턴

```bash
# 1회 list-users 호출 → in-memory set
EXISTING=$(api GET /admin/users | jq -r '.[] | .username')

new_count=0
dup_count=0
fail_count=0

while IFS=',' read -r u e p; do
  # 주석/빈 줄 skip
  [ -z "$u" ] && continue
  case "$u" in \#*) continue ;; esac

  # 중복 검사 (whitespace 패딩으로 부분 일치 방지)
  case " $EXISTING " in
    *" $u "*) dup_count=$((dup_count + 1)); continue ;;
  esac

  if api POST /admin/users "$u" "$e" "$p" >/dev/null 2>&1; then
    new_count=$((new_count + 1))
  else
    fail_count=$((fail_count + 1))
    echo "FAIL: $u" >&2
  fi
done < users.csv
```

### 성능

| | per-user list-users | bulk-users |
|---|---|---|
| 50명 등록 | 50 회 API | **1 회** |
| 200명 등록 | 200 회 | **1 회** |
| GEM-LLM 76명 사례 | 3800회 (76² 권한 검사) | 1회 (76× 감소) |

### 왜 `case` 인가
`grep -q` 도 쓸 수 있지만 (1) subprocess 비용, (2) regex meta 이스케이프 필요. `case` 패턴 매칭은 순수 bash 내장 + glob 만 이스케이프하면 된다.

## 4. 카운터 출력

```
=== bulk-users 결과 ===
  총: 50
  신규 추가: 0
  중복 skip: 50
  실패: 0
```

### idempotent 검증 공식
같은 CSV 재실행 시 `dup_count == total && new_count == 0 && fail_count == 0`.
이 조건이 깨지면 (예: 두 번째 실행에서 new_count > 0) 어딘가에서 사용자가 사라지고 있다는 신호 — 중간에 누군가 revoke 했거나, list-users 가 페이징되어 잘렸을 가능성.

### 종료 코드
- `fail_count > 0` 이면 **non-zero exit** (CI/cron 에서 감지)
- `dup_count > 0` 만 있으면 **0 exit** (정상 idempotent)

## 5. 키 자동 발급 (옵션)

CSV 에 4번째 컬럼 `device_label` 을 두면 사용자 등록 직후 키도 발급:

```bash
while IFS=',' read -r u e p label; do
  ...
  USER_ID=$(api POST /admin/users "$u" "$e" "$p" | jq -r '.id')
  if [ -n "$label" ] && [ "$USER_ID" != "null" ]; then
    api POST /admin/keys "$USER_ID" "$label" \
      | jq -r '.raw_key' >> keys-issued.txt
  fi
done
```

규칙:
- raw key 는 **1회만** 응답에 노출 (관련 skill: `api-key-lifecycle-pattern`)
- `keys-issued.txt` 는 작업자 로컬에만 저장 후 즉시 안전 채널로 전달
- label 이 비어있으면 키 발급 skip (사용자만 등록)

## 6. JSON 변형

```bash
jq -c '.[]' users.json | while read -r user; do
  username=$(echo "$user"  | jq -r '.username')
  email=$(echo "$user"     | jq -r '.email')
  plan=$(echo "$user"      | jq -r '.plan // "free"')
  label=$(echo "$user"     | jq -r '.device_label // empty')
  ...
done
```

`.plan // "free"` 는 jq 의 default 연산자 — 필드가 없으면 `"free"`.

## 7. 흔한 함정

| 증상 | 원인 | 해결 |
|---|---|---|
| 매 사용자마다 list-users API | 캐싱 X | **1회 list-users**, in-memory set |
| 중복 등록 시 silent fail | 카운터 X | 명시적 `new/dup/fail` 3카운터 |
| 인코딩 깨짐 | UTF-8 BOM, CRLF | `dos2unix` + `LANG=C.UTF-8` |
| 큰 CSV (>10k) timeout | API rate limit | 배치 처리 + `sleep 0.05` |
| 중복 검사 부분 일치 | `case "*$u*"` | `case " $EXISTING " in *" $u "*` (whitespace 패딩) |
| CSV 첫 줄이 헤더인지 모호 | 헤더 자동 감지 X | `#` 주석 컨벤션 강제 |
| 권한 누설 | admin token 평문 echo | `set +x` + `${ADMIN_TOKEN:?required}` |

## 8. 부하 테스트 데이터 생성

`load_user_*` prefix 를 두면 운영 사용자와 분리 + 사후 일괄 정리가 쉽다.

```bash
# 50명 가짜 사용자 CSV 생성
{
  echo "# bulk load users — username,email,plan"
  for i in $(seq 1 50); do
    echo "load_user_${i},load${i}@test.local,free"
  done
} > users-load-50.csv
```

정리:
```bash
# load_user_* 만 골라 회수
api GET /admin/users \
  | jq -r '.[] | select(.username | startswith("load_user_")) | .id' \
  | while read -r id; do api DELETE /admin/users/"$id"; done
```

## 9. 보안

- **CSV 평문 비밀번호 X** — 사용자 등록 시 임시 패스워드는 등록 응답에서 1회만 노출, 사용자가 첫 로그인 시 변경
- **운영 DB 백업 후 실행** — bulk 작업은 부분 실패해도 롤백이 어렵다
- **dry-run 옵션 권장** — `--dry-run` 시 카운터만 계산, API call 없음
- **admin token** — `${ADMIN_TOKEN:?required}` 로 미설정 시 즉시 실패
- **CSV 파일 권한** — `chmod 600 users.csv`, 작업 후 `_trash/` 로 이동 (관련 feedback: `feedback_no_rm_rf`)

## 10. 검증된 사례 (GEM-LLM)

- 76 users 등록 (50명 bulk + 26명 수동)
- idempotent 검증: 같은 CSV 재실행 시 dup_count = 50/50, new_count = 0
- list-users API 호출 50회 → **1회** (50× 감소)
- 100동접 부하 시 모든 키가 정상 인증 통과 (실패 0)
- 부하 후 `load_user_*` 일괄 회수 26초 (50명)

## 11. 관련 skill

- `api-key-lifecycle-pattern` — 키 발급/회전/회수 (옵션 4번째 컬럼 연계)
- `concurrent-load-testing-pattern` — bulk 등록 후 100/200 동접 부하 테스트
- `bash-cli-best-practices` — `set -euo pipefail`, sub-cmd, mv to `_trash`, SQL injection 방지
- `quota-rate-limit-pattern` — bulk 등록 후 사용자별 quota 적용
- `fastapi-gateway-pattern` — admin API 서버 측 `/admin/users` 구현
