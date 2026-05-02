# GEM-LLM 한국어 매뉴얼 OUTLINE

> **구성:** 3개 매뉴얼 — User Guide / Admin Guide / Troubleshooting
> **대상:** 일반 사용자, 사내 관리자, 운영팀
> **다이어그램:** `/home/jovyan/gem-llm/docs/diagrams/CATALOG.md`

---

# Part 1. User Guide (사용자 가이드)

## 1. 시작하기 (~10p)
**학습 목표 박스:**
- GEM-LLM에 처음 로그인하고 첫 요청을 보낼 수 있게 됨

- 1.1 GEM-LLM이란 — 한 줄 설명
- 1.2 지원 모델 (Qwen2.5-Coder-32B Dense / 26B-A4B MoE)
- 1.3 접속 주소 — `https://llm.pamout.com`
- 1.4 사전 준비 — 사내 계정, 단말 환경
- 1.5 5분 안에 첫 요청 보내기 (curl 예시)
- **다이어그램:** diagram-02 (사용자 여정)
- **실습 박스:** curl로 hello world

## 2. 설치 (~10p)
- 2.1 CLI 설치 — `pip install gem-llm-cli` (가칭)
- 2.2 시스템 요구사항
- 2.3 macOS / Linux / Windows(WSL) 설치
- 2.4 설치 확인 — `gemcli --version`
- 2.5 자동 업데이트 옵션
- **코드 예제:** `예제 2.1 - 설치 스크립트`

## 3. 로그인과 인증 (API key) (~8p)
- 3.1 API key 발급 받기 (관리자 요청 절차)
- 3.2 `gemcli login` 명령어
- 3.3 자격증명 저장 위치 — `~/.gem-llm/credentials`
- 3.4 환경변수로 사용 — `GEM_LLM_API_KEY`
- 3.5 키 회전과 만료
- **다이어그램:** diagram-13 (API key 검증 흐름)

## 4. CLI 기본 사용 (~12p)
- 4.1 대화 시작 — `gemcli chat`
- 4.2 모델 선택 — `--model qwen2.5-coder-32b-dense` / `qwen3-coder-30b-moe`
- 4.3 시스템 프롬프트 지정
- 4.4 스트리밍 출력 보기
- 4.5 대화 저장/불러오기
- 4.6 멀티라인 입력
- **다이어그램:** diagram-29 (CLI 시작 흐름)

## 5. 도구 사용 — read/write/edit/bash/grep (~15p)
- 5.1 read — 파일 읽기 예시
- 5.2 write — 새 파일 생성 예시
- 5.3 edit — 기존 파일 일부만 수정
- 5.4 bash — 명령 실행과 안전 정책
- 5.5 grep — 코드베이스 검색
- 5.6 도구 자동 호출 vs 수동 호출
- **코드 예제:** `예제 5.1 - read/write 워크플로`
- **다이어그램:** diagram-30 (도구 호출 시퀀스)

## 6. 슬래시 명령어 (~8p)
- 6.1 `/help`
- 6.2 `/model` — 모델 전환
- 6.3 `/clear` — 컨텍스트 초기화
- 6.4 `/login` / `/logout`
- 6.5 `/usage` — 내 사용량 조회
- 6.6 `/save`, `/load`
- 6.7 `/exit`
- **다이어그램:** diagram-31

## 7. OpenAI 호환 SDK로 사용 (~8p)
- 7.1 Python SDK 사용 (`openai` 라이브러리)
- 7.2 base_url 변경 — `https://llm.pamout.com/v1`
- 7.3 chat.completions / embeddings
- 7.4 LangChain 연동
- 7.5 Node.js SDK 예시
- **코드 예제:** `예제 7.1 - openai-py 호출`

## 8. 사용 한도와 매너 (~5p)
- 8.1 동시 50명 제한
- 8.2 토큰 한도 / 분당 호출 수
- 8.3 민감정보 입력 금지 가이드
- 8.4 응답 품질이 낮을 때

---

# Part 2. Admin Guide (관리자 가이드)

## 9. Admin Web UI 개요 (~6p)
- 9.1 접속 — `/admin`
- 9.2 5개 화면 구성
- 9.3 권한 모델 (admin / user / readonly)
- **다이어그램:** diagram-33 (대시보드 화면)

## 10. 사용자 관리 (~8p)
- 10.1 사용자 추가 — 이메일 + 역할
- 10.2 사용자 비활성화/삭제
- 10.3 역할 변경
- 10.4 OAuth 사용자 자동 등록 정책 (Phase 2)
- **다이어그램:** diagram-34

