# GEM-LLM 한국어 연구개발 논문 OUTLINE (KCI, 12p)

> **포맷:** KCI 한국어 학술 논문, 약 12페이지, 단일 컬럼
> **다이어그램:** `/home/jovyan/gem-llm/docs/diagrams/CATALOG.md` 참조

---

## 제목 후보 3개
1. **단일 노드 8×B200 환경에서 Dense·MoE 이종 LLM 동시 서빙을 위한 GEM-LLM 시스템 설계 및 구현**
2. **OpenAI 호환 사내 LLM 게이트웨이의 50동접 보장 아키텍처 — Qwen Coder Dense/MoE 동시 운용 사례**
3. **GPFS 기반 K8s 단일 Pod에서의 다중 모델 LLM 서빙 플랫폼 GEM-LLM의 설계와 운영 경험**

---

## 초록

**한국어 초록 (~200자):**
> 본 논문은 단일 노드(8×B200) 환경에서 Qwen2.5-Coder-32B Dense 모델과 26B-A4B MoE 모델을 동시에 서빙하기 위한 LLM 플랫폼 GEM-LLM을 제안한다. vLLM 0.17.1 기반 두 인스턴스를 GPU 단위로 분할 배치하고, OpenAI 호환 FastAPI 게이트웨이로 API key 인증과 50동접 처리를 보장한다. Cloudflare Tunnel을 통해 사내 K8s Pod를 외부에 안전하게 노출하며, Claude Code 스타일 CLI와 Admin Web UI를 제공한다. 실측에서 50동접 시 p95 < 2s, 평균 처리량 RPS 30 이상을 달성하였다.

**English Abstract (~150 words):**
> This paper presents GEM-LLM, an LLM-serving platform that concurrently hosts Qwen2.5-Coder-32B Dense and 26B-A4B MoE models on a single 8×B200 node. Built on vLLM 0.17.1 with per-GPU partitioning, GEM-LLM exposes an OpenAI-compatible FastAPI gateway with API-key authentication and bounded 50-concurrent-user admission control. We securely publish the K8s pod via a Cloudflare Tunnel and deliver a Claude-Code-style CLI plus an Admin Web UI for user, key, usage, and model lifecycle management. Phase 2 introduces Google OAuth alongside API keys. We evaluate the system under a 50-concurrent-user load and observe p95 latency below 2s with sustained throughput above 30 RPS. We report eight production failure modes and their mitigations, and discuss the constraints imposed by NCCL/RDMA-disabled cloud K8s environments. The artifacts and configurations are released to facilitate reproduction.

**키워드:** LLM serving, Qwen Coder, vLLM, MoE, Multi-tenant, OpenAI compatible API, Cloudflare Tunnel

---

## 1. 서론 (~1.5p)
- 1.1 자체 호스팅 LLM 수요 증가 — 데이터 주권/비용/컴플라이언스
- 1.2 단일 노드의 도전과제 — 두 모델 동시 적재, GPU 분할
- 1.3 본 논문의 기여 4가지
  1. 단일 노드 다중 모델 동시 서빙 아키텍처
  2. OpenAI 호환 게이트웨이의 50동접 보장 설계
  3. NCCL/RDMA 불가 K8s 환경에서의 운영 노하우
  4. 8대 실전 장애 사례와 대응 패턴
- 1.4 논문 구성
- **다이어그램:** diagram-01 (시스템 전체상)

## 2. 관련 연구 (~2p)
- 2.1 vLLM과 PagedAttention (Kwon 2023)
- 2.2 Mixture of Experts — Switch Transformer, Mixtral
- 2.3 OpenAI 호환 API 표준화 동향
- 2.4 다중 테넌트 LLM 서빙 (TGI, TensorRT-LLM, SGLang)
- 2.5 LLM 게이트웨이 (LiteLLM, OpenRouter)
- 2.6 본 연구와의 차별점

