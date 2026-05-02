---
name: deployment-checklist
description: 'LLM/API 서비스 production 배포 전 체크리스트. 사용 시점 — "배포 체크리스트", "production ready", "go-live", "런칭 점검", "사전 검증 체크". 7 영역 (인증/보안/모니터링/스케일/문서/롤백/외부)에 각 5~10 항목, GEM-LLM 28일 운영 검증.'
---

# deployment-checklist

LLM/API 서비스를 production 으로 올리기 전, *어떤 항목을 빠뜨리면 첫 주에 사고가 나는지*를 영역별로 정리한 체크리스트. 단발 점검이 아니라 7 영역 × 5~10 항목 = **56 항목**을 한 번 훑은 뒤, 미충족 항목은 *알고도 보내거나 / 막고 다시 보거나* 의사결정을 강제하는 게 목적이다 — GEM-LLM 28일 운영 + 219 테스트 + 100 동접 부하 통과 후 역산해 만든 표.

## 사용 시점

- "배포 체크리스트", "production ready 점검"
- "go-live 직전 검토", "런칭 사전 검증"
- "런칭하려는데 뭐 빠졌나"
- 베타/스테이징을 production 으로 promotion 하기 전
- 새 인프라 (도메인/DB/모델) 도입 후 첫 외부 노출

본 skill 은 *항목 목록*이고, 각 항목의 구현 패턴은 다른 skill 로 cross-reference (case 12/13/14 등은 `gem-llm-troubleshooting` 의 13 사례 참조).

## 7 영역 한눈에

| # | 영역 | 항목 수 | 핵심 질문 |
|---|---|---|---|
| 1 | 인증 (Authentication) | 8 | 누가 호출했는지 *증명*되나? |
| 2 | 보안 (Security) | 8 | 키/명령/SQL 이 *새거나 / 실행되거나* 하지 않나? |
| 3 | 모니터링 (Observability) | 8 | 죽으면 *알게* 되나? 왜 죽었는지 *볼 수* 있나? |
| 4 | 스케일 (Scaling) | 8 | 목표 동접에서 *DB pool / RPM / GPU 큐* 가 안 터지나? |
| 5 | 문서 (Documentation) | 8 | 새 사람/내일의 내가 *재현* 가능한가? |
| 6 | 롤백 (Rollback) | 8 | 망가지면 *되돌릴* 수 있나? |
| 7 | 외부 (External) | 8 | 도메인/SSL/외부 API 키가 *유효*한가? |

총 **56** 항목. 모두 충족이 이상이지만, 현실은 80~90% 통과 후 미충족 항목을 *기록*하고 가는 게 보통 — 미충족을 *모르는 채로* 가는 것과는 다르다.

## 1. 인증 (Authentication) — 8 항목

- [ ] **API key 형식 정의** — `<prefix>_<32hex>` 형태로 prefix 로 키 종류 구분 (예: `sk_` 사용자 / `admin_` 관리자). 로그에 prefix 만 노출
- [ ] **키 해시 저장** — 평문 저장 금지. SHA256+salt 또는 argon2. DB 가 새도 키는 안 새도록
- [ ] **`revoked` 플래그** — 키 폐기를 *삭제*가 아니라 플래그로 (감사 로그 보존)
- [ ] **admin key 별도 관리** — 관리 API (`/admin/*`) 는 별도 prefix + 별도 검증 경로
- [ ] **OAuth 옵션 (Phase 2)** — 사용자가 늘면 API key 만으로는 한계 → 외부 IdP (Google/GitHub) 옵션 검토
- [ ] **키 노출 방지** — 로그/에러/메트릭에는 prefix 만 (`sk_abc123...` 형태)
- [ ] **키 만료 정책** — 무기한 키는 사고 시 회수가 어렵다. 90일/1년 만료 + rotate 절차
- [ ] **키 발급/폐기 자체 CLI** — 운영자가 코드 안 거치고 발급/회수 가능한 admin CLI (`admin-cli.sh issue/revoke`)

`fastapi-gateway-pattern` 의 인증 계층 + `gem-llm-admin-cli` 의 키 관리 CLI 참조.

## 2. 보안 (Security) — 8 항목

