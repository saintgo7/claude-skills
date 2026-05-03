---
name: book-builder
description: |
  프로젝트 설계/기술 문서를 **단행본(Markdown + DOCX + PDF × 한/영)** 으로 변환하는 스킬.

  **ACTIVATION**: 사용자가 다음 중 하나를 요청할 때 활성화.
  - "책 만들어줘", "책으로 만들어", "책 생성", "docs → 책", "책 스킬"
  - "make book", "generate book", "compile book", "docs to book"
  - 여러 출력 포맷(docx, pdf) + 다국어(한/영) 언급
  - "17장 구성", "단행본", "기술서적 제작"

  **NOT FOR**: 단순 문서 편집, 블로그 포스트, 이메일 템플릿, 랜딩페이지. 단일 파일 PDF 변환만 필요하면 `pandoc` 직접 사용.

  **PROVIDES**:
  - 표준 디렉토리 구조: `docs/book/{ko,en,assets}/` + `generate.sh`
  - pandoc + xelatex 기반 MD → DOCX/PDF 파이프라인
  - 한/영 이중 언어 템플릿 + 장별 synthesize 패턴
  - macOS 한글 폰트 (Apple SD Gothic Neo) 기본, Linux Noto CJK 폴백
  - 품질 게이트: 커버페이지 + TOC + 번호 섹션 + 페이지 분리

  **REQUIRES**: `pandoc` 3.x+, `xelatex` (MacTeX on macOS), 한글 폰트.

  **USE CASES**:
  - 프로젝트 설계 문서 10~20개 → 17장 단행본
  - API 레퍼런스 북
  - 유저 매뉴얼 출판
  - 기술 서적 초안 (다국어 동시 출판)
---

# Book Builder

> 여러 Markdown 설계 문서를 **한 권의 책**으로 synthesize하여 MD/DOCX/PDF × 한/영 총 6개 파일을 생성.

---

## 1. 활성화 감지

이 스킬은 다음 키워드에 반응:

| 한국어 | 영어 |
|-------|------|
| 책 만들어, 책 만들자, 책 생성 | make book, generate book, compile book |
| 단행본, 기술서적 | book from docs, docs to book |
| docx pdf 만들어, 한영 출간 | bilingual book, print-ready book |

**사전 확인**:
```bash
# 필수 도구
which pandoc         # 3.x+
which xelatex        # MacTeX (PDF 엔진)
fc-list :lang=ko | head   # 한글 폰트 존재 확인
```

없는 도구가 있으면 안내:
- macOS: `brew install pandoc mactex-no-gui`
- Linux: `apt install pandoc texlive-xetex texlive-fonts-recommended fonts-noto-cjk`

---

## 2. 작업 절차 (Opus-level design)

### 2.1 입력 정찰

사용자의 `docs/` 또는 지정 디렉토리의 Markdown 파일 목록 파악:

```bash
ls <source-dir>/*.md
wc -l <source-dir>/*.md
```

각 파일을 간단히 읽어 장 구성 결정.

### 2.2 17장 표준 구성 (기술 프로젝트)

[`TEMPLATES.md`](TEMPLATES.md)에 상세. 기본 골격:

```
1. 서문 (Preface)
2. 프로젝트 개요
3. 범위와 기능
4. 시스템 아키텍처
5. 데이터 모델
6. API 설계
7. UI 설계
8. 핵심 도메인 모듈 (프로젝트별)
9. 인증/권한
10. 배포/인프라
11. (프로젝트 특화 1)
12. 코드 아키텍처
13. 인프라 패턴
14. 데이터 운영
15. 개발 워크플로우
16. 테스트/스프린트
17. 부록 (환경변수/명령어/약어)
```

프로젝트 성격에 따라 8·11·12번을 교체하거나 장 수 조정.

### 2.3 디렉토리 셋업

```bash
mkdir -p <project>/docs/book/{ko,en,assets/css}
```

생성 파일:
- `README.md` — 책 개요 + 재생성 가이드
- `generate.sh` — pandoc 실행 스크립트 (템플릿 [`PANDOC.md`](PANDOC.md) §5)
- `.gitignore` — pandoc 중간 HTML 무시
- `assets/css/book.css` — PDF 스타일 (weasyprint 사용 시)

### 2.4 한국어 마스터 작성 (synthesize, NOT copy)

[`PATTERNS.md`](PATTERNS.md) 참조. 핵심:

