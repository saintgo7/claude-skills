---
name: pandoc-bilingual-build
description: 'Pandoc + XeTeX로 한/영 동시 책/매뉴얼/논문 빌드 파이프라인을 기존 프로젝트에 추가. 사용 시점 — "Pandoc 빌드 파이프라인", "한영 책 빌드 추가", "IEEEtran 논문 템플릿", "KCI 논문", "Mermaid SVG 빌드", "한글 PDF 안 됨", "xeCJK 셋업". 책/논문/매뉴얼 4 포맷(PDF/DOCX/TEX/MD) × 6 타겟. project-bootstrap의 빌드 부분만 분리해 기존 프로젝트에 부착 가능.'
---

# pandoc-bilingual-build

`project-bootstrap`의 **빌드 파이프라인만** 분리한 skill. 이미 디렉토리 구조가 있는 프로젝트에 한/영 빌드 추가.

## 사용 시점

- "Pandoc 빌드 한영 추가"
- "기존 repo에 책/논문 빌드 붙이기"
- "Mermaid SVG → PDF 자동화"
- "IEEEtran 학회 논문 형식"
- "KCI 한국 학회 논문 템플릿"
- "xeCJK 한글 PDF 안 됨"

## 한 줄 사용

```bash
bash ~/.claude/skills/pandoc-bilingual-build/scripts/install-into.sh /path/to/your-project
```

자동:
1. `Makefile` 6개 타겟 (book-ko/en, manual-ko/en, paper-ko/en) + `make all`
2. `scripts/build-docs.sh`, `build-diagrams.sh`, `extract-mmd.sh`
3. `scripts/pandoc-filters/` (diagram-insert.lua, citation-fix.lua, code-block-listing.lua)
4. `docs/build/templates/` (book-{ko,en}.tex, paper-ko-kci.tex, paper-en-{ieee,acmart}.tex)
5. `docs/build/metadata-{ko,en}.yaml`
6. `docs/{book,manual,paper}-{ko,en}/OUTLINE.md` (없으면 stub)
7. `docs/diagrams/CATALOG.md` + 40 mermaid stub

## 빌드 명령 (설치 후)

```bash
make book-ko book-en      # 한/영 책 (PDF + DOCX + TEX + MD 각)
make manual-ko manual-en  # 한/영 매뉴얼
make paper-ko paper-en    # 한/영 논문 (KCI + IEEE)
make all                  # 6 targets × 4 formats = 24 산출물
make diagrams             # 40 Mermaid → SVG
make clean                # docs/build/out → _trash/
```

## 시스템 의존성 (한 번만)

```bash
sudo apt install -y \
  texlive-xetex texlive-publishers texlive-lang-cjk \
  texlive-fonts-recommended fonts-noto-cjk fonts-noto-cjk-extra \
  librsvg2-bin

# Mermaid SVG (chromium 의존)
sudo apt install -y \
  libatk-bridge2.0-0 libatk1.0-0 libcups2 libdrm2 libgbm1 libgtk-3-0 \
  libnspr4 libnss3 libxcomposite1 libxdamage1 libxfixes3 libxkbcommon0 \
  libxrandr2 libpango-1.0-0 libcairo2 libasound2t64 libxshmfence1 \
  fonts-liberation

# nvm npm 사용 시
npm install -g @mermaid-js/mermaid-cli
```

## 본문 디렉토리 구조 (이 skill이 다루는 부분)

```
your-project/
├── Makefile                         # ← 이 skill이 추가
├── scripts/
│   ├── build-docs.sh                # ← 추가
│   ├── build-diagrams.sh            # ← 추가
│   ├── extract-mmd.sh               # ← 추가
│   └── pandoc-filters/              # ← 추가
│       ├── diagram-insert.lua
│       ├── citation-fix.lua
│       └── code-block-listing.lua
└── docs/
    ├── book-ko/{OUTLINE.md, parts/} # ← OUTLINE만 stub 추가
    ├── book-en/                     # mirror
    ├── manual-{ko,en}/
    ├── paper-{ko,en}/{OUTLINE.md, sections/, references.bib}
    ├── diagrams/{CATALOG.md, mmd/, svg/}
    └── build/
        ├── metadata-{ko,en}.yaml    # ← 추가
        ├── templates/               # ← 추가
        │   ├── book-{ko,en}.tex
        │   ├── paper-ko-kci.tex
        │   ├── paper-en-ieee.tex
        │   └── paper-en-acmart.tex
        └── out/                     # ← 빌드 산출물
```

