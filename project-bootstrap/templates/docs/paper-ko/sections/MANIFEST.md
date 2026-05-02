# GEM-LLM 한국어 논문 (KCI) — MANIFEST

> 본 매니페스트는 `docs/paper-ko/sections/` 의 산출물 명세이다. Pandoc 빌드 시 본 순서대로 concatenate 한다.

## 채택 제목

**GEM-LLM: 단일 노드 8×B200에서 Dense·MoE 이종 LLM의 OpenAI 호환 동시 서빙 시스템 설계 및 운영 경험**

(OUTLINE 후보 1·2 결합)

## 파일 순서 (Pandoc concat 순)

| # | 파일 | 절 | 약 페이지 |
|---|------|----|-----------|
| 1 | `00-abstract.md` | 초록 (한·영) | 0.5 |
| 2 | `01-introduction.md` | 서론 | 1.5 |
| 3 | `02-related-work.md` | 관련 연구 | 1.5 |
| 4 | `03-system-design.md` | 시스템 설계 | 2.0 |
| 5 | `04-implementation.md` | 구현 | 2.0 |
| 6 | `05-evaluation.md` | 실험 | 2.0 |
| 7 | `06-conclusion.md` | 결론 + 향후 과제 + 감사의 글 | 1.0 |
| — | `references.bib` | BibTeX | (별도, ~1.0p 인쇄) |
| **합계** | | | **~11.5p** |

KCI 12 p 권장 분량을 충족한다.

## 사용한 다이어그램 ID

| 그림 | ID | 절 |
|-----|----|----|
| 그림 1 | `diagram-01` (시스템 전체상) | 1.5 |
| 그림 2 | `diagram-06` (컴포넌트 관계도 / GPU 할당 별칭) | 3.2 |
| 그림 3 | `diagram-17` (GPU 분할) | 3.3 |
| 그림 4 | `diagram-21` (ER 다이어그램) | 3.6 |
| 그림 5 | `diagram-09` (게이트웨이 내부) | 4.2 |
| 그림 6 | `diagram-25` (배포 토폴로지) | 4.6 |
| 그림 7 | `diagram-37` (성능 차트, 측정 예정) | 5.4 |

> 다이어그램 카탈로그: `/home/jovyan/gem-llm/docs/diagrams/CATALOG.md`

## 인용 후보

`references.bib` 의 14 개 엔트리 (cite key 기준).

| 키 | 종류 | 검증 상태 |
|----|------|-----------|
| `Kwon23` | inproceedings (SOSP) | verified |
| `Jiang24` | misc (arXiv) | verified |
| `Fedus22` | article (JMLR) | verified |
| `Shazeer17` | inproceedings (ICLR) | verified |
| `Llama3` | misc (arXiv) | verified |
| `GPT4` | misc (arXiv) | verified |
| `OpenAI24` | misc (URL) | placeholder |
| `Anthropic25` | misc (URL) | placeholder |
| `Gemma24` | techreport | verified |
| `HF-TGI24` | misc (URL) | placeholder |
| `NVIDIA24` | misc (URL) | placeholder |
| `Zheng24` | inproceedings (NeurIPS) | verified |
| `LiteLLM24` | misc (URL) | placeholder |
| `FastAPI` | misc (URL) | placeholder |
| `Cloudflare25` | misc (URL) | placeholder |

> placeholder 항목은 KCI 게재본 확정 전 실제 URL/접속일/저자 표기를 재검증해야 한다.

## "[측정 예정]" 자리표시자 위치

| 절 | 위치 |
|----|------|
| 5.4 | 표 1 모든 셀 |
| 5.4 | 그림 7 |
| 5.5 | 표 2 모든 셀 |
| 5.6 | SSE/비스트리밍 비교 수치 |
| 5.8 | "본 논문이 KCI 게재본으로 확정되기 전까지" 문장 |
| 6.2 | 한계 단락 |

## 빌드 메모

- 입력: 본 디렉토리의 7 개 `.md` (00–06).
- 참고문헌: `references.bib` (영문 IEEE 논문과 공유 가능).
- 권장 Pandoc 옵션: `--from markdown --to latex --citeproc --bibliography references.bib --csl=ieee.csl` 또는 KCI 한국어 CSL.
- 한글 폰트: `mainfont=Noto Serif KR`, 영문 fallback `IBM Plex Serif` 권장.
- 단일 컬럼, 12 pt, 1.5 행간, A4.
