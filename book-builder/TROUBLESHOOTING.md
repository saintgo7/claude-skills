# 트러블슈팅

> 책 생성 중 자주 발생하는 문제와 해결법.

---

## 1. 환경 / 도구 설치

### 1.1 `pandoc: command not found`

**해결**:
```bash
# macOS
brew install pandoc

# Ubuntu/Debian
sudo apt install pandoc

# 최신 버전 필요 시 GitHub release 다운로드
# https://github.com/jgm/pandoc/releases
```

확인: `pandoc --version` (3.x+ 권장)

### 1.2 `xelatex: command not found`

**해결**:
```bash
# macOS (권장: basictex만, 경량)
brew install --cask basictex
eval "$(/usr/libexec/path_helper)"
sudo tlmgr update --self
sudo tlmgr install collection-fontsrecommended collection-latexrecommended xecjk

# macOS (full MacTeX, 4GB+)
brew install --cask mactex-no-gui

# Ubuntu/Debian
sudo apt install texlive-xetex texlive-fonts-recommended \
                 texlive-latex-recommended texlive-latex-extra
```

확인: `xelatex --version`

### 1.3 `weasyprint` 관련 에러 (macOS)

**증상**:
```
OSError: cannot load library 'libgobject-2.0-0'
```

**원인**: homebrew의 glib 라이브러리 경로 문제.

**해결 1** (권장): xelatex로 전환 (§PANDOC.md §1.2)

**해결 2**: 라이브러리 경로 강제
```bash
export DYLD_LIBRARY_PATH="/opt/homebrew/lib:$DYLD_LIBRARY_PATH"
weasyprint ...
```

**해결 3**: Docker에서 실행 (재현 가능)
```bash
docker run -v $(pwd):/work -w /work pandoc/latex:3 \
  pandoc book.md -o book.pdf --pdf-engine=xelatex ...
```

---

## 2. 폰트 문제

### 2.1 `Package fontspec Error: The font "X" cannot be found`

**증상**: xelatex가 지정된 폰트를 못 찾음.

**확인**:
```bash
# macOS/Linux 공통
fc-list | grep -i "<font name>"

# 정확한 이름 확인
fc-list :lang=ko
```

**해결**:

| 환경 | 사용 가능 폰트 |
|------|-------------|
| macOS (기본) | "Apple SD Gothic Neo" (한글), "Menlo" (mono) |
| macOS (선택 설치) | "Noto Sans CJK KR" |
| Linux (Noto) | "Noto Sans CJK KR", "Noto Sans Mono CJK KR" |
| Docker pandoc/latex | 기본 없음 → `RUN apt install fonts-noto-cjk` 추가 |

`generate.sh`에서 시스템별 폰트 자동 선택:
```bash
if [[ "$OSTYPE" == "darwin"* ]]; then
  KO_FONT="Apple SD Gothic Neo"
else
  KO_FONT="Noto Sans CJK KR"
fi
```

### 2.2 한글 깨짐 (사각형)

**증상**: PDF에 한글이 `□□□□`로 표시.

**원인**: CJK 폰트가 주 폰트에 포함되지 않음.

**해결**:
```bash
# 반드시 CJKmainfont 지정
-V mainfont="Apple SD Gothic Neo" \
-V CJKmainfont="Apple SD Gothic Neo"
```

두 옵션 모두 필요. `mainfont`만 지정하면 영문만 정상, `CJKmainfont`만 지정하면 한글만 정상.

### 2.3 이모지 경고 (`Missing character: 🤖`)

**무시 가능**: xelatex는 이모지 폰트가 없어도 변환은 성공. 경고만 출력.

**해결**:
1. 이모지 제거 (권장): `sed -i '' 's/🤖//g' book.md`
2. 이모지 폰트 추가: `-V mainfontoptions="Fallback=Apple Color Emoji"` (느려짐)

`generate.sh`에서 경고 필터:
```bash
pandoc ... 2>&1 | grep -vE '^\[WARNING\] Missing character'
```

### 2.4 고정폭 폰트 없음 (`D2Coding not found`)

**해결**: 대체 폰트
```bash
# macOS 기본
-V monofont="Menlo"

# Linux 기본
-V monofont="DejaVu Sans Mono"

# Docker 컨테이너 내
-V monofont="Liberation Mono"
```

D2Coding은 한글 지원 고정폭 폰트. 필요 시:
```bash
brew install --cask font-d2coding
```

---

## 3. 변환 실패

### 3.1 `Error producing PDF` (구체적 메시지 없이)

**원인**: LaTeX 컴파일 에러. 자세히 보려면 `--verbose`:

```bash
pandoc ... --pdf-engine=xelatex --verbose 2>&1 | tail -50
```

### 3.2 `! Undefined control sequence`

**증상**: Markdown의 일부 LaTeX 명령어가 인식 안 됨.

**원인**: raw LaTeX가 본문에 포함. 예: `\url{}`, `\cite{}`.

**해결**: raw LaTeX 제거 또는 pandoc용 Markdown 문법으로 교체.

### 3.3 `Runaway argument`

**증상**: 중괄호 불균형.

**원인**: 코드 블록 내 `{`, `}` 가 LaTeX로 해석됨.