## 11. API key 발급/회수 (~10p)
- 11.1 신규 키 발급 — TTL, scope, rate limit
- 11.2 키 목록 조회
- 11.3 즉시 회수
- 11.4 자동 회전
- 11.5 키 누출 의심 시 절차
- **다이어그램:** diagram-13
- **실습 박스:** 키 발급 → 사용 → 회수 시나리오

## 12. 사용량 모니터링 (~10p)
- 12.1 일/주/월 토큰 사용량
- 12.2 모델별/사용자별 분해
- 12.3 비정상 패턴 탐지
- 12.4 CSV 내보내기
- 12.5 Grafana 대시보드 링크
- **다이어그램:** diagram-37

## 13. 모델 컨트롤 (~10p)
- 13.1 두 모델의 현재 상태 확인
- 13.2 모델 재시작 — 안전 절차
- 13.3 모델 가중치 핫스왑
- 13.4 GPU 메모리 한계 시 처리
- **다이어그램:** diagram-28
- **코드 예제:** `예제 13.1 - 모델 재시작 스크립트`

## 14. 백업과 복구 (~8p)
- 14.1 DB 덤프 (PostgreSQL pg_dump)
- 14.2 설정 파일 백업
- 14.3 로그 보관 정책
- 14.4 복구 리허설
- **코드 예제:** `예제 14.1 - 백업 cron`

## 15. 보안 점검 체크리스트 (~6p)
- 15.1 API key 해싱 확인
- 15.2 Cloudflare Tunnel 상태
- 15.3 OAuth client secret 회전
- 15.4 감사 로그 확인 주기
- 15.5 사고 대응 플레이북

---

# Part 3. Troubleshooting (문제 해결)

각 항목 형식: **[증상] / [에러 메시지 원문] / [원인] / [해결] / [예방]**

## 16. 인증 관련 (~10p)
- 16.1 `401 Unauthorized: Invalid API key` — 키 오타/만료
- 16.2 `403 Forbidden: Insufficient scope` — scope 부족
- 16.3 OAuth 콜백 redirect 불일치 — `redirect_uri_mismatch`
- 16.4 ID token 검증 실패 — `aud` 불일치
- 16.5 세션 만료 처리 누락
- **다이어그램:** diagram-13, diagram-14

## 17. 모델 로딩 실패 (~10p)
- 17.1 `CUDA out of memory: tried to allocate ...` — GPU 메모리 부족
- 17.2 `RuntimeError: model weights not found` — GPFS 경로 문제
- 17.3 `ImportError: vllm.engine.llm_engine` — 버전 불일치
- 17.4 토크나이저 mismatch — `tokenizer.json` 누락
- 17.5 Hugging Face 다운로드 실패
- **다이어그램:** diagram-19

## 18. GPU OOM (~8p)
- 18.1 KV 캐시 폭주 패턴
- 18.2 `gpu-memory-utilization` 조정
- 18.3 `max_model_len` 축소
- 18.4 동시 요청 수 제한

## 19. 토큰 한도 / Rate Limit (~6p)
- 19.1 `429 Too Many Requests` — 분당 한도 초과
- 19.2 `400 BadRequest: token limit exceeded` — context window 초과
- 19.3 자동 retry 정책 권장값

## 20. 네트워크/Tunnel (~8p)
- 20.1 `cloudflared connection lost` — Tunnel 재시작
- 20.2 DNS 전파 지연
- 20.3 `502 Bad Gateway` — 업스트림 vLLM 다운
- 20.4 SSE 스트림 끊김 (proxy buffer 문제)
- **다이어그램:** diagram-26, diagram-40

## 21. 성능 저하 (~8p)
- 21.1 TTFT 급증 — 큐 적체
- 21.2 TPOT 급증 — 다른 모델과 GPU 경합
- 21.3 GPFS I/O 지연으로 워밍업 지연
- 21.4 로그 폭증으로 디스크 가득

## 22. 데이터/DB (~6p)
- 22.1 Alembic 마이그레이션 충돌
- 22.2 UsageLog 테이블 비대 — 파티션
- 22.3 PostgreSQL connection pool 고갈

## 23. CLI 클라이언트 (~6p)
- 23.1 `~/.gem-llm/credentials` 권한 오류
- 23.2 프록시 환경 (`HTTPS_PROXY`)
- 23.3 색상/유니코드 깨짐 (Windows)
- 23.4 도구 실행 권한 부족

## 24. 자주 묻는 질문 (~5p)
- 24.1 두 모델 중 무엇을 쓸지
- 24.2 한국어 품질 차이
- 24.3 사용 로그가 어디에 남는지
- 24.4 외부 인터넷 차단 환경에서 사용 가능한가
- 24.5 fine-tuning이 지원되는가

---

## 매뉴얼에서 사용하는 다이어그램 ID 목록
diagram-02, 13, 14, 19, 26, 28, 29, 30, 31, 33, 34, 37, 40
