---
name: bilingual-book-authoring
description: '한/영 동시 책 저작 (~1000p) 워크플로 — OUTLINE 동기화, Part별 멀티에이전트 디스패치, 다이어그램 ID 공유, 자연 영어 (직역 X), 에러 사례 수집. 사용 시점 — "한영 책 동시", "기술서적 저작", "병렬로 책 쓰기", "OUTLINE 미러", "다이어그램 카탈로그 공유", "자연스러운 영어 번역". GEM-LLM ~1000p 작성에서 검증된 6가지 패턴.'
---

# bilingual-book-authoring

한/영 두 권을 **동시에 써내려가는** 기술서적 저작 워크플로. `pandoc-bilingual-build`(빌드 인프라) + `multi-agent-orchestrator`(병렬 디스패치) 위에 얹는 *콘텐츠 저작 패턴*.

## 사용 시점 (트리거)

- "한/영 책 동시에 쓰자"
- "기술서적 한 번에 양쪽 언어로"
- "병렬로 책 본문 작성"
- "OUTLINE 한/영 mirror"
- "다이어그램 카탈로그 한/영 공유"
- "직역 말고 자연스러운 영어로 동시 작성"
- "에러 사례 챕터 (실제 운영 사례)"

빌드 도구만 필요하면 → `pandoc-bilingual-build`
병렬 디스패치 일반 패턴 → `multi-agent-orchestrator`
빈 프로젝트부터 → `project-bootstrap`

## 검증 사례 (~1000p)

GEM-LLM 프로젝트에서 한/영 한 쌍의 기술서적을 **약 7 라운드 멀티 에이전트**로 작성:

| 항목 | 한국어 (`book-ko/`) | 영문 (`book-en/`) |
|---|---|---|
| 페이지 수 | ~576p | ~576p |
| 챕터 수 | 24 (5 Part + 부록) | 24 (mirror) |
| 다이어그램 | 40 (공유) | 40 (공유) |
| 에러 사례 (Ch.16) | 13 케이스 | 13 케이스 mirror |
| LaTeX 템플릿 | `book-ko.tex` | `book-en.tex` |
| 폰트 | Noto Sans KR + DejaVu Sans Mono | Noto Sans + DejaVu Sans Mono |

7 라운드 동안 동시 디스패치 에이전트 수: 라운드당 4~6.

## 6가지 핵심 패턴

### 1. OUTLINE 동기화 (Mirror)

한국어 `OUTLINE.md`를 *먼저* 확정한 뒤 영문 `OUTLINE.md`를 **구조 mirror**.

- Part 수, Chapter 수, Section heading 수가 *완전 일치*
- 챕터 제목만 영문으로 (직역 아닌 자연 영어 — *"vLLM 부팅 함정" → "vLLM Boot-Time Pitfalls"*)
- 페이지 추정치 동일하게 적되 ±10% 오차 허용

```
docs/book-ko/OUTLINE.md ──(mirror)──▶ docs/book-en/OUTLINE.md
                                      (구조 동일, 제목 자연 영어)
```

❌ 영문에서 챕터 추가/삭제 → 다이어그램 번호 어긋남, 페이지 카운트 미스매치
✅ 구조 변경은 한국어 먼저 → 영문 mirror 라운드 재실행

### 2. 다이어그램 ID 공유

다이어그램은 **한 카탈로그**(`docs/diagrams/CATALOG.md`)에서 단일 source of truth.

```
docs/diagrams/
├── CATALOG.md           # diagram-01 … diagram-40 (한 곳)
├── mmd/diagram-NN.mmd   # Mermaid 소스 (1 copy)
└── svg/diagram-NN.svg   # 빌드 산출 (1 copy)
```

본문 참조는 한/영 동일 ID:

```markdown
<!-- book-ko/parts/part-2/ch-05.md -->
![diagram-12 vLLM 부팅 시퀀스](../../diagrams/svg/diagram-12.svg)

<!-- book-en/parts/part-2/ch-05.md -->
![diagram-12 vLLM Boot Sequence](../../diagrams/svg/diagram-12.svg)
```

