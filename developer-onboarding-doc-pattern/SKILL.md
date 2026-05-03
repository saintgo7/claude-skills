---
name: developer-onboarding-doc-pattern
description: '신규 개발자 0→실행 onboarding 문서 작성 패턴 (README + QUICKSTART + INDEX). 사용 시점 — "developer onboarding", "신규 입사", "0 to running", "5분 quickstart", "처음 시작", "git clone 부터", "first run guide", "README 구조". 5분 quickstart + 검증 + 상세 가이드 + FAQ + 트러블슈팅.'
---

# developer-onboarding-doc-pattern

신규 개발자가 `git clone` 부터 첫 실행까지 도달하는 onboarding 문서 묶음의 표준 패턴.
README / QUICKSTART / INDEX / docs 4-tier 구조 + 5분 검증 + FAQ + 트러블슈팅 표.

## 1. 사용 시점

- 신규 입사자가 첫 주에 0 → 실행까지 가는 가이드 작성
- 새 환경에서의 setup 가이드 (로컬 / staging / production)
- `git clone` 부터 first hello world 까지의 step-by-step
- 외부 contributor 첫 PR 가이드 (open source onboarding)
- 인수인계 문서 (전임자 → 후임자)

## 2. 4-tier 구조

| Tier | 문서 | 분량 | 목적 | 독자 시간 |
|---|---|---|---|---|
| 1 | `README.md` | 1 page | 한 화면에 무엇 / 누구 / 왜 / 시작 링크 | 1분 (스캔) |
| 2 | `QUICKSTART.md` | 5분 | git clone → first run → 검증 | 5분 (실행) |
| 3 | `docs/*.md` (deep) | 30분~ | 상세 절차 / 운영 / 아키텍처 | 깊게 |
| 4 | `INDEX.md` | 1 page | 모든 자산 카탈로그 (책 / 매뉴얼 / 코드 / skill) | 1분 (참조) |

핵심 원칙: **각 tier 는 단일 책임을 가진다.** README 가 5분 quickstart 까지 다 담으면 길어진다.
QUICKSTART 가 운영 상세까지 가면 5분 안에 안 끝난다. 분리.

## 3. README.md 표준 구조 (한 화면)

```
1. 한 줄 요약 (badge / live URL)
2. 시스템 아키텍처 (mermaid / ASCII 1개)
3. 5분 Quickstart (3-5 명령)
4. 검증된 메트릭 (성능 표 / 테스트 카운트)
5. 산출물 / 카탈로그 (책 / 매뉴얼 / skill 수)
6. 운영 도구 (CLI / 대시보드 표)
7. CI/CD 상태 (배지 / 최근 run)
8. 관련 문서 (QUICKSTART / INDEX / docs/ 링크)
```

전체 1 page (스크롤 1-2 번). 더 길면 잘라서 docs/ 로 보낸다.

## 4. QUICKSTART.md (5분 안에 끝나야 함)

`git clone` → install → run → 검증, 5 단계 이내. 각 단계는 4-tuple 로 (`playbook-authoring-pattern` 참고).

```
Step N (X min) — <목적 요약>
  [목적]      이 단계에서 무엇을 달성하는가
  [명령]      복붙 가능한 명령
  [기대출력]  실행 직후 보여야 할 것
  [실패시]    가장 흔한 실패 + 1줄 해결
```

5단계가 넘어가면 분리하거나 docs 로 옮긴다.

## 5. 검증 단계 (사용자가 성공했는지 한 줄로 확인)

quickstart 마지막에 반드시 확인 명령 한 줄:

```bash
curl http://localhost:8080/healthz
# 기대: HTTP 200, "ok"
```

검증 없이 끝나면 "되긴 한 건가?" 가 첫 슬랙 질문이 된다.

## 6. 한 줄 요약 (헤더) 작성법

