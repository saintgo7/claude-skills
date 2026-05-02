---
name: multi-agent-orchestrator
description: 'Claude Code에서 대량 작업(책 1000p, 코드 12K LOC, 문서 50개)을 8+ 에이전트 병렬 디스패치로 빠르게 완료하는 패턴. 사용 시점 — "병렬로 작업", "여러 에이전트로", "한 번에 빠르게", "대량 문서 작성", "전체 멀티 에이전트로", "8 에이전트 동시", "ultrathink 병렬". GEM-LLM 부트스트랩에서 검증된 패턴 — 에이전트별 출력 경로 지정, 200~400단어 요약 보고, 컨텍스트 폭발 방지, 라운드별 동기화.'
---

# multi-agent-orchestrator

Claude Code의 `Agent` tool로 **8+ 에이전트를 병렬 디스패치**해 대량 작업을 빠르게 완료하는 검증된 패턴.

## 검증된 사례 (GEM-LLM 부트스트랩)

| 라운드 | 에이전트 수 | 산출물 | 시간 |
|---|---|---|---|
| #1 | 4 (Explore) | vLLM/CLI/Pandoc/Skills 4 영역 조사 보고 | 5분 |
| #2 | 3 (general-purpose) | 16 SPEC/ADR + 7 OUTLINE + 9 vLLM 스크립트 (32 파일) | 15분 |
| #3 | 4 (general-purpose) | mermaid 빌드 + Gateway + CLI + 빌드 파이프라인 (123 파일) | 18분 |
| #4 | 4 (general-purpose) | Skills/MCP/Hooks + Admin UI + 매뉴얼 KO+EN | 25분 |
| #5 | 6 (general-purpose) | 책 KO 4개 Part + 논문 KO/EN + 통합 테스트 | 30분 (rate limit) |
| #6-7 | 6+ | 영문 책 + PDF 빌드 + 검증 등 | 누적 |

**총 산출물**: 코드 ~12K LOC, 문서 ~64K LOC, 295+ 파일, 9 Git commits.
**단일 에이전트 시도 시 예상**: 8~12배 길어짐 (rate limit + 컨텍스트 폭발).

## 핵심 원칙

### 1. 에이전트별 출력 경로 명시

❌ "SPEC 12개 작성해" — 어디 저장할지 모호
✅ "SPEC 12개를 다음 정확한 절대경로에 Write 도구로 저장: `/path/SPEC-01-architecture.md` ... `/path/SPEC-12-testing-qa.md`"

### 2. 200~400 단어 요약 보고 강제

각 에이전트 prompt 끝에:
> **완료 후 보고 (300단어 이내):**
> - 작성한 파일 수와 라인 수
> - 추측한 부분
> - 다음 단계에서 채울 placeholder 위치

이유: 에이전트가 *작성한 파일 전체*를 메인 컨텍스트로 가져오면 폭발. 요약만 메인 메모리에.

### 3. subagent_type 선택

| Type | 권장 사용 |
|---|---|
| `Explore` | 빠른 read-only 조사 (코드 위치, 패턴 검색) |
| `Plan` | 설계 검토 (단, **read-only** — 파일 작성 X) |
| `general-purpose` | **파일 작성 포함 모든 작업** (가장 자주 사용) |
| `claude-code-guide` | Claude Code/SDK/API 사용법 질문 |

⚠️ **`Plan` 함정**: read-only이라 SPEC/문서 *작성* 못 함. SPEC 12개 같은 산출물 작업은 **반드시 `general-purpose`**.

### 4. 한 응답에 여러 Agent 호출

✅ Claude Code는 한 응답 안의 여러 `Agent` tool 호출을 **자동 병렬**:

```
한 응답 안에 8개 Agent tool 호출 → 8개 에이전트 동시 실행
```

❌ 8개 응답에 1개씩 호출 → 순차

## 디스패치 패턴

### 패턴 A — 영역 분할 (Domain Sharding)

큰 산출물을 도메인별로 쪼개기:

```
Agent #1: SPEC + ADR + roadmap (계획 영역)
Agent #2: 책 OUTLINE + 다이어그램 카탈로그 (목차 영역)
Agent #3: vLLM launch 스크립트 + healthcheck (인프라 영역)
```

각 에이전트 산출물이 *서로 의존하지 않게* 분할.

### 패턴 B — Part 분할 (Length Sharding)

1000p 책을 Part별로:

```
Agent #1: Part I (~80p)
Agent #2: Part II (~100p)
Agent #3: Part III (~150p)
Agent #4: Part IV+V+부록 (~170p)
```

**중요**: 모든 에이전트가 *같은 OUTLINE.md, 같은 다이어그램 ID, 같은 SPEC*을 참조하도록 prompt 시작에 명시.

### 패턴 C — 언어 Mirror

