# pandoc 설정 레퍼런스

> MD → DOCX/PDF 변환 명령 모음 + 검증된 옵션.

---

## 1. 기본 명령

### 1.1 MD → DOCX

```bash
pandoc book.md \
  --from=gfm+yaml_metadata_block+raw_html \
  --to=docx \
  --toc --toc-depth=2 \
  --number-sections \
  --standalone \
  --metadata title="Book Title" \
  -o book.docx
```

### 1.2 MD → PDF (xelatex)

**권장 방법** (한글 지원).

```bash
pandoc book.md \
  --from=gfm+yaml_metadata_block+raw_html \
  --pdf-engine=xelatex \
  --toc --toc-depth=2 \
  --number-sections \
  -V mainfont="Apple SD Gothic Neo" \
  -V CJKmainfont="Apple SD Gothic Neo" \
  -V monofont="D2Coding" \
  -V geometry:"margin=20mm" \
  -V fontsize=10pt \
  -V linkcolor=blue \
  -V colorlinks=true \
  -V documentclass=article \
  -o book.pdf
```

### 1.3 MD → PDF (weasyprint) — 대안

weasyprint이 정상 동작하는 환경에서만 사용. macOS에서 `libgobject` 로딩 이슈 자주 발생.

```bash
# 1) MD → HTML
pandoc book.md \
  --from=gfm+yaml_metadata_block+raw_html \
  --to=html5 \
  --toc --toc-depth=2 \
  --number-sections \
  --standalone \
  --css=assets/css/book.css \
  --metadata lang="ko" \
  -o book.html

# 2) HTML → PDF
weasyprint book.html book.pdf
```

### 1.4 MD → EPUB (전자책)

```bash
pandoc book.md \
  --to=epub3 \
  --toc --toc-depth=2 \
  --number-sections \
  --metadata title="Book" \
  --metadata author="Author" \
  --epub-cover-image=cover.png \
  -o book.epub
```

---

## 2. 언어별 폰트 설정

### 2.1 한국어

macOS (권장):
```
-V mainfont="Apple SD Gothic Neo"
-V CJKmainfont="Apple SD Gothic Neo"
```

Linux/Docker:
```
-V mainfont="Noto Sans CJK KR"
-V CJKmainfont="Noto Sans CJK KR"
```

폰트 확인:
```bash
fc-list :lang=ko | head
```

### 2.2 일본어

```
-V mainfont="Hiragino Kaku Gothic Pro"
-V CJKmainfont="Hiragino Kaku Gothic Pro"
```

### 2.3 중국어

```
-V mainfont="PingFang SC"
-V CJKmainfont="PingFang SC"
```

### 2.4 영어 (CJK 없을 때)

```
-V mainfont="Helvetica"
-V monofont="Menlo"
```

---

## 3. 페이지/타이포그래피 옵션

| 옵션 | 설명 | 예 |
|-----|-----|----|
| `-V geometry` | 페이지 여백 | `margin=20mm`, `a4paper` |
| `-V fontsize` | 본문 크기 | `10pt`, `11pt`, `12pt` |
| `-V linestretch` | 행간 | `1.5` |
| `-V documentclass` | LaTeX 문서 클래스 | `article`, `book`, `report` |
| `-V classoption` | 문서 클래스 옵션 | `twoside`, `openany` |
| `-V linkcolor` | 링크 색상 | `blue`, `red` |
| `-V colorlinks` | 색상 링크 활성화 | `true` |
| `--highlight-style` | 코드 강조 스타일 | `breezedark`, `pygments`, `tango` |
| `-V mathfont` | 수식 폰트 | `XITS Math` |

---

## 4. 여러 Markdown 파일 병합

챕터 분리 시:

```bash
pandoc \
  01-preface.md \
  02-chapter1.md \
  03-chapter2.md \
  --pdf-engine=xelatex \
  --toc \
  -o book.pdf
```

또는 글로브:
```bash
pandoc chapters/*.md --pdf-engine=xelatex -o book.pdf
```

---

## 5. `generate.sh` 템플릿

