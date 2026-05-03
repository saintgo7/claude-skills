---
description: 'SearCam 개발기 기술 서적 챕터 작성/업데이트 (한국어·영어 병렬 저술). 사용 시점 — "searcam book", "searcam chapter", "ch01"~"ch24", "기술 서적 챕터", "병렬 저술", "parallel authoring", "KO EN 동시 작성", "docs/book chapter", "make en-md". 챕터 매핑표 + KO/EN 템플릿 + 빌드 명령 (make md/en-md/both) 포함.'
model: sonnet
---

# SearCam Book Chapter Writer

SearCam 개발기 기술 서적의 챕터를 **한국어와 영어로 동시에** 작성하거나 업데이트합니다.

## 병렬 작성 원칙

> 번역이 아닌 **병렬 저술(parallel authoring)**입니다.
> 같은 내용을 두 언어의 독자에게 맞게 각각 직접 씁니다.
>
> - 한국어: 구어체 존댓말, 비유 → 기술 설명 순서
> - 영어: Active voice, conversational but professional tone
> - 코드 블록: 양쪽 모두 **영어 주석** 사용 (코드는 언어가 없으므로 통일)
> - 분량: 한국어 5,000~8,000자 / 영어 2,500~4,000 words (같은 내용, 언어 특성 차이 반영)

## 챕터 매핑표

| 챕터 | KO 파일 | EN 파일 | 참조 문서 |
|------|---------|---------|----------|
| Ch01 | ch01-problem-discovery.md | same | 01-PRD.md |
| Ch02 | ch02-prd.md | same | 01-PRD.md |
| Ch03 | ch03-trd-architecture.md | same | 02-TRD.md |
| Ch04 | ch04-system-architecture.md | same | 04-system-architecture.md |
| Ch05 | ch05-ui-ux-design.md | same | 09-ui-ux-spec.md |
| Ch06 | ch06-security-design.md | same | 14-security-design.md |
| Ch07 | ch07-test-strategy.md | same | 18-test-strategy.md |
| Ch08 | ch08-database-design.md | same | 07-db-schema.md |
| Ch09 | ch09-data-flow.md | same | 05-data-flow.md |
| Ch10 | ch10-project-setup.md | same | 02-TRD.md (기술 스택) |
| Ch11 | ch11-wifi-scan.md | same | 03-TDD.md (Layer 1) |
| Ch12 | ch12-lens-detection.md | same | 03-TDD.md (Layer 2) |
| Ch13 | ch13-emf-detection.md | same | 03-TDD.md (Layer 3) |
| Ch14 | ch14-cross-validation.md | same | 03-TDD.md (교차 검증) |
| Ch15 | ch15-ui-implementation.md | same | 09-ui-ux-spec.md |
| Ch16 | ch16-room-implementation.md | same | 07-db-schema.md |
| Ch17 | ch17-pdf-report.md | same | — |
| Ch18 | ch18-testing.md | same | 18-test-strategy.md |
| Ch19 | ch19-cicd.md | same | 19-cicd-pipeline.md |
| Ch20 | ch20-release.md | same | — |
| Ch21 | ch21-monitoring.md | same | 21-monitoring.md |
| Ch22 | ch22-legal-privacy.md | same | 17-privacy-impact.md |
| Ch23 | ch23-revenue-gtm.md | same | — |
| Ch24 | ch24-retrospective.md | same | — |

*파일명은 KO/EN 동일, 저장 경로만 다름.*

## 저장 위치

```
docs/book/
├── chapters/       ← 한국어 챕터
│   └── chXX-*.md
└── chapters-en/    ← 영어 챕터 (같은 파일명)
    └── chXX-*.md
```

## 챕터 작성 프로세스

1. **목표 챕터 파악**: `$ARGUMENTS`에서 챕터 번호/주제 확인
2. **소스 읽기**: 해당 챕터의 참조 문서 읽기
3. **기존 내용 확인**: KO/EN 양쪽 기존 파일 확인
4. **병렬 작성**: KO 파일 → EN 파일 순서로 동시에 작성
5. **빌드 확인**: `make md && make en-md` 실행 (병합 검증)

## 한국어 챕터 템플릿

```markdown
# Ch[번호]: [제목]

> **이 장에서 배울 것**: [한 줄 요약]

## 도입

[왜 이 장이 중요한가 — 독자가 겪는 문제/상황에서 시작]
[SearCam 프로젝트에서 이 단계가 어떤 의미인지]

## [주요 개념 1]

[핵심 개념 설명 — 비유 먼저, 기술 설명 후]

### SearCam 적용 사례

[실제 프로젝트 코드/설계/결정 과정]

```kotlin
// English comments in code blocks
class Example {
    fun doSomething(): Result { ... }
}
```

## [주요 개념 2]

...

## 실습 과제

> **실습**: [따라할 수 있는 구체적 과제]

**목표**: ...  
**힌트**: ...  
**예상 결과**: ...

## 핵심 정리

| 개념 | 요점 |
|------|------|
| ... | ... |

**이 장의 핵심**:
- ✅ ...
- ✅ ...
- 하면 안 되는 것: ...

## 다음 장 예고

[다음 챕터로 자연스럽게 연결]

---
*참고 자료*: [docs/ 문서 링크]
```

## 영어 챕터 템플릿

```markdown
# Ch[Number]: [Title]

> **What you'll learn**: [One-line summary]

## Introduction

[Start with the problem the reader faces, not theory]
[What this chapter means in the context of SearCam]

## [Core Concept 1]

[Explain with a real-world analogy first, then go technical]

### How SearCam Does It

[Actual code, design decisions, and trade-offs from the project]

```kotlin
// English comments in code blocks
class Example {
    fun doSomething(): Result { ... }
}
```

## [Core Concept 2]

...

## Hands-On Exercise

> **Exercise**: [A concrete task the reader can follow]

**Goal**: ...  
**Hint**: ...  
**Expected outcome**: ...

## Chapter Summary

| Concept | Key Takeaway |
|---------|-------------|
| ... | ... |

**Key points from this chapter**:
- ...
- ...
- What NOT to do: ...

## What's Next

[Natural bridge to the next chapter]

---
*References*: [docs/ file links]
```

## 빌드 명령

```bash
# 한국어만
make md && make docx

# 영어만
make en-md && make en-docx

# 둘 다 (병렬 빌드)
make both
```

## 사용법

`$ARGUMENTS` 예시:
- `"Ch11 Wi-Fi 스캔 구현 챕터 작성"` → KO + EN 동시 신규 작성
- `"Ch15 UI 구현 챕터 업데이트 — HomeScreen 추가됨"` → KO + EN 동시 업데이트
- `"Ch18 en만 업데이트"` → 영어 챕터만 업데이트
- `"전체 챕터 현황 확인"` → KO/EN 작성 진행률 테이블 출력
