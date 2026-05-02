---
name: mermaid-diagram-authoring
description: 'Mermaid 다이어그램 작성 + Pandoc 통합 검증된 패턴. 사용 시점 — "다이어그램 작성", "mermaid 카탈로그", "mmdc 빌드", "SVG 자동 삽입", "한글 라벨 다이어그램", "syntax error mermaid". CATALOG.md 단일 파일 + extract-mmd → mmdc → SVG → Lua filter 자동 삽입 5단계.'
---

# mermaid-diagram-authoring

책 한 권에 다이어그램이 30~50개 들어가면, 각 chapter 안에 mermaid 블록을 흩어 놓는 방식은 깨지기 쉽다 — 같은 다이어그램을 한/영 두 책에서 공유할 수 없고, syntax error 가 한 곳만 나도 어느 다이어그램인지 찾기 힘들고, SVG 빌드 캐싱이 안 된다. *CATALOG.md 단일 파일* 에 모든 다이어그램을 정의하고, 스크립트로 `.mmd` 추출 → `mmdc` SVG 빌드 → Pandoc Lua filter 가 본문에 자동 삽입하는 5단계 파이프라인이 정답이다.

이 skill 은 GEM-LLM 한/영 책의 **40 다이어그램 (36 한/영 공유 + 4 단일 언어)** 을 빌드하면서 검증된 패턴이다. mermaid 0.9 → 0.10 syntax 변경 (case 1: 다중 공백, 단일 hyphen edge) 같은 회귀 사례까지 포함한다.

## 1. 사용 시점

- "다이어그램 작성" / "mermaid 카탈로그"
- "mmdc 빌드 실패" / "syntax error mermaid"
- "SVG 자동 삽입" / "Pandoc + mermaid"
- "한글 라벨 다이어그램" / "Noto Sans KR mmdc"
- 책/논문/매뉴얼에 10개 이상 다이어그램이 들어갈 때
- 한/영 두 언어가 같은 다이어그램을 공유해야 할 때
- 다이어그램이 본문에 흩어져 있어 일관성 관리가 어려울 때

## 2. 6 카테고리 (GEM-LLM 40 다이어그램 검증)

40개를 일일이 새로 디자인하지 말고, 아래 6 카테고리에서 시작하면 90% 이상 커버된다.

| 카테고리 | 사용처 | Mermaid 종류 |
|---|---|---|
| 시스템 전체상 | book Ch.1, paper Fig.1 | flowchart LR |
| 시퀀스 (요청 흐름) | book Ch.4, Ch.9 | sequenceDiagram |
| 데이터 모델 ER | book Ch.6 | erDiagram |
| 상태/인증 흐름 | book Ch.7, Ch.12 | flowchart, classDiagram |
| 배포 토폴로지 | book Ch.13 | deployment / flowchart subgraph |
| 모니터링/대시보드 | book Ch.14 | gantt 또는 flowchart |

GEM-LLM 의 경우 시스템 전체상 (8) + 시퀀스 (12) + ER (3) + 상태 (9) + 배포 (5) + 모니터링 (3) = 40 으로 분포했다.

## 3. 5단계 워크플로

### Step 1: CATALOG.md 단일 파일에 정의

`diagrams/CATALOG.md` 에 모든 다이어그램을 한 곳에 모은다. ID, 타입, 설명 (한/영), 사용처, mermaid 코드를 한 블록에 묶는다.

````markdown
## diagram-01 — 시스템 전체상 / Whole-System View
- **Type:** flowchart
- **Description (KO):** 사용자 → Gateway → vLLM 흐름
- **Description (EN):** End-to-end flow
- **Used in:** book Ch.1, paper Fig.1

```mermaid
flowchart LR
  U[Users] -->|HTTPS| GW[Gateway]
  GW --> V[vLLM]
```
````

장점:
- ID 가 unique 하므로 한/영 책 모두 같은 다이어그램 참조 가능
- syntax error 발생 시 어느 ID 인지 즉시 식별
- diagram review 가 한 파일에서 가능

### Step 2: extract-mmd 스크립트로 .mmd 파일 추출

```bash
bash scripts/extract-mmd.sh
# CATALOG.md 파싱 → mmd/diagram-NN.mmd 40개 생성
```

CATALOG.md 의 각 ` ```mermaid ... ``` ` 블록을 ID 기반 파일명으로 추출. mmd 파일은 *gitignore* 해도 됨 (CATALOG.md 가 single source of truth).

### Step 3: mmdc 로 SVG 빌드

```bash
mmdc -i mmd/diagram-01.mmd -o svg/diagram-01.svg \
  -p puppeteer.json -t default -b transparent
```

병렬화: `find mmd -name '*.mmd' | xargs -P 4 -I {} mmdc -i {} ...`. GEM-LLM 40개 빌드 ~30초 (4 병렬, B200 노드 무관 — chromium 단일 코어).

### Step 4: Pandoc Lua filter 로 자동 삽입

`diagram-insert.lua` 가 본문의 `![](../diagrams/svg/diagram-01.svg)` 참조를 절대 경로로 변환하고 caption 보강:

```lua
-- diagram-insert.lua
function Image(img)
  local src = img.src
  if src:match("diagram%-%d+%.svg$") then
    -- 절대 경로로 변환 + caption 추가
    img.src = pandoc.path.normalize(src)
    if not img.caption[1] then
      img.caption = pandoc.MetaInlines(pandoc.Str("Diagram"))
    end
  end
  return img
end
```

`pandoc-bilingual-build` skill 의 빌드 파이프라인에서 `--lua-filter=diagram-insert.lua` 로 호출.

### Step 5: 본문에서 참조

```markdown
![diagram-01 시스템 전체상](../../diagrams/svg/diagram-01.svg)
```

본문에서는 *반드시* `diagram-NN` 패턴 ID 를 alt-text 에 포함. lint 가 누락된 ID 를 잡아낸다.

## 4. Mermaid syntax 함정 (case 1 일반화)

case 1: GEM-LLM 빌드 중 mermaid CLI 0.9 → 0.10 업그레이드 후 절반의 다이어그램이 깨졌다. 원인은 *공백 처리* 와 *edge syntax* 의 strict 화. 아래 표는 이후 검증된 안전 패턴.

| 함정 | 깨지는 패턴 | 안전한 패턴 |
|---|---|---|
| 다중 공백 | `A  -->  B` | `A --> B` |
| 단일 hyphen edge | `A -.-> B` | `A -.->\|label\| B` |
| 한글 라벨 | `A -->\|한국어\|B` | quote: `A -->\|"한국어"\|B` |
| 특수문자 | `A --> B(C/D)` | `A --> B[C-D]` |
| 줄바꿈 | `A --> B\nC` | `A --> B<br/>C` |

규칙: edge 는 정확히 한 칸 공백, 라벨은 항상 double quote, 줄바꿈은 `<br/>`.

## 5. 한글 라벨 주의사항

- *노드 이름* 은 영문 (`U`, `GW`, `V`) — ID 충돌/lint 회피
- *라벨* 만 한글 (`U[사용자]`)
- 한글 라벨 *안* 의 공백은 OK (`U[사용자 그룹]`)
- 한글 라벨이 edge label 일 때 (`-->|...|`) double quote 필수
- `puppeteer.json` 에 한글 폰트 명시:

```json
{
  "args": ["--no-sandbox", "--font-render-hinting=none"],
  "executablePath": "/usr/bin/chromium",
  "defaultViewport": null
}
```

폰트는 컨테이너에 `fonts-noto-cjk` 패키지 설치 + `~/.config/fontconfig/fonts.conf` 에 Noto Sans KR 우선순위 설정.

## 6. mmd lint (CI)

```bash
bash scripts/lint-mmd.sh
```

- mmdc 의 dry-run (`--quiet`) 으로 syntax 검증
- 0-byte SVG 검사 (mmdc 가 silent fail 하는 경우 있음)
- CATALOG ID ↔ `mmd/*.mmd` ↔ `svg/*.svg` 1:1:1 일치 검증
- 실패 시 어느 다이어그램 ID 가 깨졌는지 명확히 출력

CI 에서 본문 빌드 *전* 에 lint-mmd 가 통과해야 함.

## 7. Pandoc 통합 (pandoc-bilingual-build skill)

빌드 인프라는 `pandoc-bilingual-build` 에 있다. 이 skill 에서 추가하는 것:

- Lua filter `diagram-insert.lua` 추가
- 빌드 파이프라인에 `lint-mmd` → `extract-mmd` → `mmdc` 단계 삽입
- 한/영 책 모두 같은 `svg/diagram-NN.svg` 를 참조 (사례: GEM-LLM 36개 한/영 mirror)

한/영 mirror 가능한 이유: SVG 안에 텍스트가 거의 없거나 영문 (시스템 식별자) 이고, 한글 caption 만 본문에서 다르게 붙이기 때문. 라벨이 한글 → 영어로 바뀌는 4개만 한/영 별도 SVG 빌드.

## 8. GEM-LLM 검증 결과

- 40 다이어그램, 36 한/영 공유, 4 단일 언어
- 빌드 시간 ~30s (40개 SVG, 4 병렬)
- 회귀 사례: case 1 (mermaid 0.9 → 0.10 syntax change), case 2 (chromium libnss3 누락)
- 책 빌드 전체 (다이어그램 + Pandoc + XeTeX) ~3분

## 9. 흔한 함정

- CATALOG.md 만 있고 `.mmd` 없음 (extract-mmd 단계 누락)
- `.mmd` 있고 `.svg` 없음 (mmdc 실패 — lint-mmd 가 없으면 silent)
- 본문에서 잘못된 ID 참조 (`diagram-NN` 패턴 누락 → Lua filter pass-through)
- 한글 라벨 quote 누락 (rendering 깨짐, syntax 통과)
- mmdc puppeteer chromium libs 누락 (case 2: libnss3, libxss1, libasound2)
- mermaid 버전 mix (mmdc CLI 와 vscode preview 가 다른 버전 → preview 통과 / CI 실패)

## 10. 관련 skill

- `pandoc-bilingual-build` — 빌드 인프라 (XeTeX, Lua filter 호출 위치)
- `bilingual-book-authoring` — 한/영 책 저작 워크플로 (CATALOG mirror 결정 지점)