캡션만 언어별로 다르고 **파일 경로/ID 동일**. SVG 빌드 1회로 양쪽 책이 같은 그림 사용 → 일관성 + 디스크 절약.

### 3. Part별 멀티 에이전트 디스패치

5 Part + 부록을 4 에이전트로 (Part IV+V+부록 묶음):

```
Agent KO-1: Part I (기초)
Agent KO-2: Part II (구현)
Agent KO-3: Part III (운영)
Agent KO-4: Part IV + V + 부록
```

영문도 동일 4분할 → 한 라운드에 한국어 4 + 영문 4 = **8 에이전트 동시** 가능 (rate limit 주의).

각 에이전트 prompt 시작에 *공유 컨텍스트* 명시:

```
**먼저 읽어야 할 파일:**
- docs/book-ko/OUTLINE.md (전체 목차)
- docs/diagrams/CATALOG.md (이 Part가 사용하는 diagram-NN)
- plan/SPEC-*.md (인터페이스 사실)

**이 Part가 사용하는 diagram ID:** diagram-08 ~ diagram-15
```

### 4. 자연 영어 (직역 금지)

영문 에이전트 prompt에 **명시적으로**:

> 한국어 챕터의 *content depth*는 동일하되 **직역하지 말고 자연스러운 영어로** 작성. 한국어 문장 구조 그대로 옮기지 말고, 영어 기술서적 관용 표현 사용. 저자가 한국인이라 영어가 어색해질 위험이 있으므로, 명시적으로 *native technical English* 스타일을 지시.

체크 항목:
- 문장 길이를 한국어보다 짧게 (영문 평균 15~20 단어)
- 수동태 남용 금지 (한국어식 "~되어진다" → 능동)
- "It is important that..." 같은 빈말 제거 → 직접 명령형
- 코드 주석/식별자는 처음부터 영어 → 양쪽 동일

❌ "The vLLM is being booted by the supervisor" (직역 냄새)
✅ "The supervisor boots vLLM" (자연)

### 5. 에러 사례 수집 (Chapter 16)

운영 책의 가치는 **실제 발생한 에러 사례**. 가상/일반론 X, 실제 stack trace + 해결 과정 O.

GEM-LLM 책의 Part V Chapter 16: **13 케이스 스터디**, 각 케이스 6단 구조:

| 단 | 내용 | 예시 |
|---|---|---|
| 영역 | 어느 컴포넌트 | vLLM / Gateway / CLI / 빌드 |
| 시점 | 언제 발생 | 부팅 / 첫 요청 / 24시간 후 |
| 증상 | 사용자가 본 것 | 500 에러 / OOM / 한글 깨짐 |
| 원인 | 진짜 원인 | torch 버전 / xeCJK 누락 |
| 해결 | 적용한 패치 | requirements.txt 핀 / apt install |
| 교훈 | 일반화 | 버전 매트릭스 / 의존성 문서화 |

도메인 분류로 묶기:
- **환경** (apt, CUDA, Python 버전)
- **설정** (yaml, env var, 포트)
- **코드** (race condition, off-by-one)
- **문서** (잘못된 명령 예시)
- **사용자 실수** (오해 가능한 인터페이스)

수집 방법: 프로젝트의 `_logs/`, git commit 메시지(`fix:`), Slack/이슈 트래커에서 *실제* 사례 추출. 케이스마다 stack trace 1~3줄 인용 (재현 가능성 보장).

### 6. PDF 빌드 일관성

한/영 책이 **시각적으로 한 시리즈**로 보이도록:

| 항목 | 한국어 | 영문 |
|---|---|---|
| `documentclass` | `book` | `book` |
| 본문 폰트 | Noto Sans KR | Noto Sans |
| 코드 폰트 | DejaVu Sans Mono | DejaVu Sans Mono |
| Geometry | a4paper, margin=2.5cm | a4paper, margin=2.5cm |
| Heading 스타일 | 동일 LaTeX 명령 | 동일 LaTeX 명령 |
| 페이지 번호 위치 | 동일 footer | 동일 footer |