- [ ] **HTTPS 강제** — Cloudflare Tunnel / Let's Encrypt / nginx → HTTP 평문 노출 금지. HSTS 헤더
- [ ] **CORS 정책** — 와일드카드 (`*`) 금지. 필요한 origin 만 화이트리스트
- [ ] **위험 명령 차단 (case 13)** — bash 운영 스크립트에 `rm -rf`, `mkfs`, `dd of=` 등 직접 호출 금지. 삭제는 `mv ... _trash/` 로
- [ ] **SQL injection 방지** — prepared statement / parameterized query 강제. 문자열 연결 SQL 금지 (특히 bash 의 `sqlite3 "SELECT ... '$var'"` 패턴)
- [ ] **secret 환경변수화** — DB URL / HF_TOKEN / API 키 절대 코드에 X. `.env` 또는 secret manager
- [ ] **`.env` `.gitignore` 등록** — 커밋된 `.env` 는 회수 불가. pre-commit hook 으로 차단
- [ ] **감사 로그 (audit trail)** — 누가 / 언제 / 무엇을 — 관리 작업은 모두 로그. `usage_log` + `admin_audit` 분리
- [ ] **요청/응답 본문 마스킹** — 로그에 prompt/completion 전체 저장 시 PII 누출. 길이/해시만 또는 N자 trim

`bash-cli-best-practices` (위험 명령 + SQL injection) + `sqlite-wal-safe-ops` (백업 안전).

## 3. 모니터링 (Observability) — 8 항목

- [ ] **`/healthz`, `/readyz`, `/metrics` 엔드포인트** — `/healthz` (프로세스 살아있나) / `/readyz` (DB+업스트림 연결되나) 분리 필수
- [ ] **Prometheus 커스텀 메트릭** — 표준 Counter/Histogram/Gauge 3계층 (요청 수, 지연, in-flight)
- [ ] **Grafana dashboard** — RPS / p50/p95/p99 / 에러율 / 거부율 4 패널 최소
- [ ] **알림 (Alertmanager 또는 cron)** — 5xx 비율 > X%, 응답 지연 p95 > Xs 임계 알림
- [ ] **로그 집계** — 단일 파일 → 회전 (`logrotate`) 또는 외부 (Loki/ELK). stdout JSON 로깅
- [ ] **error tracking (Sentry 옵션)** — uncaught exception 의 *발생 위치* 추적. 100+ 사용자에서 거의 필수
- [ ] **tracing (OTel 옵션)** — 게이트웨이 → 업스트림 → DB 의 분산 trace. 멀티 서비스 시 권장
- [ ] **메트릭 cardinality 제한** — `user_id`, `request_id` 같은 high-cardinality 라벨 금지. Prometheus OOM

`prometheus-fastapi-metrics` (메트릭 추가) + `fastapi-gateway-pattern` (`/healthz` `/readyz` 구현).

## 4. 스케일 (Scaling) — 8 항목

- [ ] **DB pool size (case 12)** — SQLAlchemy `pool_size=50, max_overflow=150` 이상. 기본값 (5+10) 은 50 동접에서 즉시 timeout
- [ ] **Rate limit (case 14)** — RPM (slowapi) + daily (DB) + concurrent (Semaphore) 3계층. 단일 도구로는 항상 어딘가 새거나 OOM
- [ ] **vLLM TP 설정** — GPU 메모리 / 모델 크기 기준 TP=1/2/4/8 결정. 모델 70B + B200 80GB → TP=2 권장
- [ ] **PostgreSQL 마이그레이션 plan** — SQLite 는 100+ 동접 쓰기에서 write-lock 한계. PG 이전 절차 사전 준비 (`postgres-migration-from-sqlite`)
- [ ] **caching (Redis 옵션)** — quota 캐시 / RPM 분산 / 세션 → 멀티 워커 시 거의 필수
- [ ] **async I/O 일관성** — FastAPI + httpx + SQLAlchemy 모두 async. sync `requests` 한 줄이 워커를 블록 (`fastapi-async-patterns`)
- [ ] **부하 테스트 (50/100/200 동접 검증)** — 목표 동접의 2배까지 단계 테스트. 5xx 0, 429 명확한 reason
- [ ] **타임아웃 + 백프레셔** — httpx/요청/응답/스트리밍 각 단계 timeout. 무한 대기 방지 + 큐 길이 한도

