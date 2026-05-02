---
name: llm-serving-performance-tuning
description: 'LLM 서빙 (vLLM + FastAPI Gateway) 성능 튜닝 워크플로. 사용 시점 — "처리량 향상", "p99 latency 개선", "동접 100 vs 200", "vLLM 큐 적체", "tok/s", "GPU 활용률", "DB pool", "rate limit 튜닝", "scaling bottleneck". 6단계 (측정 → 분류 → vLLM 튜닝 → Gateway 튜닝 → DB 튜닝 → 재측정), GEM-LLM 50/100/200동접 검증.'
---

# llm-serving-performance-tuning

LLM 서빙 스택 (vLLM 추론 엔진 + FastAPI 게이트웨이 + DB) 의 성능은 *한 곳*만 보고 튜닝하면 거의 항상 잘못된 곳을 만진다 — GPU util 만 보고 vLLM 을 튜닝했더니 실제 병목은 SQLAlchemy pool 이었던 사례 (GEM-LLM case 12). *측정 → 분류 → 계층별 튜닝 → 재측정* 순서로 가야 한다.

이 skill 은 GEM-LLM 50/100/200 동접 부하 테스트에서 검증된 6단계 워크플로다. 각 단계의 도구 · 임계값 · 흔한 함정을 정리한다.

## 1. 사용 시점

- "처리량 향상" / "p99 latency 개선" / "tok/s 측정"
- "동접 100 vs 200 차이" / "scaling bottleneck"
- "vLLM 큐 적체" / "GPU 활용률 낮다"
- "DB pool 한도" / "rate limit 튜닝"
- 단일 요청은 빠른데 동접 50+ 에서 갑자기 느려질 때
- 부하 테스트 결과 해석 (RPS 천장, p99 spike, 5xx 분포)

성능이 *측정 가능*한 단계여야 한다 — 부하 도구 없이 추측만으로는 90% 잘못된 곳을 만진다.

## 2. 6단계 워크플로

### Step 1: 베이스라인 측정

먼저 *지금* 의 수치를 잡는다. 튜닝 후 비교 대상이 없으면 어떤 변경이 효과적이었는지 알 수 없다.

```bash
# locust (HTTP 시나리오 + RPS 제어)
GEM_LLM_KEY=... locust -f locustfile.py \
  --headless --users 50 --spawn-rate 5 --run-time 60s \
  --csv reports/baseline

# 또는 multi-user-bench (asyncio.gather, 진짜 동시)
python templates/load-test.py.template
```

수집할 지표:

| 지표 | 도구 | 의미 |
|---|---|---|
| RPS (req/s) | locust / bench | 처리량 천장 |
| p50/p95/p99 latency | locust / bench | UX 영향 |
| tokens/sec | bench (usage 합산) | vLLM 실제 처리량 |
| Success rate | locust / bench | 5xx/429 분포 |
| GPU util | `nvidia-smi --query-gpu=utilization.gpu` 1초 polling | vLLM 한계 도달 여부 |
| DB pool waiters | SQLAlchemy `pool.status()` | Gateway 병목 신호 |

### Step 2: 병목 분류

베이스라인 결과의 *패턴*으로 병목을 식별한다.

| 증상 | 가능 원인 | 다음 단계 |
|---|---|---|
| 모든 요청 빠른 실패 (500) | DB pool 고갈 (case 12) | Step 4 Gateway |
| 모든 요청 느림 (p50 > 1s, GPU 90%+) | vLLM 큐 적체 | Step 3 vLLM |
| 일부 요청만 느림 (p99 spike, p50 정상) | GC pause / DB lock (case 14) | Step 5 DB |
| 429 다수 | rate limit 한도 너무 낮음 | Step 4 Gateway |
| GPU 0~10% sustained | CPU bottleneck (parsing/encoding) | Step 4 Gateway |
| GPU 90~100% sustained | vLLM 처리량 한계 | Step 3 vLLM (또는 hardware) |
| 5xx 502 from upstream | vLLM 자체 timeout/crash | Step 3 vLLM |

병목이 *둘 이상* 동시에 보인다면 가장 큰 것부터 — 작은 것을 먼저 고치면 더 큰 병목 뒤에 가려진다.

### Step 3: vLLM 튜닝

GPU/메모리/큐 단의 파라미터:

| 파라미터 | 효과 | 트레이드오프 |
|---|---|---|
| `--max-model-len` | 작을수록 KV cache slot 더 많은 동접 | 긴 컨텍스트 못 받음 |
| `--gpu-memory-utilization 0.85→0.90` | KV pool 더 큼 → 동접 증가 | OOM 위험 |
| `--max-num-seqs` | 동시 처리 시퀀스 수 | 너무 크면 batch latency 증가 |
| `--enable-prefix-caching` | 시스템 프롬프트 재사용 | 메모리 ~5% 추가 |
| `--swap-space N` (GiB) | GPU OOM 시 CPU swap | swap I/O 시 latency 증가 |
| `--tensor-parallel-size` | TP=4 vs TP=8 | TP↑ → latency↓ throughput↓ |
| `--enable-chunked-prefill` | 긴 prompt 분할 처리 | 초기 token latency 증가 |

