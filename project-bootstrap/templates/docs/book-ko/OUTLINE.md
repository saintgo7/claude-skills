# GEM-LLM 한국어 책 상세 OUTLINE (~500p)

> **프로젝트:** GEM-LLM — 단일 노드 8×B200에서 Qwen Coder Dense(31B) + MoE(26B-A4B) 동시 서빙 플랫폼
> **대상 독자:** LLM 서빙 엔지니어, ML 인프라 운영자, 시스템 아키텍트
> **총 분량:** 본문 약 450p + 부록 50p = 500p
> **다이어그램:** diagram-01 ~ diagram-40 (모든 다이어그램 ID는 `/home/jovyan/gem-llm/docs/diagrams/CATALOG.md` 참조)

---

## Part I — 기초 (Foundations) — 약 80p / 3 Chapters

### Chapter 1. 왜 GEM-LLM인가 (~25p)
**학습 목표 박스:**
- 단일 노드에서 두 모델을 동시에 서빙해야 하는 비즈니스/기술적 이유 이해
- 50동접 + OpenAI 호환 + 사내망이라는 제약 조건의 의미 파악
- 본 책의 전체 로드맵 인지

- 1.1 LLM 서빙 시장의 현재 (~3p)
- 1.2 자체 호스팅이 필요한 순간 — 데이터 주권, 비용 곡선, 컴플라이언스 (~4p)
- 1.3 GEM-LLM의 5대 설계 원칙 (단일 노드, 멀티 모델, OpenAI 호환, OAuth-Ready, 관측 가능) (~4p)
- 1.4 사용 시나리오 — 사내 챗봇, 코드 어시스턴트, 문서 요약 봇 (~4p)
- 1.5 책의 구성과 읽는 법 (Part 별 가이드) (~3p)
- 1.6 사전 준비물 — 계정/툴/배경 지식 체크리스트 (~3p)
- 1.7 용어 정의 — Dense, MoE, Active Param, Tunnel (~4p)
- **다이어그램:** diagram-01 (시스템 전체상), diagram-02 (사용자 여정 개요)
- **실습 박스:** `curl https://llm.pamout.com/v1/models` 으로 첫 호출 체험

### Chapter 2. 인프라 — B200, GPFS, K8s Pod (~30p)
**학습 목표 박스:**
- B200 8장 노드의 실제 토폴로지(NVLink/PCIe/메모리)와 한계 이해
- 카카오클라우드 K8s 환경에서의 제약 (NCCL/RDMA 불가) 인지
- GPFS 공유 스토리지 위에서의 모델 가중치 배치 전략 학습

- 2.1 NVIDIA B200 — Hopper 후속, FP8/BF16, 메모리 대역폭 (~5p)
- 2.2 노드 토폴로지 — 8 GPU × 180GB HBM, NVLink 도메인 (~4p)
- 2.3 카카오클라우드 K8s — Pod 단위 배치, NCCL/RDMA 비활성 환경 (~4p)
- 2.4 GPFS 분산 파일 시스템 — 모델 가중치/체크포인트 공유 (~4p)
- 2.5 CUDA/cuDNN/NCCL 버전 매트릭스 (~3p)
- 2.6 단일 노드 vs 멀티 노드 — 본 프로젝트가 단일 노드인 이유 (~4p)
- 2.7 메모리 산정 — Dense 31B + MoE 26B 동시 적재 (~4p)
- 2.8 네트워크 — Cloudflare Tunnel 진입점 한 줄 요약 (~2p)
- **다이어그램:** diagram-03 (B200 노드 토폴로지), diagram-04 (Pod-GPFS-Tunnel 인프라)
- **코드 예제:** `예제 2.1 - nvidia-smi topo -m 출력 해석`

### Chapter 3. Qwen Coder 모델 패밀리 분석 (~25p)
**학습 목표 박스:**
- Qwen2.5-Coder-32B Dense와 26B-A4B MoE 모델의 구조적 차이 이해
- Active Parameter 4B의 의미와 추론 비용에 미치는 영향
- 컨텍스트 길이/토크나이저/포맷 차이 파악