- **synthesize = 재구성**: 원문 "01-overview.md"의 내용을 그대로 복사하지 않고, 단행본 맥락에 맞게 재서술
- 각 장 말미에 `docs/NN-xxx.md §M.P 참조` 로 원문 링크
- 교차 참조는 `§N.M` 형식으로 같은 책 내부 섹션 가리킴
- 코드 블록은 `typescript`, `bash`, `sql` 등 언어 태그 명시

YAML frontmatter + 커버 페이지:

```markdown
---
title: <제목>
subtitle: <부제>
author: <저자>
date: 2026-XX-XX
lang: ko
---

<div class="cover">

# <제목>

<div class="subtitle">...</div>
<div class="version">버전 X.Y · YYYY년 MM월</div>

</div>

# 서문
...
```

### 2.5 영문 마스터 작성 (번역)

원칙:
- 기술 용어는 영어 원형 유지 (e.g., "audit note", "signature", "reconciliation")
- 한국 고유 개념은 괄호 병기 (e.g., "삼성표준인증원 (Samsung Standard Registrar)")
- 장 번호/섹션 번호는 한국어와 정확히 일치 (교차참조 안전)
- 코드/다이어그램은 동일 유지

### 2.6 변환 실행

```bash
cd <project>/docs/book
./generate.sh           # 전체
./generate.sh ko docx   # 한국어 docx만
./generate.sh en pdf    # 영문 pdf만
```

### 2.7 검증

- 각 파일 크기 확인 (MD ≈ 2-5K lines, PDF ≈ 150-300KB)
- PDF 첫 페이지 열어 한글 폰트 정상 확인
- TOC 생성 여부
- 페이지 번호 표시

---

## 3. 참조 파일

| 파일 | 내용 |
|-----|-----|
| [`TEMPLATES.md`](TEMPLATES.md) | 프로젝트 유형별 장 구성 템플릿 (기술/매뉴얼/레퍼런스) |
| [`PANDOC.md`](PANDOC.md) | pandoc 명령 + `generate.sh` 템플릿 + 엔진별 옵션 |
| [`PATTERNS.md`](PATTERNS.md) | Synthesize 원칙, 커버/TOC/부록 형식, YAML frontmatter |
| [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) | 폰트 누락, 변환 실패, 인코딩 이슈 |

---

## 4. 생성 성공 기준

- [ ] 한/영 MD 파일 각각 2,000+ lines
- [ ] 17장 구조 일관 (장 번호 한·영 일치)
- [ ] DOCX 변환 성공 (TOC 포함, 번호 섹션)
- [ ] PDF 변환 성공 (한글 깨짐 0건, 첫 페이지 커버, 페이지 번호)
- [ ] `generate.sh` 재실행 가능
- [ ] `.gitignore` 로 중간 파일 제외
- [ ] README에 재생성 방법 명시
- [ ] 원문 설계 문서 교차 참조 (각 장 말미 `docs/NN §M.P 참조`)

---

## 5. 예상 산출물 크기

경험치 (SAP 프로젝트 기준):

| 항목 | 한국어 | 영문 |
|-----|-------|-----|
| MD | ~110KB (3,200 lines) | ~90KB (2,700 lines) |
| DOCX | ~90KB | ~75KB |
| PDF | ~265KB | ~185KB |

출처 문서가 ~12,000 lines일 때의 결과. synthesize 비율 약 25-30%.

---

## 6. 제한 사항

- **한/영 이중 번역 품질**: 기계 번역 수준이 아닌 수동 재작성 기반이지만, 출판 전 전문 번역가 검토 권장
- **다국어 확장**: 현재 ko/en만 템플릿 지원. 일본어/중국어 추가는 `PANDOC.md`의 폰트/언어 옵션 수정 필요
- **이미지**: Mermaid 다이어그램은 pandoc이 자동 렌더링 안 함 → Mermaid CLI로 SVG 변환 후 삽입
- **수식**: LaTeX 수식은 xelatex 통해 지원, DOCX/HTML은 제한적

---

## 7. 사용 예 (SAP 프로젝트)

실제 예시는 `/Users/saint/01_DEV/app-sap-saas/docs/book/` 참조. 동일한 패턴으로 다른 프로젝트에 적용 가능.

생성된 커밋:
- `4b44750 docs: SAP 설계서 단행본 신설 (한/영 × MD/DOCX/PDF)`
- 10 파일, 11,568 insertions
