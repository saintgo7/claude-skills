# 책 작성 패턴

> 여러 Markdown 소스를 **한 권의 책으로 synthesize**할 때 지키는 원칙.

---

## 1. 핵심 원칙: Synthesize, Not Copy-Paste

### 1.1 금지

- ❌ 원문 설계 문서(예: `03-db-schema.md`)의 전체 SQL DDL 섹션을 그대로 복사
- ❌ 16개 문서를 단순 concat
- ❌ 내부 링크(GitHub relative path)를 그대로 유지

### 1.2 권장

- ✅ 원문의 **핵심 결정·인터페이스·예시만 선별 추출**
- ✅ 단행본의 독자 여정(reading order)에 맞게 재구성
- ✅ 원문 세부는 `docs/NN §M.P 참조` 로 위임
- ✅ 여러 문서의 중복 내용을 한 곳에 통합

### 1.3 압축 비율 목표

| 원문 | 책 | 비율 |
|-----|---|-----|
| 10,000-12,000 lines | 3,000-4,000 lines | 25-35% |
| 5,000-7,000 lines | 1,500-2,000 lines | 25-30% |

---

## 2. 장 말미 교차 참조

각 장 마지막에 원문 링크:

```markdown
## N.X 상세 문서 참조

전체 엔드포인트 스펙: `docs/04-api-spec.md` (721줄)
```

또는 섹션 단위:

```markdown
자세한 reconciliation 규칙은 `docs/06-report-system.md §3.4.3` 참조.
```

---

## 3. YAML Frontmatter

```yaml
---
title: 책 제목
subtitle: 부제
author: Author Name
date: 2026-04-21
lang: ko           # ko | en | ja | zh
---
```

pandoc이 DOCX/PDF 메타데이터로 사용.

---

## 4. 커버 페이지

MD 맨 앞에 HTML block:

```markdown
---
title: ...
---

<div class="cover">

# 책 제목

<div class="subtitle">부제</div>

<div class="version">버전 X.Y · YYYY년 MM월</div>

</div>

# 서문
...
```

CSS로 스타일링 (weasyprint) 또는 xelatex LaTeX 템플릿 커스텀 필요.
xelatex만 사용 시 커버는 단순 `# 제목` 페이지로 충분 (TOC 앞에 배치됨).

---

## 5. 목차 (TOC)

pandoc 자동 생성:
```
--toc --toc-depth=2
```

depth 2는 `#`, `##`까지. 너무 상세하면 depth=1, 모든 섹션이면 depth=3.

---

## 6. 섹션 번호

pandoc 자동:
```
--number-sections
```

장 번호가 `1.`, `1.1.`, `1.1.1.` 형식 자동 부여.
수동 `## 1. ...` 표기와 중복될 수 있음 → **수동 번호 사용 권장** (안정적, 교차 참조 일관).

수동 번호 시 `--number-sections` 생략:
```markdown
# 1. 프로젝트 개요

## 1.1 프로젝트 요약
...

## 1.2 해결하려는 문제
...
```

---

## 7. 이중 언어 병행 관리

### 7.1 동일 구조

한/영 파일의 **장 번호와 섹션 번호 완전 일치** 필수. 교차 참조 안전.

### 7.2 번역 원칙

| 유형 | 처리 |
|-----|-----|
| 기술 용어 | 영어 원형 유지 (e.g., "audit note", "signature", "reconciliation") |
| 고유명사 | 괄호 병기 (e.g., "삼성표준인증원 (Samsung Standard Registrar)") |
| 코드 | 동일 유지, 주석만 번역 선택 |
| 다이어그램 | ASCII art 그대로, 라벨만 번역 |
| 테이블 | 헤더·값 번역, 숫자 동일 |

### 7.3 영문 축약 허용 범위

분량이 큰 한국어 원문을 1:1 번역하면 영문이 덜 자연스러울 수 있음. 허용:
- Docker compose, 긴 코드 블록: 한국어 판 참조 안내 가능
  `(See Korean edition Chapter 10.1.2 for full content — identical.)`

단, 핵심 **서술/알고리즘/API 계약**은 완전 번역 필수.

---

## 8. 코드 블록 규약

### 8.1 언어 태그 필수

```markdown
```typescript
export const foo = 'bar';
```
```

pandoc syntax highlighting 동작. 언어 태그 없으면 단색.

### 8.2 긴 코드는 핵심만

500+ line 파일 전체 복사 대신:

```typescript
// src/lib/services/nc.ts (축약)
export async function reconcile(reportId: string) {
  // 1. 노트에서 셀 추출
  // 2. 기존 auto_from_note 조회
  // 3. Reconciliation 6-case
  // 4. seq_no 재채번
  // ...
}
// 전체: `docs/06-report-system.md §3.4.2`
```