- 3.1 Qwen2.5-Coder-32B Dense — 아키텍처 개요 (~4p)
- 3.2 Qwen3-Coder-30B-A3B MoE — 라우팅, expert 수, top-k (~5p)
- 3.3 토크나이저 — SentencePiece, vocab, 한국어 처리 (~3p)
- 3.4 컨텍스트 길이 정책 — 32K/128K, RoPE 스케일링 (~3p)
- 3.5 채팅 템플릿 — system/user/assistant 포맷 (~3p)
- 3.6 함수 호출(tool use) 능력 비교 (~3p)
- 3.7 모델 선택 가이드 — 언제 Dense, 언제 MoE를 (~4p)
- **다이어그램:** diagram-05 (Dense vs MoE 구조 비교)
- **코드 예제:** `예제 3.1 - chat_template 적용 코드`

---

## Part II — 아키텍처 (Architecture) — 약 100p / 4 Chapters

### Chapter 4. 시스템 설계 개요 (~25p)
**학습 목표 박스:**
- GEM-LLM 6대 컴포넌트(vLLM x2, Gateway, CLI, Admin UI, Auth)의 역할 분리 이해
- 동기/비동기 경계와 큐잉 지점 파악

- 4.1 6대 컴포넌트 정의 (~3p)
- 4.2 컨트롤 플레인 vs 데이터 플레인 (~3p)
- 4.3 요청 라이프사이클 (CLI → Gateway → vLLM → 응답) (~4p)
- 4.4 모델 라우팅 정책 — model name 기반 분기 (~3p)
- 4.5 동시성 모델 — async, semaphore, 50동접 처리 (~4p)
- 4.6 장애 도메인 — 어떤 부품이 죽으면 어디까지 죽는가 (~4p)
- 4.7 외부 의존성 지도 (Cloudflare, GPFS, Hugging Face Hub) (~4p)
- **다이어그램:** diagram-06 (컴포넌트 관계도), diagram-07 (요청 라이프사이클 시퀀스)

### Chapter 5. 다이어그램 모음 — 시각화로 보는 GEM-LLM (~30p)
**학습 목표 박스:**
- 본 책 전체에 사용되는 핵심 다이어그램을 한 곳에서 조망
- 각 다이어그램의 정확한 해석 능력 획득

- 5.1 시스템 전체상 (diagram-01, diagram-08) (~5p)
- 5.2 인증/인가 흐름 (diagram-13~16) (~5p)
- 5.3 vLLM 토폴로지 — TP/PP/EP 어디까지 쓰나 (diagram-17~20) (~6p)
- 5.4 데이터 모델 ER (diagram-21~22) (~4p)
- 5.5 배포 토폴로지 — Cloudflare Tunnel (diagram-25~28) (~4p)
- 5.6 CLI 사용 흐름 (diagram-29~32) (~3p)
- 5.7 모니터링 대시보드 (diagram-36~38) (~3p)
- **다이어그램:** diagram-01, 06~08, 13~22, 25~32, 36~38

### Chapter 6. 데이터 모델 (~22p)
**학습 목표 박스:**
- User/APIKey/Conversation/Message/UsageLog 5대 엔티티 설계 의도 이해
- 마이그레이션 전략과 인덱스 정책 학습

- 6.1 ERD 개요 (~3p)
- 6.2 User — id, email, role, created_at, oauth_sub (~3p)
- 6.3 APIKey — hashed_key, scope, rate_limit, expires_at (~4p)
- 6.4 Conversation/Message — 대화 이력 저장 (~4p)
- 6.5 UsageLog — token in/out, model, latency_ms (~3p)
- 6.6 인덱스/파티셔닝 전략 (~3p)
- 6.7 마이그레이션 — Alembic 운용 (~2p)
- **다이어그램:** diagram-21 (ERD), diagram-22 (UsageLog 시계열 모델)
- **코드 예제:** `예제 6.1 - SQLAlchemy 모델 정의`

### Chapter 7. 보안 모델 (~23p)
**학습 목표 박스:**
- API key 해싱/회전/회수 메커니즘 이해
- Google OAuth 플로우(Phase 2)의 도입 이유와 단계
- Cloudflare Tunnel이 제공하는 보안 경계 이해

- 7.1 위협 모델 — STRIDE 적용 (~4p)
- 7.2 API key 라이프사이클 — 발급/저장/검증/회수 (~4p)
- 7.3 Google OAuth 2.0 — Authorization Code Flow (~4p)
- 7.4 RBAC — admin/user/readonly (~3p)
- 7.5 Rate Limit — 키별/사용자별/모델별 (~3p)
- 7.6 Cloudflare Tunnel — Zero Trust 적용 가능성 (~3p)
- 7.7 감사 로그 — 누가 무엇을 언제 (~2p)
- **다이어그램:** diagram-13 (API key 검증), diagram-14 (OAuth 플로우), diagram-16 (RBAC 권한 매트릭스)
- **실습 박스:** API key 발급 후 회수까지의 admin 콘솔 시나리오