`docs/build/templates/book-ko.tex` ↔ `book-en.tex`는 **xeCJK 블럭만 다르고 나머지 동일**. 헤딩 스타일/페이지 번호 위치를 한쪽에서만 바꾸면 시리즈 일관성 깨짐.

```latex
% book-ko.tex (xeCJK 추가)
\usepackage{xeCJK}
\setCJKmainfont{Noto Sans KR}
\XeTeXlinebreaklocale "ko"

% book-en.tex (xeCJK 없이)
\setmainfont{Noto Sans}
```

## 저작 라운드 흐름 (6 라운드)

표준 진행 순서. 각 라운드는 한 응답 + 동시 에이전트 완료 대기.

### 라운드 1 — OUTLINE 동기화
- 한국어 `OUTLINE.md` 작성 (Plan agent 또는 general-purpose)
- 영문 `OUTLINE.md` mirror (general-purpose)
- 산출물: 두 OUTLINE, 챕터 제목 확정

### 라운드 2 — 다이어그램 카탈로그 stub
- `docs/diagrams/CATALOG.md`에 ~40 다이어그램 frontmatter + 빈 mermaid 블럭
- ID 분배 표 작성 (Part I = 01~08, Part II = 09~17, …)
- `bash scripts/extract-mmd.sh` → `.mmd` 파일 생성
- 산출물: CATALOG + 40개 stub mermaid

### 라운드 3 — 한국어 본문 (Part 4분할)
- 4 에이전트 (Part I, II, III, IV+V+부록)
- 각 에이전트는 자기 Part의 다이어그램 ID만 사용
- 산출물: `book-ko/parts/part-N/ch-NN.md` 24 파일

### 라운드 4 — 영문 본문 (한국어 mirror)
- 4 에이전트, 한국어를 *읽고* 영문 작성
- "직역 금지" 명시
- 산출물: `book-en/parts/part-N/ch-NN.md` 24 파일

### 라운드 5 — 빌드 검증
- `make diagrams` (Mermaid → SVG 40개)
- `make book-ko book-en` (PDF + DOCX + TEX + MD 각 4 포맷)
- 한/영 PDF 페이지 수 비교 (±10% 이내 정상)
- 산출물: `docs/build/out/book-ko.pdf`, `book-en.pdf`

### 라운드 6 — 에러 사례 챕터 채우기
- 프로젝트 `_logs/`, git log, 이슈 트래커에서 실제 사례 수집
- Chapter 16 (또는 운영 Part 마지막 챕터) 6단 구조로 작성
- 한/영 동시 (사례 자체는 같음, 영어는 자연스럽게 재서술)

## 일반적 함정

| 함정 | 회피 |
|---|---|
| 한국어 일부만 변경 후 영문 동기화 누락 | OUTLINE 변경 시 *반드시* 두 책 같은 라운드에서 갱신 |
| 다이어그램 ID 한/영에서 다르게 사용 | CATALOG.md 단일 source — 본문에서 임의 ID 부여 금지 |
| 직역으로 어색한 영어 | 영문 에이전트 prompt에 "저자가 한국인이라 명시적으로 자연스러운 영어 지시" 박아넣기 |
| LaTeX 템플릿이 한/영 다르게 진화 | `diff book-ko.tex book-en.tex`에서 xeCJK + 폰트 외에 차이 0 유지 |
| 한국어 책에만 챕터 추가 → 페이지 번호 어긋남 | 구조 변경은 OUTLINE 라운드 재실행 (라운드 1로 복귀) |
| 에러 사례에 가상 사례 섞기 | git log/`_logs/` 출처 명기 — stack trace 인용 필수 |
| 코드 블럭 안 한글로 코드 주석 | 코드는 처음부터 영어 주석 (한/영 책 양쪽 동일 코드) |
| 영문 챕터를 한국어와 다른 순서로 작성 | Part 분할 동일 (Part I 작성 시 한/영 동시) |