**해결**:
```bash
--from=gfm+raw_html   # raw_html 포함하되 raw_tex 제외
```

pandoc이 모든 코드 블록을 자동 escape.

### 3.4 `dimension too large`

**증상**: 매우 긴 테이블 또는 넓은 이미지.

**해결**:
```bash
# 테이블을 longtable로
-V classoption="twocolumn,smaller"

# 이미지 크기 제한
![alt](image.png){width=80%}
```

### 3.5 `underfull hbox` / `overfull hbox`

**증상**: 경고만 나오고 변환 성공. 일부 줄이 여백 초과.

**해결**: 무시 또는
```bash
-V classoption="fleqn,nobreak"
```

---

## 4. DOCX 특수 이슈

### 4.1 스타일이 기본값 그대로

**원인**: DOCX는 CSS 적용 안 됨.

**해결**: 커스텀 템플릿 사용
```bash
# 기본 템플릿 추출
pandoc -o reference.docx --print-default-data-file reference.docx

# 템플릿 편집 후 적용
pandoc book.md --reference-doc=reference.docx -o book.docx
```

### 4.2 이미지가 너무 큼

**해결**:
```markdown
![alt](image.png){width=400}
```

### 4.3 TOC 업데이트 필요

**증상**: Word에서 "필드 업데이트" 필요 메시지.

**해결**: Word에서 F9 또는 모든 필드 업데이트 (Ctrl+A → F9).

---

## 5. 성능 문제

### 5.1 PDF 변환이 너무 느림

**대상**: 3,000+ lines 파일

**해결**:
- xelatex 1차 통과는 원래 오래 걸림 (1-3분 정상)
- TOC가 2패스 통과 유발 → 더 오래
- `--toc-depth=1`로 줄이면 단축

### 5.2 메모리 부족

**해결**:
```bash
# LuaLaTeX 대신 xelatex (메모리 효율)
# 또는 weasyprint로 전환
```

---

## 6. 다이어그램

### 6.1 Mermaid 다이어그램이 PDF에 안 나옴

**원인**: pandoc은 Mermaid 기본 미지원.

**해결 1** (권장): ASCII art로 변환
```
┌──────────┐    ┌──────────┐
│ Client   │ ─▶ │ Server   │
└──────────┘    └──────────┘
```

**해결 2**: Mermaid CLI로 SVG 사전 생성
```bash
npm install -g @mermaid-js/mermaid-cli
mmdc -i diagram.mmd -o diagram.svg
```
MD에 `![alt](diagram.svg)` 로 삽입.

**해결 3**: pandoc-mermaid 필터 (실험적)
```bash
pandoc --filter=pandoc-mermaid ...
```

---

## 7. 인코딩 / 문자

### 7.1 BOM 문제

**증상**: PDF 첫 페이지 상단에 이상한 문자.

**해결**: MD 파일 BOM 제거
```bash
# BOM 확인
head -c 3 book.md | od -c

# BOM 제거 (macOS)
sed -i '' '1s/^\xEF\xBB\xBF//' book.md
```

### 7.2 줄바꿈 혼합 (CRLF/LF)

**해결**:
```bash
dos2unix book.md
```

### 7.3 한자(漢字)가 일본어체로 렌더링

**원인**: CJK 폰트가 일본어 폴백.

**해결**:
```bash
-V CJKmainfont="Apple SD Gothic Neo"
-V CJKoptions="Script=Hangul"
```

---

## 8. 재현성 / CI

### 8.1 로컬은 되는데 CI는 실패

**원인**: 폰트·버전 차이.

**해결**: Docker로 통일
```dockerfile
FROM pandoc/latex:3
RUN apt-get update && \
    apt-get install -y fonts-noto-cjk && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /book
```

```yaml
# .github/workflows/book.yml
- uses: docker://pandoc/latex:3
  with:
    args: book.md --pdf-engine=xelatex -o book.pdf
```

### 8.2 결과물이 매번 다름

**원인**: xelatex의 `\random` 시드, 타임스탬프.

**해결**:
```bash
-V draft=false   # 초안 모드 비활성
# 또는 source code에서 타임스탬프 제거
```

---

## 9. 빠른 진단 순서

문제 발생 시 아래 순서로 시도:

1. `pandoc --version` (3.x+)
2. `xelatex --version` (설치 확인)
3. `fc-list | grep -i <font>` (폰트 존재)
4. `pandoc ... --verbose 2>&1 | tail -50` (상세 로그)
5. 최소 MD 파일로 테스트:
   ```bash
   echo "# 테스트\n한글 테스트" > test.md
   pandoc test.md --pdf-engine=xelatex -V CJKmainfont="Apple SD Gothic Neo" -o test.pdf
   ```
6. 작동하면 원본 파일의 문제 구간 바이섹션

---

## 10. 도움 요청 시 필수 정보

지원 요청할 때 포함:
- OS + 버전 (macOS 14.x, Ubuntu 22.04 등)
- pandoc 버전
- xelatex/MacTeX 버전
- 사용한 명령어 전체
- 에러 메시지 전체 (tail -50)
- MD 파일 앞 50줄