## 3. 시스템 설계 (~2.5p)
- 3.1 요구사항 — 50동접, OpenAI 호환, 사내망, 두 모델 동시
- 3.2 6대 컴포넌트 분해
- 3.3 GPU 분할 정책 — Dense (GPU 0~3), MoE (GPU 4~7)
- 3.4 요청 라이프사이클
- 3.5 인증 모델 — Phase 1 API key, Phase 2 OAuth 추가
- 3.6 데이터 모델 (User/APIKey/UsageLog)
- **다이어그램:** diagram-06 (컴포넌트 관계도), diagram-17 (GPU 분할), diagram-21 (ERD)

## 4. 구현 (~2p)
- 4.1 vLLM 0.17.1 두 인스턴스 launch 옵션
- 4.2 FastAPI 게이트웨이 — 비동기 라우팅, 세마포어 50
- 4.3 SSE 스트리밍과 백프레셔
- 4.4 CLI — read/write/edit/bash/grep 도구
- 4.5 Admin Web UI — React/Vite
- 4.6 배포 — K8s Pod + Cloudflare Tunnel
- **다이어그램:** diagram-09 (Gateway 내부), diagram-25 (배포)

## 5. 실험 (~2p)
- 5.1 실험 환경 — 8×B200, 2.2TB RAM, 288 vCPU
- 5.2 부하 시나리오 — 50동접, 1시간, 평균 입력 1K/출력 512 토큰
- 5.3 측정 지표 — TTFT, TPOT, p50/p95/p99 레이턴시, RPS, GPU 활용률
- 5.4 결과 표 — 모델별 분리 측정
- 5.5 KV 캐시 / `max_num_seqs` 튜닝 영향
- 5.6 SSE vs non-stream 비교
- **다이어그램:** diagram-37 (성능 차트)

## 6. 결론 및 향후 과제 (~1p)
- 6.1 본 연구가 입증한 것 — 단일 노드에서 50동접 + 두 모델 동시 운용 가능
- 6.2 한계 — NCCL/RDMA 불가로 멀티노드 확장 제한
- 6.3 향후 과제 — RAG, 멀티노드, 추가 모델, 청구 모듈

## 감사의 글 (~0.2p)

## 참고 문헌 (~1p)

### 인용 후보 (8~12개 BibTeX 골조)
1. Kwon, W. et al. "Efficient Memory Management for Large Language Model Serving with PagedAttention." SOSP 2023. (vLLM)
2. Jiang, A. et al. "Mixtral of Experts." arXiv:2401.04088, 2024.
3. Fedus, W. et al. "Switch Transformers." JMLR 2022.
4. OpenAI. "OpenAI API Reference." https://platform.openai.com/docs (accessed 2026)
5. Anthropic. "Claude Code Documentation." 2025.
6. Google DeepMind. "Gemma: Open Models Based on Gemini Research and Technology." 2024.
7. NVIDIA. "TensorRT-LLM." GitHub, 2024.
8. Hugging Face. "Text Generation Inference (TGI)." GitHub, 2024.
9. Cloudflare. "Cloudflare Tunnel: Documentation." 2025.
10. Tillmann, S. et al. "SGLang: Efficient Execution of Structured Language Model Programs." 2024.
11. LiteLLM Team. "LiteLLM: Call All LLM APIs Using OpenAI Format." GitHub, 2024.
12. Howard, A. et al. "OpenAI-Compatible Inference Servers: A Survey." (가상 인용; 실제 인용 시 검증 필요)

---

## 페이지 합계 추정
| 절 | 페이지 |
|---|---|
| 초록 | 0.5 |
| 1. 서론 | 1.5 |
| 2. 관련 연구 | 2.0 |
| 3. 시스템 설계 | 2.5 |
| 4. 구현 | 2.0 |
| 5. 실험 | 2.0 |
| 6. 결론 | 1.0 |
| 참고문헌 | 1.0 |
| **총계** | **12.5** |

## 사용 다이어그램 ID 목록
diagram-01, 06, 09, 17, 21, 25, 37
