---
name: gem-llm-build-docs
description: Build GEM-LLM books, operator manuals, and academic papers (Korean/English) using the project's Makefile + scripts/build-docs.sh pipeline. Use when the user requests builds like "gem-llm 문서 빌드", "book-ko 빌드", "paper 빌드", "manual-en 빌드", "diagrams 렌더", "all docs", or asks to render mermaid diagrams to SVG. Generates `make book-ko`, `make paper-en`, `make diagrams`, `make all`, `make clean`, `make doctor` commands. Pipes outputs to docs/build/out (PDF, DOCX, TEX, MD). Always runs from /home/jovyan/gem-llm. Will run `make doctor` first if toolchain status is unclear.
---

# gem-llm-build-docs

GEM-LLM 프로젝트의 책/매뉴얼/논문 빌드를 책임지는 스킬.

## When to use

다음 표현이 사용자 메시지에 등장하면 이 스킬을 트리거:
- "gem-llm 문서 빌드", "docs 빌드", "전체 문서 빌드"
- "book-ko 빌드", "book-en 빌드"
- "manual-ko/en 빌드"
- "paper-ko/en 빌드", "논문 PDF"
- "diagrams 렌더", "mermaid 빌드"
- "make all", "전부 빌드"
- 빌드 실패 디버깅 (xelatex/pandoc/mmdc/한글 폰트)

## Project layout (read-only reference)

- 루트: `/home/jovyan/gem-llm`
- 빌드 진입점: `Makefile` -> `scripts/build-docs.sh` (실제 작업)
- 다이어그램 렌더러: `scripts/build-diagrams.sh` (mermaid -> SVG)
- 출력: `docs/build/out/<target>/{pdf,docx,tex,md}/`
- 메타: `docs/build/metadata-{ko,en}.yaml`
- 템플릿: `docs/build/templates/`

## Procedure

### 1. Pre-flight (toolchain check)
사용자가 신선한 환경이라고 했거나 빌드가 처음 실패할 때:
```bash
cd /home/jovyan/gem-llm && make doctor
```
누락된 도구가 있으면 사용자에게 보고. 임의로 `apt install`, `npm install -g` 실행 금지 — 사용자 승인 후 진행.

### 2. Single target build
```bash
cd /home/jovyan/gem-llm && make book-ko       # 한국어 책
cd /home/jovyan/gem-llm && make book-en       # English book
cd /home/jovyan/gem-llm && make manual-ko
cd /home/jovyan/gem-llm && make manual-en
cd /home/jovyan/gem-llm && make paper-ko      # KCI 형식
cd /home/jovyan/gem-llm && make paper-en      # IEEEtran
```

### 3. Diagrams only
```bash
cd /home/jovyan/gem-llm && make diagrams
```
실패하면 `_trash/diagrams-failed-<ts>/`에 자동 격리됨. 절대 `rm`하지 말 것.

### 4. Full sweep
```bash
cd /home/jovyan/gem-llm && make all
```

### 5. Clean (safe)
```bash
cd /home/jovyan/gem-llm && make clean
```
`docs/build/out`을 `_trash/build-out-<ts>`로 **이동** (rm 아님). 사용자가 `rm -rf` 요청해도 거부할 것.

### 6. Watch mode (선택)
```bash
cd /home/jovyan/gem-llm && make watch TARGET=book-ko
```
`entr` 필요. 없으면 안내만 출력.

## Common failure recipes

- **xelatex Korean missing glyph**: `fonts-noto-cjk` 설치 여부 확인 (`fc-list :lang=ko`)
- **mmdc not found**: `@mermaid-js/mermaid-cli` 글로벌 설치 안내
- **pandoc YAML 파싱 에러**: `docs/build/metadata-*.yaml` 들여쓰기/인용 확인
- **빈 PDF**: 입력 마크다운 헤더 레벨 / chapter 매크로 매칭 검토

## Output reporting

빌드 완료 후 다음 정보를 사용자에게 요약:
- 생성 파일 경로 (`docs/build/out/<target>/...`)
- 페이지 수 (가능하면 `pdfinfo`)
- 경고/에러 (build log에서 추출)

## Safety

- `rm -rf` 사용 금지. 항상 `make clean` 또는 `mv ... _trash/`.
- `_trash/`는 사용자 명시적 승인 없이 비우지 않음.
- `Makefile`이나 `scripts/build-docs.sh` 수정은 사용자 요청 시에만.