`quota-rate-limit-pattern` + `postgres-migration-from-sqlite` + `gem-llm-load-test` 참조.

## 5. 문서 (Documentation) — 8 항목

- [ ] **README + 빠른 시작** — 5분 안에 `clone → install → run` 까지 가능한 길잡이
- [ ] **API 레퍼런스** — OpenAPI (`/docs`, `/redoc`) 자동 생성 + 예시 cURL
- [ ] **매뉴얼 (User + Admin)** — 사용자용 (어떻게 부르나) + 관리자용 (키 발급/quota 변경/장애 대응) 분리
- [ ] **운영 runbook** — start/stop/status/restart, 흔한 에러 대응 순서
- [ ] **에러 사례집** — 발생한 에러 + 원인 + 수정 (Chapter 16 같은 형태). 13~17 사례 쌓이면 별도 챕터
- [ ] **다이어그램 (Mermaid)** — 컴포넌트 / 시퀀스 / 인증 플로우 — 텍스트로 git diff 가능
- [ ] **CHANGELOG** — 버전별 변경/마이그레이션 노트. SemVer 권장
- [ ] **온보딩 문서** — 새 운영자가 30분 안에 stack 이해 + 로그/메트릭/CLI 접근 가능

`gem-llm-build-docs` (Pandoc 빌드) + `bilingual-book-authoring` (한/영 매뉴얼).

## 6. 롤백 (Rollback) — 8 항목

- [ ] **DB 마이그레이션 reversible** — Alembic `downgrade` 검증. drop column 같은 비가역 변경은 별도 절차
- [ ] **git tag 표시** — 배포할 때마다 `v0.x.x` 태그 + 릴리스 노트
- [ ] **이전 버전 빠른 복원 절차** — `git checkout v0.x.x && supervisor.sh restart` 가 5분 안에 끝나야
- [ ] **DB 백업 (case 13)** — SQLite 는 `.backup` API 또는 WAL 안전 복사 (단순 `cp` 는 corruption). PG 는 `pg_dump` 일일 cron
- [ ] **백업 복원 검증** — 백업이 *복원 가능*한지 분기 1회 리허설. 안 한 백업은 백업이 아님
- [ ] **카나리 배포 옵션** — 새 버전을 일부 사용자/트래픽에만 노출 (5~10%) → 모니터링 후 확대
- [ ] **feature flag** — 새 기능을 환경변수/DB 플래그로 토글. 코드 롤백 없이 끌 수 있어야
- [ ] **마이그레이션 dry-run** — production DB 사본에 마이그레이션 시뮬 → 시간/락/오류 사전 측정

`sqlite-wal-safe-ops` (백업 함정) + `postgres-migration-from-sqlite` (PG 백업).

## 7. 외부 (External) — 8 항목

- [ ] **도메인 + DNS** — Cloudflare Tunnel / Route53 등. CNAME / A 레코드 + TTL 짧게 (장애 시 빠른 전환)
- [ ] **SSL/TLS cert** — Let's Encrypt / Cloudflare 자동 갱신. 만료 알림 30일 전
- [ ] **외부 API key (HF_TOKEN 등)** — HuggingFace, OpenAI, Anthropic 등. 만료/rotate 일정 + secret manager
- [ ] **외부 서비스 SLA 확인** — 의존하는 외부 서비스 (모델 호스트, 인증, 결제) 의 SLA / 장애 페이지 구독
- [ ] **CDN 옵션** — 정적 자산 / 캐시 가능한 GET 응답 → Cloudflare CDN
- [ ] **백업 도메인** — primary 도메인 장애 시 임시 노출 경로 (예: 직접 IP / Tunnel 백업 hostname)
- [ ] **외부 webhook 재시도 정책** — 결제/알림 등 outbound webhook 의 재시도 + dead letter
- [ ] **외부 서비스 장애 fallback** — 외부 IdP / 모델 호스트 다운 시 graceful degradation 경로

`cloudflare-tunnel-setup` (도메인 노출) + `gem-llm-cloudflare-tunnel` (GEM-LLM 특화).

## Go-Live 체크리스트 (단축판)

배포 직전 *반드시* 확인할 5 항목 — 이게 막히면 배포 보류:

1. **모든 테스트 통과** — `pytest` 에서 0 fail (skip 은 사유 명시)
2. **부하 테스트 100% 성공** — 목표 동접에서 5xx 0, 429 reason 분리 확인
3. **`/healthz`, `/readyz` 외부 200** — 도메인 외부에서 cURL 200 (DNS/SSL/방화벽 모두 OK)
4. **모니터링 + 알림 가동** — Grafana 그래프 살아있고 테스트 알림 수신 확인
5. **롤백 플랜 검증** — 실제 이전 버전으로 5분 안에 되돌리는 리허설 1회

위 5 항목은 56 항목과 별개 — 56 항목은 *영역별 사전 점검*, 위 5 는 *go-live 직전 마지막 게이트*.

## 적용 패턴

```
1. templates/checklist.md.template 복사 → docs/deploy-checklist-v0.x.md
2. 영역별로 [ ] → [x] 체크하며 진행
3. 미충족 항목은 [ ] 유지 + "이유 / 보완 일정" 메모
4. PR 에 첨부 → 리뷰어가 미충족을 *알고도 통과*했는지 확인
5. go-live 직전 단축판 5 항목 다시 통과 확인
```

## GEM-LLM 사례 (검증된 항목)

GEM-LLM v0.6 (28일 운영 + 219 테스트 + 100 동접 부하 통과) 시점 충족 현황:

**56 항목 중 48 항목 충족 (87%)**.

**충족** (대표 8):
- 인증: API key `sk_<32hex>` + SHA256+salt + revoked 플래그
- 보안: Cloudflare Tunnel HTTPS, `rm -rf` 차단 (`mv to _trash/`), `?`-bind SQL
- 모니터링: `/healthz` `/readyz` `/metrics` + Grafana 4 패널 + cron 알림
- 스케일: SQLAlchemy `pool_size=50, max_overflow=150` (case 12), 3계층 quota (case 14)
- 문서: 매뉴얼 (User+Admin) + Chapter 16 에러 사례 13개 + Mermaid 다이어그램
- 롤백: Alembic downgrade + git tag + WAL 안전 백업 (case 13)
- 외부: llm.pamout.com + Cloudflare 자동 SSL + HF_TOKEN

**미충족** (4):
- PostgreSQL 마이그레이션 (200+ 동접 대비 plan 만 있음, 실행 X)
- Sentry (Phase 2 예정)
- OTel tracing (단일 게이트웨이라 우선순위 낮음)
- 카나리 배포 (사용자 100명 미만이라 미적용)

이 87% 가 *어떤 영역에서 부족한지* 가 중요 — 모니터링 / 인증 / 보안은 100%, 미충족은 모두 *스케일 확대 시* 필요한 항목들 → 현재 사용자 규모에서는 합리적. 8 미충족이 *모니터링* 쪽이었다면 즉시 보강 필요.

## 흔한 함정

1. **체크리스트를 *처음*에 한 번만** — 배포는 반복. 매 릴리스마다 새 사본을 만들어 그 시점의 미충족을 기록해야 *증가/감소 추세*가 보인다.
2. **항목을 보고서로만 채우기** — `[x]` 만 찍고 실제 검증 안 하면 의미 없음. 항목별로 *증거* (cURL 결과 / 그래프 스크린샷 / 테스트 로그) 첨부.
3. **미충족을 숨기기** — 압박 받으면 `[x]` 로 바꾸고 싶은 유혹. *미충족을 명시*하고 *이유와 보완 일정*을 남기는 게 본 skill 의 핵심 가치.
4. **단축판만 보기** — go-live 5 항목은 *필요조건이지 충분조건 아님*. 56 항목 사전 점검 후의 단축판이라야 의미.

## 관련 skill

- `fastapi-gateway-pattern` — 1/2/3/4 영역의 게이트웨이 측 구현
- `gem-llm-troubleshooting` — case 12/13/14 등 본 체크리스트의 *위반 사례*
- `prometheus-fastapi-metrics` — 영역 3 모니터링 구현
- `quota-rate-limit-pattern` — 영역 4 스케일 구현
- `postgres-migration-from-sqlite` — 영역 4 + 6 (스케일 + 백업)
- `bash-cli-best-practices` — 영역 2 (위험 명령 / SQL injection)
- `sqlite-wal-safe-ops` — 영역 2 + 6 (백업 안전)
- `cloudflare-tunnel-setup` — 영역 7 외부 노출