체감 효과 큰 순서: prefix caching → max_num_seqs → gpu_memory_utilization → TP 변경.

```bash
# 예: prefix caching + 큰 KV
vllm serve <model> \
  --enable-prefix-caching \
  --gpu-memory-utilization 0.90 \
  --max-num-seqs 256 \
  --max-model-len 8192
```

### Step 4: Gateway 튜닝

GEM-LLM case 12 가 여기서 발생 — pool 5+10 (기본값) 으로는 50 동접에 즉시 고갈.

| 파라미터 | 기본값 | 권장 (50~200 동접) |
|---|---|---|
| SQLAlchemy `pool_size` | 5 | 50 |
| SQLAlchemy `max_overflow` | 10 | 150 |
| SQLAlchemy `pool_timeout` | 30s | 5s (빠른 실패) |
| asyncio.Semaphore (concurrent) | — | per-user 5~10 |
| slowapi RPM | — | per-key 60~120 (1초 1회 = 너무 낮음) |
| httpx Client connection pool | 100 | 200~500 |
| streaming buffer | default | 8KB chunk (SSE) |
| uvicorn workers | 1 | 1 (asyncio 멀티는 의미 없음, OS 단으로) |

핵심:
- SQLAlchemy QueuePool 은 *async* 에서도 thread-pool 백엔드라 동접 그대로 누적 → pool=50, overflow=150 → 200 동접까지 안전
- slowapi RPM 너무 낮게 (60RPM = 1초 1번) 잡으면 정상 사용자도 막힘 → 단일 키 부하 테스트 결과로 오해
- httpx 의 `max_connections` 가 vLLM 으로 가는 upstream 동접의 천장 — 100 이면 100 동접에서 막힘

### Step 5: DB 튜닝

Concurrent write 가 많아지면 SQLite 가 첫 번째로 무너진다 (case 14: write-lock 경합).

| 항목 | SQLite | PostgreSQL |
|---|---|---|
| 동접 한도 | ~50~100 (WAL) | 200+ |
| Concurrent write | 직렬화 (file lock) | row-level lock |
| 백업 안전성 | journal 파일 손상 가능 | pg_dump |

SQLite 단계 튜닝:
```python
# busy_timeout — write lock 대기 (case 14)
engine = create_engine("sqlite:///./_data/app.db",
    connect_args={"timeout": 30.0})  # 30s busy_timeout

# WAL mode + checkpoint
PRAGMA journal_mode=WAL;
PRAGMA wal_autocheckpoint=1000;
PRAGMA synchronous=NORMAL;
```

100+ 동접에서 그래도 lock 경합이 보이면 PostgreSQL 마이그레이션 (`postgres-migration-from-sqlite` skill 참조).

추가 튜닝 항목:
- 인덱스: `api_keys.key_prefix`, `usage_log(user_id, ts)` — daily quota SUM 가속
- async write batch: UsageLog INSERT 누적 후 1초 단위 flush (write QPS 50→5)
- 일일 누적 캐시 테이블: SUM 매 요청마다 안 돌리고 `daily_usage(user_id, day, total)` 에서 WHERE day=today

### Step 6: 재측정 + 비교

같은 부하 시나리오로 재측정. *한 항목씩* 변경 후 측정해야 어떤 변경이 효과를 냈는지 안다.

| 변경 | 동접 | RPS | p50 | p99 | tok/s | 5xx |
|---|---|---|---|---|---|---|
| 베이스라인 | 50 | ... | ... | ... | ... | ... |
| pool 50+150 | 50 | ... | ... | ... | ... | 0 |
| + prefix caching | 50 | ... | ... | ... | ... | ... |
| + busy_timeout 30s | 100 | ... | ... | ... | ... | ... |

상승이 있어야 변경 유지, 차이 없으면 롤백 (불필요한 복잡도 추가 X).

## 3. GEM-LLM 검증 결과

`templates/load-test.py.template` 기반 multi-user-bench 결과 (B200 1× GPU, 단일 노드):

| 동접 | 성공률 | RPS | p50 | p99 | tok/s |
|---|---|---|---|---|---|
| 50 | 100% | 43.83 | 180ms | 4.2s | 1390 |
| 100 | 100% | 45.41 | 144ms | 8.1s | 1440 |
| 200 | 100% | 41.34 | 2985ms | 17.3s | 1311 |