## 에러 사례 챕터 작성 팁

1. **수집 우선** — 작성 전에 raw 사례 20+개 모으기 (`git log --grep=fix`, `_logs/error-*`)
2. **6단 통일** — 영역/시점/증상/원인/해결/교훈, 케이스마다 동일 순서
3. **도메인 분류** — 환경/설정/코드/문서/사용자 실수 5 도메인으로 그룹핑
4. **재현성** — 각 케이스에 *실제 명령 + 실제 출력* 1~3줄 인용
5. **일반화 명시** — "교훈" 단에 *다른 프로젝트에도 적용 가능한* 1문장 추출
6. **양쪽 동일 케이스** — 영문판도 같은 13 케이스, 단 영어 운영 환경 관점에서 자연스러운 표현

## 빌드 명령 (pandoc-bilingual-build와 연계)

```bash
# 한/영 동시 빌드
make book-ko book-en

# 모든 타겟 (book + manual + paper) × 4 포맷
make all

# 다이어그램만
make diagrams

# 빌드 산출물 → _trash (안전한 clean)
make clean
```

빌드 산출물:
```
docs/build/out/
├── book-ko.pdf      ~1.5M / ~576p
├── book-ko.docx
├── book-ko.tex
├── book-ko.md       (단일 합본)
├── book-en.pdf      ~1.4M / ~576p (영문은 약간 짧음)
├── book-en.docx
├── book-en.tex
└── book-en.md
```

빌드 실패 시 → `pandoc-bilingual-build` skill의 "흔한 에러" 표 참조.

## 디렉토리 구조

```
docs/
├── book-ko/
│   ├── OUTLINE.md            # 한국어 목차 (source)
│   └── parts/
│       ├── part-1/ch-01.md … ch-04.md
│       ├── part-2/ch-05.md … ch-09.md
│       ├── part-3/ch-10.md … ch-13.md
│       ├── part-4/ch-14.md … ch-17.md   # ch-16 = 에러 사례
│       ├── part-5/ch-18.md … ch-21.md
│       └── appendix/ch-22.md … ch-24.md
├── book-en/                  # mirror (구조 동일)
│   ├── OUTLINE.md            # 영문 목차 (한국어 mirror)
│   └── parts/                # ch-NN.md 파일명 동일
├── diagrams/                 # 한/영 공유
│   ├── CATALOG.md
│   ├── mmd/diagram-01.mmd … diagram-40.mmd
│   └── svg/diagram-01.svg … diagram-40.svg
└── build/
    ├── metadata-ko.yaml
    ├── metadata-en.yaml
    └── templates/
        ├── book-ko.tex       # xeCJK + Noto Sans KR
        └── book-en.tex       # Noto Sans (xeCJK 없음)
```

## 실용 체크리스트

새 라운드 디스패치 전:

- [ ] OUTLINE 한/영 구조 동일한가 (Part/Chapter 수, heading 수)
- [ ] 다이어그램 ID 분배표가 prompt에 있는가
- [ ] 영문 에이전트 prompt에 "직역 금지" 박아넣었나
- [ ] 코드 블럭 주석이 영어인가 (양쪽 동일 코드)
- [ ] LaTeX 템플릿 diff가 xeCJK + 폰트 블럭으로 한정되는가
- [ ] 에러 사례에 출처(git commit / log 파일) 명기됐나
- [ ] 한/영 PDF 페이지 수 ±10% 이내인가

## 관련 skill

- `pandoc-bilingual-build` — 빌드 인프라 (Makefile, LaTeX 템플릿, Mermaid)
- `multi-agent-orchestrator` — Part별 병렬 디스패치 일반 패턴
- `project-bootstrap` — 빈 프로젝트에서 책 골격 자동 생성 (이 skill의 상위)

## 참조

- Pandoc 매뉴얼: https://pandoc.org/MANUAL.html
- xeCJK: https://ctan.org/pkg/xecjk
- Mermaid CLI: https://github.com/mermaid-js/mermaid-cli