## Mermaid 다이어그램 워크플로

1. `docs/diagrams/CATALOG.md`에 다이어그램 정의 (frontmatter + ` ```mermaid` 코드블럭)
2. `bash scripts/extract-mmd.sh` → `docs/diagrams/mmd/diagram-NN.mmd` 추출
3. `bash scripts/build-diagrams.sh` → `docs/diagrams/svg/diagram-NN.svg` 빌드
4. 본문에서 `![diagram-NN 제목](../../diagrams/svg/diagram-NN.svg)`로 참조
5. Pandoc Lua filter `diagram-insert.lua`가 빌드 시 자동 인라인

## 한글 PDF 핵심 옵션

```yaml
# docs/build/metadata-ko.yaml
mainfont: "Noto Sans KR"
monofont: "DejaVu Sans Mono"
documentclass: book
geometry: a4paper, margin=2.5cm
```

```latex
% docs/build/templates/book-ko.tex
\usepackage{xeCJK}
\setCJKmainfont{Noto Sans KR}
\XeTeXlinebreaklocale "ko"
\XeTeXlinebreakskip = 0pt plus 1pt minus 0.1pt
```

xeCJK 미설치 시 fontspec만으로도 작동 (단, 한글 줄바꿈 품질이 약간 떨어짐).

## 학회 템플릿

### KCI (한국정보과학회)

`docs/build/templates/paper-ko-kci.tex` — 일반 article + xeCJK + 2단 조판.

### IEEE Conference

`docs/build/templates/paper-en-ieee.tex` — `\documentclass[conference]{IEEEtran}` + IEEEkeywords.

`texlive-publishers` 패키지에 IEEEtran.cls 포함.

### ACM SIGCONF

`docs/build/templates/paper-en-acmart.tex` — `\documentclass[sigconf]{acmart}`.

## 흔한 에러

| 증상 | 해결 |
|---|---|
| `! LaTeX Error: File 'IEEEtran.cls' not found` | `sudo apt install texlive-publishers` |
| `! Package xeCJK Error: Cannot define encoding "UTF8"` | `sudo apt install texlive-lang-cjk` |
| `Missing character: There is no 한 (U+...) in font DejaVu Sans Mono` | 코드블럭 안 한글 — `\setmonofont` 변경 또는 무시 |
| `mmdc: command not found` | `npm install -g @mermaid-js/mermaid-cli` (nvm 권장) |
| `chromium-browser requires snap` | snap 없는 환경 → puppeteer 자체 Chrome (`puppeteer browsers install chrome`) |
| `libatk-1.0.so.0: cannot open` | Chrome libs 설치 (위 의존성 섹션) |
| 한글 폰트 없음 | `sudo apt install fonts-noto-cjk fonts-noto-cjk-extra` |
| `librsvg2-bin` 부재 → cairosvg | `sudo apt install librsvg2-bin` 또는 cairosvg 시멘틱 wrapper |

## 검증

```bash
# 빌드 dry-run
DRY_RUN=1 bash scripts/build-docs.sh book-ko pdf

# 다이어그램 SVG 빌드
bash scripts/build-diagrams.sh
ls docs/diagrams/svg/  # 40개 SVG

# 실제 빌드
make book-ko
ls -lh docs/build/out/book-ko.pdf  # ~1.5M for ~500p
```

## 관련 skill

- `project-bootstrap` — 빈 프로젝트에서 시작 시 (이 skill의 상위)
- `gem-llm-build-docs` — GEM-LLM 운영 환경 특화 (이미 설치된 환경)

## 참조

- Pandoc 매뉴얼: https://pandoc.org/MANUAL.html
- IEEEtran: https://ctan.org/pkg/ieeetran
- acmart: https://ctan.org/pkg/acmart
- xeCJK: https://ctan.org/pkg/xecjk