---

## Part III — 구현 (Implementation) — 약 150p / 5 Chapters

### Chapter 8. 모델 서빙 — vLLM 0.17.1 (~35p)
**학습 목표 박스:**
- vLLM 0.17.1로 Dense/MoE 두 모델을 한 노드에 동시 띄우는 방법 학습
- 메모리 분할(GPU 0~3 Dense, GPU 4~7 MoE) 정책 결정

- 8.1 vLLM 0.17.1 변경점 요약 (~3p)
- 8.2 Engine 옵션 — `--tensor-parallel-size`, `--gpu-memory-utilization` (~5p)
- 8.3 Dense 모델 launch (~4p)
- 8.4 MoE 모델 launch — `--enable-expert-parallel` 등 (~5p)
- 8.5 두 모델의 GPU 분할 전략 (~5p)
- 8.6 KV 캐시 튜닝 — block_size, swap (~4p)
- 8.7 배치/스케줄링 — continuous batching (~4p)
- 8.8 로그/메트릭 노출 — Prometheus exporter (~3p)
- 8.9 헬스체크 엔드포인트 (~2p)
- **다이어그램:** diagram-17 (8 GPU 분할), diagram-18 (Dense launch 흐름), diagram-19 (MoE launch 흐름), diagram-20 (KV 캐시 구조)
- **코드 예제:** `예제 8.1 - dense_launch.sh`, `예제 8.2 - moe_launch.sh`, `예제 8.3 - vLLM 헬스체크 클라이언트`
- **실습 박스:** 8 GPU 중 4개로 Dense를 띄우고 nvidia-smi 확인

### Chapter 9. FastAPI Gateway — OpenAI 호환 API (~35p)
**학습 목표 박스:**
- `/v1/chat/completions`, `/v1/completions`, `/v1/models`, `/v1/embeddings` 구현 이해
- 두 vLLM 인스턴스를 모델 이름으로 분기하는 라우팅 학습

- 9.1 OpenAI Spec 매핑 — 어디까지 호환할 것인가 (~4p)
- 9.2 라우팅 — model name → upstream URL (~4p)
- 9.3 스트리밍 — SSE 구현 (~5p)
- 9.4 인증 미들웨어 — Bearer 토큰 파싱 (~4p)
- 9.5 사용량 기록 — UsageLog write 비동기화 (~4p)
- 9.6 에러 매핑 — vLLM → OpenAI error format (~4p)
- 9.7 백프레셔/세마포어 — 50동접 보장 (~4p)
- 9.8 의존성 주입 — FastAPI Depends 패턴 (~3p)
- 9.9 통합 테스트 (~3p)
- **다이어그램:** diagram-09 (Gateway 내부 구조), diagram-10 (스트리밍 시퀀스)
- **코드 예제:** `예제 9.1 - chat_completions handler`, `예제 9.2 - SSE 스트리밍 코드`, `예제 9.3 - 에러 매퍼`

### Chapter 10. CLI — Claude Code 스타일 (~30p)
**학습 목표 박스:**
- 터미널에서 LLM과 상호작용하는 CLI의 UX 설계 학습
- read/write/edit/bash/grep 도구를 직접 구현할 수 있게 됨

- 10.1 CLI 아키텍처 — REPL, command parser, tool runner (~4p)
- 10.2 인증 저장 — `~/.gem-llm/credentials` (~3p)
- 10.3 슬래시 명령어 — `/help`, `/model`, `/clear`, `/login` (~4p)
- 10.4 도구: read — 파일 읽기 (~3p)
- 10.5 도구: write/edit — 파일 수정 안전성 (~4p)
- 10.6 도구: bash — 샌드박스/타임아웃 (~4p)
- 10.7 도구: grep — ripgrep 래핑 (~3p)
- 10.8 스트리밍 렌더링 — markdown live render (~3p)
- 10.9 컨텍스트 관리 — 자동 트리밍/요약 (~2p)
- **다이어그램:** diagram-29 (CLI 시작 흐름), diagram-30 (도구 호출 시퀀스), diagram-31 (슬래시 명령어 처리), diagram-32 (스트리밍 렌더 루프)
- **코드 예제:** `예제 10.1 - REPL main loop`, `예제 10.2 - tool registry`
- **실습 박스:** `gemcli` 로컬 설치 후 첫 대화