핵심 발견:
- **RPS 천장 ~45** — 동접을 더 늘려도 RPS 가 거의 변하지 않음 = vLLM 처리량 한계
- **200 동접 = p99 17초** — UX 부적합 (사용자 기다림 한계 5~8초)
- **권장 sustainable: 75~100 동접** — RPS 유지 + p99 < 10s
- 200 동접에서도 5xx 0% — Gateway/DB 단은 잘 막아냄, 진짜 한계는 vLLM 처리량
- tok/s 1282~1440 안정적 — KV cache 가 적절히 재사용됨

100 동접 부하 시 GPU util 88% 평균 → vLLM 거의 풀가동, 추가 동접은 큐 대기로 변환됨.

## 4. 흔한 함정

1. **단일 요청 latency 만 측정** — 1 동접에서 200ms 인 요청이 50 동접에서 5초 (case 12). 반드시 *동시* 부하로 측정.

2. **DB pool 기본값 그대로** — SQLAlchemy 5+10 은 production 부적합. 100 동접에서 즉시 고갈 + `QueuePool timeout` 500.

3. **rate limit 너무 낮음** — 60 RPM = 1초 1번. 정상 사용자도 막힘. multi-key 시나리오에서만 진짜 부하 보임.

4. **GPU OOM** — `--max-model-len 32768` 같이 큰 값 + KV cache 부족 → 동접 증가 시 OOM. `--gpu-memory-utilization 0.85` + `--swap-space 4` 가 안전 출발점.

5. **prefix caching 미활성화** — 시스템 프롬프트가 매 요청마다 재계산 → ~30% throughput 낭비. `--enable-prefix-caching` 켜면 거의 공짜.

6. **transformers fallback** — vLLM native 가 모델을 지원 안 할 때 transformers backend 사용 → 5x 느림. 모델 선택 시 vLLM 지원 확인.

7. **단일 키 부하 테스트** — 1 키로 50 워커 = 60 RPM 한도에서 99% 실패. quota/rate-limit 검증용으론 OK 지만 *처리량* 측정 안 됨. multi-key 필수.

8. **uvicorn 멀티 worker** — async 게이트웨이는 단일 worker 가 정상. 멀티 worker 는 메모리만 늘어나고 asyncio.Semaphore 가 per-process 라 한도 N 배 허용됨.

9. **부하 후 GPU util 안 본다** — RPS/latency 만 보면 vLLM 한계인지 Gateway 한계인지 모름. nvidia-smi 동시 측정 필수.

## 5. 측정 도구

| 도구 | 용도 | 강점 | 약점 |
|---|---|---|---|
| locust | HTTP 시나리오 부하 | 시나리오 가중치, RPS 제어, CSV/HTML | 단일 키 + RPM 제한에 막힘 |
| asyncio + httpx (`load-test.py.template`) | 진짜 동시 부하 | multi-key, 정확한 동접 | 시나리오 단순 |
| `nvidia-smi --query-gpu` | GPU util | sub-second 정확 | 단일 시점 |
| Prometheus + Grafana | 지속적 관측 | 시간축 + 라벨 | 설정 비용 |
| wrk2 | 저레이턴시 측정 | 매우 가벼움 | LLM streaming 부적합 |

부하 테스트는 *최소 60초* — 30초 미만은 prefix cache 워밍업 단계만 보고 끝남.

## 6. 시작 체크리스트

1. `templates/load-test.py.template` 복사 → 키 5~10개 발급 (`gem-llm-admin-cli` 또는 자체 admin)
2. 베이스라인 50/100/200 동접 각각 60초 측정 → CSV 저장
3. 결과를 Step 2 표에 매핑 → 가장 큰 병목 1개 식별
4. 해당 계층(Step 3/4/5) 의 *한 파라미터*만 변경
5. 재측정 → 개선 있으면 유지, 없으면 롤백
6. 다음 병목 식별 → 반복
7. 최종 sustainable 동접 결정 (p99 < 10s 기준)

## 7. 관련 skill

- `prometheus-fastapi-metrics` — 게이트웨이 메트릭 수집 (RPS/latency/실패율 라벨)
- `quota-rate-limit-pattern` — Step 4 의 rate-limit 3계층 (slowapi RPM + Semaphore + DB daily)
- `postgres-migration-from-sqlite` — Step 5 SQLite 한계 도달 시 이전
- `vllm-bootstrap` — Step 3 vLLM 의존성 매트릭스 + 부팅 실패 패턴
- `vllm-tool-calling` — tool parser 가 GPU util 에 미치는 영향
- `gem-llm-load-test` — GEM-LLM 특화 부하 테스트 절차
- `observability-bundle` — Prometheus + Loki + OTel 통합 관측