한/영 동시 작성:

```
Agent KO: 한국어 책 Part I~V
Agent EN: 영문 책 Part I~V (한국어 mirror, *직역 아님 — 자연스러운 영어*)
```

영문 에이전트 prompt: "한국어 챕터의 *content depth*는 동일하되 직역하지 말고 자연스러운 영어로. 다이어그램 ID는 동일."

### 패턴 D — 검증 분할

산출물 + 검증 분리:

```
Agent #1-3: 실제 산출물 (코드/문서)
Agent #4: 통합 테스트 작성
Agent #5: 빌드/lint 검증
```

## 흔한 함정

| 함정 | 회피 |
|---|---|
| Plan agent로 파일 작성 시도 | `subagent_type=general-purpose` 사용 |
| 에이전트가 같은 파일에 동시 쓰기 | 출력 경로를 디렉토리 단위로 분할 |
| 모델명/포트/API 형식 등 인터페이스 불일치 | prompt에 *공유 사실* 표 형식으로 명시 |
| 컨텍스트 폭발 (에이전트가 전체 보고) | "300단어 이내 요약" 명시 |
| Rate limit 도달 (~5+ 에이전트 30분 작업) | 에이전트 수 줄이거나 30분 후 재개 |
| 다이어그램 ID 충돌 | "diagram-NN, NN+1, ... 만 사용" 명시적 분배 |

## 디스패치 prompt 템플릿

```
Agent({
  description: "<5단어 짧은 설명>",
  subagent_type: "general-purpose",
  prompt: """<task 설명>

**먼저 읽어야 할 컨텍스트:**
- /path/to/SPEC.md (인터페이스 정의)
- /path/to/OUTLINE.md (목차)

**출력 파일 (정확한 경로):**
1. /path/to/file-1.md
2. /path/to/file-2.md
...

**전제 조건 (반드시 반영):**
- 환경: ...
- 모델: ...
- 포트: ...

**스타일:**
- 학습 목표 박스, 요점 정리 박스
- 코드 ≤ 60줄/블럭

**제약:**
- rm -rf 금지 (mv ... _trash/)
- 모든 type hints

**완료 후 보고 (300단어 이내):**
- N개 파일 라인 수
- 사용 다이어그램 ID
- 추측한 부분
"""
})
```

## 라운드 단위 진행

**1라운드 = 한 응답 + 동시 에이전트들의 완료 대기**.

라운드 사이에 사용자가 결정해야 할 게 있으면 라운드 종료 후 질문. 자율 진행 모드면 다음 라운드 자동 시작.

라운드 #1: 조사 → #2: 골격 → #3: 본체 → #4: 검증 → #5: 빌드 → #6: commit.

## 실패 케이스 처리

에이전트가 실패하면:
1. 에러 보고 분석
2. *같은 에이전트 type으로 재디스패치* 안 함 — 같은 실패 반복 가능
3. `subagent_type` 변경 또는 prompt 명확화 후 재시도
4. 여전히 실패 → 메인 에이전트가 직접 처리

GEM-LLM 사례:
- Plan agent → general-purpose 전환으로 SPEC 작성 성공 (case 7)
- 같은 작업을 다르게 분할해 재디스패치

## Rate Limit 대응

Anthropic Claude API rate limit:
- 5+ 에이전트 × 30분 작업이면 도달 가능
- 도달 시: 30~60분 후 자동 리셋
- `ScheduleWakeup` tool로 30분 후 자동 재개 가능

작업이 멈추면 *완료된 산출물은 보존*되니 손실 없음. wakeup 후 남은 작업만 다시 디스패치.

## ultrathink 모드와 함께

사용자가 `ultrathink` 키워드 사용하면 메인 에이전트가 더 깊이 사고 — 이 패턴과 결합:

> **ultrathink** — 사용자가 깊은 분석 + 멀티 에이전트 병렬 둘 다 원함. 한 응답에 8 에이전트 디스패치 + 각자에게 *깊은 사고* 지시.

## 실용 체크리스트

새 멀티 에이전트 라운드 전:

- [ ] 작업을 N개 독립 영역으로 쪼갤 수 있나 (의존성 없음)
- [ ] 각 영역의 출력 경로가 다른가 (충돌 없음)
- [ ] 공유 컨텍스트(SPEC, OUTLINE, 다이어그램 ID)를 prompt에 포함했나
- [ ] subagent_type이 적절한가 (Plan 아니라 general-purpose)
- [ ] "300단어 이내 보고" 명시했나
- [ ] rate limit 여유가 있나 (이전 라운드에서 30분+ 지난 경우 OK)

## 관련 skill

- `project-bootstrap` — 프로젝트 시작 시 (이 skill 사용 가능)
- 책/논문 대량 작성에서 이 패턴 핵심