### Chapter 11. Admin Web UI (~25p)
**학습 목표 박스:**
- 관리자 콘솔의 핵심 화면 5개 구조 학습
- 사용자/키/사용량/모델 상태/감사 로그 탐색 UI 설계

- 11.1 기술 스택 — React + Vite, TanStack Query (~3p)
- 11.2 화면 1: 대시보드 — 활성 사용자, 모델 상태 (~3p)
- 11.3 화면 2: 사용자 관리 (~4p)
- 11.4 화면 3: API key 발급/회수 (~4p)
- 11.5 화면 4: 사용량 분석 (~4p)
- 11.6 화면 5: 모델 컨트롤 (재시작/스왑) (~4p)
- 11.7 권한 게이트 — admin only (~3p)
- **다이어그램:** diagram-33~35 (Admin UI 화면 와이어프레임 3종)
- **코드 예제:** `예제 11.1 - useAuth 훅`

### Chapter 12. Phase 2 — Google OAuth 통합 (~25p)
**학습 목표 박스:**
- API key 단독 → API key + OAuth 병행으로 이행하는 단계 이해
- 세션과 키의 공존 모델 학습

- 12.1 Phase 1 vs Phase 2 차이 (~3p)
- 12.2 Google Cloud Console 설정 — OAuth client (~3p)
- 12.3 Authorization Code Flow 구현 (~5p)
- 12.4 ID token 검증 — JWKS, aud, iss (~4p)
- 12.5 세션 쿠키 vs JWT (~3p)
- 12.6 API key와 OAuth 사용자 매핑 (~4p)
- 12.7 로그아웃과 세션 회수 (~3p)
- **다이어그램:** diagram-14 (OAuth 플로우), diagram-15 (세션 + API key 통합)
- **코드 예제:** `예제 12.1 - oauth callback handler`

---

## Part IV — 운영 (Operations) — 약 70p / 3 Chapters

### Chapter 13. 배포 — Cloudflare Tunnel & K8s (~25p)
**학습 목표 박스:**
- 사내망 K8s Pod에서 외부로 안전하게 노출하는 Tunnel 설정 학습
- 무중단 배포 전략 (롤링/블루그린 한계) 이해

- 13.1 배포 아키텍처 — Pod 1개에 모든 컴포넌트 (~3p)
- 13.2 Cloudflare Tunnel 셋업 — `cloudflared` (~4p)
- 13.3 `llm.pamout.com` DNS/인증서 (~3p)
- 13.4 환경 변수/Secret 관리 (~4p)
- 13.5 모델 가중치 다운로드 자동화 (~3p)
- 13.6 헬스 프로브 (liveness/readiness) (~3p)
- 13.7 무중단 모델 재시작 — 트릭 (~3p)
- 13.8 백업 — DB 덤프, 설정 (~2p)
- **다이어그램:** diagram-25 (배포 토폴로지), diagram-26 (Tunnel 흐름), diagram-27 (Secret 관리), diagram-28 (모델 재시작 절차)
- **코드 예제:** `예제 13.1 - cloudflared config.yml`, `예제 13.2 - K8s Pod manifest`

### Chapter 14. 모니터링 & 관측 가능성 (~25p)
**학습 목표 박스:**
- Prometheus + Grafana로 vLLM/Gateway/시스템 메트릭을 수집·시각화
- 알람 임계치 설계

- 14.1 시그널 3종 — 메트릭/로그/트레이스 (~3p)
- 14.2 vLLM 메트릭 — TTFT, TPOT, queue length (~4p)
- 14.3 Gateway 메트릭 — RPS, p50/p95/p99 (~4p)
- 14.4 GPU 메트릭 — DCGM exporter (~3p)
- 14.5 로그 — JSON 구조화, request_id 트레이싱 (~4p)
- 14.6 대시보드 — 7개 패널 구성 (~4p)
- 14.7 알람 — Slack 웹훅 (~3p)
- **다이어그램:** diagram-36 (모니터링 토폴로지), diagram-37 (대시보드 와이어), diagram-38 (알람 흐름)
- **코드 예제:** `예제 14.1 - prometheus.yml scrape config`