```bash
#!/usr/bin/env bash
# Book generation script
# Usage:
#   ./generate.sh                   # 모든 언어, 모든 형식
#   ./generate.sh ko                # 한국어 모든 형식
#   ./generate.sh en docx           # 영문 docx만

set -euo pipefail

BOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LANG_FILTER="${1:-all}"
FORMAT_FILTER="${2:-all}"

# 언어별 폰트 (macOS 기본)
KO_FONT="Apple SD Gothic Neo"
EN_FONT="Apple SD Gothic Neo"    # 영문에도 한글 섞일 수 있어 동일 권장
MONO_FONT="D2Coding"

generate_lang() {
  local lang="$1"
  local dir="$BOOK_DIR/$lang"
  local md="$dir/book.md"         # 또는 프로젝트별 네이밍
  local docx="$dir/book.docx"
  local pdf="$dir/book.pdf"

  [[ ! -f "$md" ]] && { echo "⚠️  $md 없음 — 건너뜀"; return 0; }

  local title
  local font
  if [[ "$lang" == "ko" ]]; then
    title="<Korean Title>"
    font="$KO_FONT"
  else
    title="<English Title>"
    font="$EN_FONT"
  fi

  cd "$dir"

  if [[ "$FORMAT_FILTER" == "all" || "$FORMAT_FILTER" == "docx" ]]; then
    echo "📄 [$lang] DOCX 생성 → $docx"
    pandoc "$md" \
      --from=gfm+yaml_metadata_block+raw_html \
      --to=docx \
      --toc --toc-depth=2 \
      --number-sections \
      --standalone \
      --metadata title="$title" \
      -o "$docx"
  fi

  if [[ "$FORMAT_FILTER" == "all" || "$FORMAT_FILTER" == "pdf" ]]; then
    echo "📕 [$lang] PDF 생성 → $pdf"
    pandoc "$md" \
      --from=gfm+yaml_metadata_block+raw_html \
      --pdf-engine=xelatex \
      --toc --toc-depth=2 \
      --number-sections \
      -V mainfont="$font" \
      -V CJKmainfont="$font" \
      -V monofont="$MONO_FONT" \
      -V geometry:"margin=20mm" \
      -V fontsize=10pt \
      -V linkcolor=blue \
      -V colorlinks=true \
      -V documentclass=article \
      -o "$pdf" 2>&1 | grep -vE '^\[WARNING\] Missing character' | tail -15 || true
  fi

  echo "✅ [$lang] 완료"
  cd "$BOOK_DIR"
}

if [[ "$LANG_FILTER" == "all" ]]; then
  for lang in ko en; do
    generate_lang "$lang"
  done
else
  generate_lang "$LANG_FILTER"
fi

echo ""
echo "🎉 모든 작업 완료"
ls -lh "$BOOK_DIR"/{ko,en}/book.{docx,pdf} 2>/dev/null || true
```

실행권한: `chmod +x generate.sh`

---

## 6. 에러 필터링

xelatex는 많은 경고 출력. 스크립트에서 유용한 것만 표시:

```bash
pandoc ... 2>&1 | grep -vE '^\[WARNING\] Missing character' | tail -15
```

특히 이모지(🤖)와 특수문자(☑)는 경고만 나고 변환은 성공.

---

## 7. 성능 최적화

### 7.1 큰 파일 처리

5,000+ lines 파일의 PDF 변환이 느리면:

```bash
# fast mode (수식 렌더링 간소화)
pandoc ... -V classoption=fleqn
```

### 7.2 병렬 생성

한/영 + 3개 형식 = 6개 산출물 병렬:

```bash
./generate.sh ko docx &
./generate.sh ko pdf &
./generate.sh en docx &
./generate.sh en pdf &
wait
```

---

## 8. 특수 요구

### 8.1 표지 페이지 (cover)

MD에 HTML block 삽입:

```html
<div class="cover">

# Book Title

<div class="subtitle">Subtitle</div>
<div class="version">Version X · YYYY-MM</div>

</div>
```

CSS로 스타일링 (weasyprint) 또는 xelatex는 LaTeX 템플릿 커스텀 필요.

### 8.2 헤더/푸터 (xelatex)

`-V` 옵션으로:
```
-V header-includes="\usepackage{fancyhdr}\pagestyle{fancy}\fancyhead[L]{Chapter}\fancyfoot[C]{\thepage}"
```

### 8.3 코드 블록 폰트 / 색상

```
--highlight-style=tango
-V monofont="D2Coding"
```

D2Coding은 한글 지원 고정폭 폰트. 없으면 `Menlo` (macOS) 또는 `DejaVu Sans Mono` (Linux).

---

## 9. 검증 커맨드

생성된 PDF의 기본 메타데이터:
```bash
pdfinfo book.pdf       # 페이지 수, 제목 등
mdfind -name book.pdf  # 파일 위치
```

DOCX 구조 확인:
```bash
unzip -l book.docx     # 내부 XML 확인
```

---

## 10. 환경별 체크리스트

### macOS
- [ ] `brew install pandoc`
- [ ] MacTeX 설치 (`brew install --cask mactex-no-gui` 또는 수동)
- [ ] Apple SD Gothic Neo 기본 탑재 확인

### Linux (Ubuntu/Debian)
- [ ] `apt install pandoc texlive-xetex texlive-fonts-recommended`
- [ ] `apt install fonts-noto-cjk`
- [ ] 폰트 이름: "Noto Sans CJK KR"

### Docker (재현 가능 빌드)
```dockerfile
FROM pandoc/latex:3
RUN apt-get update && apt-get install -y fonts-noto-cjk
WORKDIR /book
ENTRYPOINT ["./generate.sh"]
```