- 무엇을 / 누구에게 / 왜 가치 (1-2 줄, 마케팅/기술 균형)
- 추상 X, 구체 수치 O
- 좋은 예: "GEM-LLM is a Qwen Coder dual-model coding assistant on 8×B200, OpenAI-compatible Gateway with 50-user concurrent verified production-ready system."
- 나쁜 예: "An AI system that helps developers." (무엇이? 누구에게?)

## 7. 시스템 아키텍처 다이어그램

mermaid 또는 ASCII art. 한 화면에 들어가게.

```
[User] → [Gateway:8000] → [vLLM-A:8001]
                       → [vLLM-B:8002]
```

3-7 개 박스 / 5-10 개 화살표. 더 복잡하면 docs/architecture.md 로.
참고: `mermaid-diagram-authoring`.

## 8. 검증된 메트릭 표 (믿음 단서)

추상 X. 구체 수치만.

| 동접 | 성공률 | RPS | p99 (ms) |
|---|---|---|---|
| 50 | 100% | 12.3 | 9100 |
| 100 | 99.8% | 22.7 | 18500 |

테스트 카운트, uptime, 운영 일수, 사용자 수도 동일.

## 9. 산출물 / 카탈로그

- 책 / 매뉴얼 / 논문 PDF 페이지 수
- skills 카운트 + 링크
- 테스트 카운트 (passing / total)
- INDEX.md 로 전체 자산 일람

INDEX.md 가 단일 진실의 출처(SoT).

## 10. FAQ (5-10 Q&A, 입사 첫 주에 묻는 것)

- Q1: 비용 얼마나 드나? (라이선스 / 클라우드 / GPU)
- Q2: 의존성? OS는? Python 버전?
- Q3: 운영 중 가장 흔한 트러블 5 가지
- Q4: 다음에 읽어야 할 문서 (학습 경로)
- Q5: 누구한테 물어보면 되나? (담당자 / 슬랙 채널)

답은 짧게 (3-5 줄). 길면 docs 링크.

## 11. 흔한 함정

| 증상 | 원인 | 해결 |
|---|---|---|
| README 너무 김 (5+ 스크롤) | 모든 걸 한 화면에 | tier 분리, docs/ 로 이동 |
| QUICKSTART 첫 명령 실패 | 사전 조건 명시 X | pre-flight 추가 (의존성 check) |
| 검증 단계 없음 | 성공 신호 X | curl healthz 추가 |
| 한 줄 요약 모호 | "AI 시스템" 같은 추상 | 구체 (8×B200, 50 동접) |
| 문서 사이 cross-reference X | 길 잃음 | tier 표 + INDEX.md |
| 한국어/영어 mix | 일관성 X | 한 문서 = 한 언어 |
| 다이어그램 없음 | 텍스트만 | mermaid/ASCII 1개 필수 |
| 메트릭 추상 ("빠르다") | 수치 없음 | 표 (RPS, p99, 동접) |
| INDEX 없음 | 자산 흩어짐 | 단일 카탈로그 SoT |
| FAQ 없음 | 첫 주 슬랙 폭주 | 5-10 Q&A 미리 답 |

## 12. 관련 skill

- `bilingual-book-authoring` — 한/영 동시 책 저작 (deep tier 문서)
- `playbook-authoring-pattern` — 4-tuple 절차서 작성 (QUICKSTART 단계 디테일)
- `mermaid-diagram-authoring` — 아키텍처 다이어그램
- `claude-code-skill-authoring` — skill 자체 onboarding

## 템플릿

- `templates/README.md.template` — Tier 1 한 화면 README
- `templates/QUICKSTART.md.template` — Tier 2 5분 quickstart

```bash
cp ~/.claude/skills/developer-onboarding-doc-pattern/templates/README.md.template README.md
cp ~/.claude/skills/developer-onboarding-doc-pattern/templates/QUICKSTART.md.template QUICKSTART.md
```

`<PROJECT>`, `<repo>`, `<install command>` 같은 placeholder 를 프로젝트에 맞게 치환.