### 8.3 다이어그램은 ASCII art

Mermaid는 pandoc이 자동 렌더링 안 함. ASCII art로 고정:

```
┌──────────┐      ┌──────────┐
│ Client   │ ───▶ │ Server   │
└──────────┘      └──────────┘
```

복잡한 다이어그램은 미리 SVG/PNG 생성 후 이미지 삽입.

---

## 9. 표 사용 (열거/매핑에 적극)

텍스트 나열 대신 표 사용:

```markdown
| 항목 | 값 | 설명 |
|-----|---|------|
| DB  | PostgreSQL 16 | Docker self-host |
| Port | 10311 | 127.0.0.1 only |
```

특히 다음에 적합:
- 환경변수 목록
- 에러 코드 정의
- API 엔드포인트 목록
- 역할·권한 매트릭스
- 의존성·버전 표

---

## 10. 부록 필수 섹션

### 10.1 전체 문서 목록

```markdown
| No | 문서 | 라인 | 핵심 |
|----|-----|------|-----|
| 01 | overview | 311 | ... |
| 02 | spec | 716 | ... |
| ... | | | |
| **합계** | | **11,826** | |
```

### 10.2 환경변수

```bash
# 카테고리별 정렬
DATABASE_URL=...
NEXTAUTH_URL=...
# ...
```

### 10.3 주요 명령어

```bash
# 개발
npm run dev

# 테스트
npm test

# 배포
docker compose pull
```

### 10.4 약어집

```markdown
| 약어 | 의미 |
|-----|-----|
| SAP | Samsung Standard Registrar Auditor Platform |
| ISO | International Organization for Standardization |
| ... | ... |
```

### 10.5 참고 링크

```markdown
- GitHub: `github.com/...`
- Next.js: https://nextjs.org/docs/app
- ...
```

### 10.6 재생성 가이드

```bash
cd docs/book
./generate.sh
```

---

## 11. 서문 (Preface) 필수 요소

```markdown
# 서문

본서는 **<프로젝트명>**의 <X>을 <Y 목적>으로 다룬 <Z> 문서이다.

## 대상 독자

- ...
- ...

## 본서의 위상

...

## 버전 이력

| 버전 | 시점 | 주요 변경 |
|-----|-----|---------|
| v1.3 | YYYY-MM-DD | ... |
| v1.4 | YYYY-MM-DD | ... |

## 표기 규약

- **FN-XX-NNN**: 기능 ID
- **§N.M**: 섹션 번호
- `docs/NN-name.md §M.P`: 원문 참조
```

---

## 12. 흔히 빠지는 함정

### 12.1 섹션 번호 불일치

**증상**: `§3.4 참조`라 썼는데 실제는 §3.4가 없거나 다른 내용.

**예방**: 완성 후 모든 교차 참조를 grep으로 확인:
```bash
grep -oE '§[0-9]+(\.[0-9]+)*' book.md | sort -u
```

### 12.2 원문 없는 내용을 임의 창작

**증상**: 원문에 없는 정보를 "일반적으로는..."으로 지어냄.

**예방**: 한 번 작성 후 원문과 비교. 없는 내용은 추측 금지.

### 12.3 이모지 / 특수문자

**증상**: 🤖, ☑ 같은 이모지가 xelatex에서 `missing character` 경고.

**예방**: 본문 이모지 제거. 헤더·표 기호도 `✅`, `❌` 같은 유니코드 대신 `[O]`, `[X]` 등 ASCII.

### 12.4 한/영 분량 극단 차이

**증상**: 한국어 4000줄인데 영문은 1000줄.

**예방**: 축약 허용되는 구간은 본문에 명시. 핵심 장은 완전 번역 목표.

### 12.5 TOC 누락

**증상**: 생성된 PDF에 TOC가 없음.

**예방**: `--toc --toc-depth=2` 항상 포함. MD에 수동 TOC 작성 금지 (중복).

---

## 13. 검증 체크리스트

완성 후:

- [ ] 모든 장 번호 한/영 일치
- [ ] 모든 `§N.M` 참조 유효
- [ ] 이모지 0개 본문
- [ ] 코드 블록 언어 태그 모두 있음
- [ ] 커버 페이지 정상 렌더링
- [ ] TOC 자동 생성
- [ ] 부록 6개 섹션 (문서목록/env/명령어/약어/링크/재생성) 모두 포함
- [ ] PDF 페이지 번호 표시
- [ ] DOCX 스타일 (제목/본문) 일관
