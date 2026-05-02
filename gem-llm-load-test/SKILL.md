---
name: gem-llm-load-test
description: GEM-LLM 부하 테스트 (locust + asyncio multi-user-bench). 사용 시점 — "부하 테스트 돌려", "50동접 측정", "p99 latency 확인", "처리량 측정", "스케일링 한계", "throughput". locustfile 또는 multi-user-bench.py 둘 다 지원. quota/rate-limit 시나리오 검증 포함.
---

# gem-llm-load-test

## 두 가지 도구

### 1. Locust (단일 키, 다중 워커, RPS 제어)

```bash
GEM_LLM_KEY=gem_live_... \
  /home/jovyan/vllm-env/bin/locust \
  -f /home/jovyan/gem-llm/tests/load/locustfile.py \
  --host http://localhost:8080 \
  --headless \
  --users 10 --spawn-rate 2 --run-time 60s \
  --csv tests/reports/load-$(date +%Y%m%d-%H%M%S)
```

- 4 워크로드: short_chat (50%), coding_help (30%), long_context (15%), streaming_multi_tool (5%)
- **단일 키라 60RPM 제한에서 막힘** — 진짜 처리량 측정 안 됨, *quota/rate-limit 검증* 용

### 2. multi-user-bench (여러 키, 동시 검증)

```bash
# 5명 사용자 + 키 발급 (한 번)
for u in alice bob carol dave eve; do
  RESP=$(bash scripts/admin-cli.sh add-user $u $u@wku.ac.kr pro)
  UID=$(echo "$RESP" | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
  KR=$(bash scripts/admin-cli.sh issue-key "$UID" loadtest)
  echo "$KR" | grep raw_key | python3 -c "import sys,re;m=re.search(r'gem_live_[a-f0-9]+',sys.stdin.read());print(m.group(0))" \
    > tests/load/keys/$u.key
done

# 부하 테스트
/home/jovyan/vllm-env/bin/python tests/load/multi-user-bench.py
```

- 5 keys × 10 workers = **50 concurrent** asyncio 요청
- 200 총 요청, asyncio.gather로 진짜 동시 부하

## 검증된 결과 (2026-05-02)

| 도구 | 동접 | 성공률 | p50 | p99 | 처리량 |
|---|---|---|---|---|---|
| locust 단일키 | 10 워커 | 25%* | 30s** | 60s** | 0.4 req/s |
| locust 단일키 (pool 수정 전) | 10 | 25% | 30s | 60s | 0.4 req/s |
| **multi-user-bench (pool 수정 후)** | **50** | **100%** | **144ms** | **4.1s** | **45 req/s** / **1441 tok/s** |

*단일 키 25% = quota/RPM 제한 정상 작동 (의도)
**SQLAlchemy QueuePool 5+10 한계 — 케이스 12 참조

## SPEC-12 요구사항 충족

- ✅ 50동접 안정
- ✅ p99 < 5초 (4.1s)
- ✅ 처리량 > 30 req/s

## 더 큰 부하 (100, 200동접)

multi-user-bench의 `USERS_PER_KEY` 또는 키 수 증가:

```python
# tests/load/multi-user-bench.py 상단
USERS_PER_KEY = 20  # 5 keys × 20 = 100
TOTAL_REQUESTS = 500
```

Gateway pool size를 추가로 키워야 할 수도 (현재 50+150 = 200). 100동접 안정성 검증 시 200+, 200동접에선 400+ 권장.

## 측정 메트릭

- p50/p95/p99/max latency
- 성공률 / 실패 분류 (HTTP 500, 429, 401, exception)
- 토큰 처리량 (tok/s) = 생성 토큰 / 총 시간
- nvidia-smi GPU 활용률 (별도 측정)

## 결과 저장 위치

- locust CSV: `tests/reports/load-<ts>_stats.csv`, `_failures.csv`, `_stats_history.csv`
- locust markdown: `tests/reports/load-<ts>.md`
- bench는 stdout만 (필요시 `> tests/reports/bench-<ts>.txt`로 redirect)

## 예상 에러 분류

| 에러 | 원인 | 해결 |
|---|---|---|
| 401 invalid_api_key | 키 placeholder 또는 회수 | 환경변수 GEM_LLM_KEY 확인 |
| 429 rate_limited 60/min | 단일 사용자 RPM 초과 | 다중 사용자 키 사용 |
| 429 daily_token_limit | 50K 토큰 초과 | 사용자 quota 증액 (DB) |
| 500 QueuePool timeout | SQLAlchemy pool 부족 | db.py pool_size 증가 (case 12) |
| 500 disk I/O error | SQLite WAL 손상 | _data 재초기화 (case 13) |
| streaming consumed | locust SSE 처리 버그 | 알려진 limitation, 무시 가능 |

## 관련

- 부하 테스트 시 Gateway 로그: `_logs/gateway.log` (ERROR/Traceback grep)
- vLLM 부하 측정: nvidia-smi에서 GPU util 60-90% 정상