### Chapter 15. Skills, MCP, Hooks (~20p)
**학습 목표 박스:**
- Claude Code의 Skills/MCP/Hooks 개념을 GEM-LLM CLI에 이식하는 방법
- 사용자 정의 자동화 훅 설계

- 15.1 Skills — 재사용 가능한 도메인 액션 (~4p)
- 15.2 MCP (Model Context Protocol) 개요 (~4p)
- 15.3 Hooks — pre-prompt/post-tool 훅 (~4p)
- 15.4 사례: 사내 Confluence MCP (~3p)
- 15.5 사례: PR 자동 리뷰 hook (~3p)
- 15.6 보안 고려사항 (~2p)
- **다이어그램:** diagram-39 (Skills/MCP/Hooks 데이터 흐름)
- **코드 예제:** `예제 15.1 - hook 정의 JSON`

---

## Part V — 사례 & 튜닝 (Case Studies) — 약 50p / 3 Chapters

### Chapter 16. 실전 에러 사례 정리 (~20p)
**학습 목표 박스:**
- 운영 중 마주친 8대 에러와 해결 패턴 학습

- 16.1 GPU OOM — KV 캐시 폭주 (~3p)
- 16.2 vLLM 모델 로딩 실패 — 메모리 부족 (~3p)
- 16.3 Cloudflare Tunnel 끊김 (~2p)
- 16.4 50동접 초과시 큐잉 폭발 (~3p)
- 16.5 GPFS I/O 병목으로 워밍업 지연 (~2p)
- 16.6 토크나이저 mismatch (~2p)
- 16.7 OAuth 토큰 만료 처리 누락 (~2p)
- 16.8 모델 핫스왑 중 in-flight 요청 손실 (~3p)
- **다이어그램:** diagram-40 (장애 흐름 트리)

### Chapter 17. 성능 튜닝 (~15p)
**학습 목표 박스:**
- 처리량(RPS)과 레이턴시(p95)의 트레이드오프 측정·튜닝

- 17.1 벤치마크 도구 — locust, vegeta (~2p)
- 17.2 KV 캐시 크기 최적화 (~3p)
- 17.3 max_num_seqs / max_num_batched_tokens (~3p)
- 17.4 SSE 스트리밍 vs non-stream 비교 (~2p)
- 17.5 Gateway 비동기 워커 수 (~2p)
- 17.6 결과 — 50동접 시 p95 < 2s 달성 사례 (~3p)
- **다이어그램:** diagram-37 (성능 결과 차트)

### Chapter 18. 확장 시나리오 (~15p)
**학습 목표 박스:**
- 단일 노드의 한계를 넘어서는 다음 단계 설계

- 18.1 멀티 노드로의 확장 — RDMA 가능 환경 가정 (~3p)
- 18.2 추가 모델 패밀리 (Llama, Qwen) 통합 (~3p)
- 18.3 RAG 통합 — 벡터 DB (~3p)
- 18.4 Fine-tuning pipeline 연결 (~3p)
- 18.5 청구/과금 모듈 (~3p)

---

## 부록 (Appendices) — 약 50p

- A. 전체 API 레퍼런스 (~15p) — 모든 엔드포인트와 파라미터
- B. 설정 파라미터 사전 (~10p) — env var, config.yaml 키 전체
- C. 용어집 (~5p) — Dense/MoE/TTFT/TPOT/EP/TP 등
- D. 참고 문헌 (~3p) — 본 책에서 인용한 논문/문서
- E. 라이선스 — Qwen, vLLM, FastAPI 등 (~2p)
- F. FAQ (~5p) — 자주 묻는 질문 30개
- G. 변경 이력 (~2p) — 1.0 → 1.x
- H. 색인 (~8p)

---

## Part 별 페이지 합계

| Part | Chapter 수 | 페이지 |
|---|---|---|
| Part I — 기초 | 3 | 80 |
| Part II — 아키텍처 | 4 | 100 |
| Part III — 구현 | 5 | 150 |
| Part IV — 운영 | 3 | 70 |
| Part V — 사례 | 3 | 50 |
| 부록 | 8 | 50 |
| **총계** | **18 + 부록** | **500** |

---

## 본 책에서 사용하는 다이어그램 ID 목록
diagram-01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40
