---
name: production-postmortem-pattern
description: '운영 사고 postmortem (사후분석) 검증된 패턴. 사용 시점 — "post-mortem", "사후분석", "incident report", "RCA", "case study", "근본 원인 분석", "사고 회고", "blameless", "교훈 정리". 7-section 형식 (영역/시점/증상/근본원인/해결/예방/교훈) + 액션 아이템 추적 + 책 case 통합.'
---

# production-postmortem-pattern

운영 사고 postmortem (사후분석)을 일관된 형식으로 작성/추적/내재화하는 패턴. 사고 1건이 1회성 디버깅으로 끝나지 않고 — 7-section 형식으로 정리되고, 액션 아이템이 추적되고, 패턴이 skill로 추출되고, 책 case study로 외부에 공유되도록 만든다. gem-llm 책 16장 case 1-20 (총 53시간 사고)의 사후분석에서 검증된 형식이다.

## 1. 사용 시점

- 운영 장애 (5xx 폭증, 타임아웃, OOM)
- 데이터 손실 / 손상 (DB wipe, 부분 손실)
- 보안 사고 (key 유출, 인증 우회)
- silent bug (사용자에게 빈 결과/잘못된 응답)
- 성능 회귀 (p99 SLO 위반)
- CVE / 취약점 대응 (patch 후)
- 사용자 지표 영향 (가입 실패, 결제 실패)
- 분기/주간 회고에서 "왜 같은 사고 반복?"

## 2. 7-section 형식 (gem-llm book 검증)

| 섹션 | 1줄 정의 | 작성 팁 |
|---|---|---|
| 영역 | 코드/환경/설정/운영/사용자 | 다음 절 분류표 참조 |
| 시점 | YYYY-MM-DD HH:MM (UTC) | 사고 발생 + 감지 + 복구 3 timestamp |
| 증상 | 사용자에게 보인 것 | 로그 한 줄, 사용자 인용 |
| 근본 원인 | 5-Why 끝점 | "사람" 금지 — §3 |
| 해결 | 즉시 조치 | commit hash + 명령어 |
| 예방 | 재발 방지 | 테스트/모니터링/skill |
| 교훈 | 패턴 1줄 | 다른 시스템에 일반화 가능한 명제 |

영역 분류 (gem-llm 20 cases):

| 영역 | 건수 | 예시 |
|---|---|---|
| 코드 | 10 | silent bug, dispatch 누락, 라우트 mismatch |
| 환경 | 3 | 라이브러리 버전 충돌, GPU OOM |
| 설정 | 3 | K-EXAONE CoT 토큰 미설정 |
| 운영 | 2 | SQLite WAL `mv`, validate-all DB wipe |
| 사용자 실수 | 2 | 잘못된 API key, CLI 옵션 오용 |

## 3. 5-Why 적용

근본 원인은 "사람"이 아니라 "시스템"에서 찾는다. "Alice가 잘못 입력했다"는 1-Why일 뿐이다.

```
증상: validate-all 실행 후 모든 DB row 사라짐
1-Why: Alice가 prod DB에서 validate-all 실행
2-Why: validate-all 스크립트가 환경변수 DB_URL 무조건 덮어쓰지 않음
3-Why: pytest fixture가 setdefault 사용 (이미 있으면 skip)
4-Why: 운영 환경변수가 테스트 컨테이너에 leak
5-Why: container 환경 분리 패턴이 정립되지 않음
근본 원인: env-isolation pattern 부재 → env-isolation-pattern skill로 추출
```

5-Why를 4-5 깊이까지 끌고 가야 시스템 원인이 드러난다. gem-llm 평균 깊이는 4.2.

## 4. blameless 작성

| 나쁜 표현 | 좋은 표현 |
|---|---|
| "Alice가 코드 잘못 작성" | "PR 리뷰 단계 회귀 검증 부재" |
| "Bob이 prod에서 실수" | "prod/test 환경 분리 미비" |
| "사용자가 매뉴얼 안 읽음" | "CLI가 위험 명령에 confirm 없음" |
| "이번엔 운이 나빴다" | "monitoring이 X 시점에 부재" |

기준: 같은 환경/도구에 다른 사람을 두면 같은 사고가 발생할 가능성이 있는가? Yes → 시스템 원인. blameless는 "책임 회피"가 아니라 "재발 방지의 정확도"를 위한 것.

## 5. 액션 아이템 추적

postmortem이 "회의 후 잊혀짐"으로 끝나지 않으려면 표 형식 + 측정 가능 + 마감 + 담당 1인.

| # | 항목 | 담당 | 마감 | 상태 |
|---|---|---|---|---|
| 1 | env-isolation skill 작성 | @alice | 2026-05-10 | done |
| 2 | validate-all 스크립트 confirm 추가 | @bob | 2026-05-08 | open |
| 3 | CI에 env leak detection 추가 | @carol | 2026-05-15 | wip |

원칙:
- 담당 1인 (둘 이상이면 책임 분산)
- 마감 7-14일 이내 (장기는 쪼갠다)
- 측정 가능한 완료 조건 (PR merged / commit hash)
- 주간 미팅에서 open 상태만 점검

## 6. 책 case study 통합

postmortem (사내 위키, 회사 정보 포함) → 책 case (외부, 익명화). 7-section 형식이 그대로 옮겨진다.

변환 규칙:
- 회사명/팀명/담당자 익명화 ("@alice" → "팀원 A")
- 내부 URL/IP 제거
- commit hash는 OSS repo면 공개 가능 (gem-llm은 saintgo7/gem-llm 공개)
- 날짜는 분기 단위로 일반화 ("2026-Q2") 또는 그대로
- 사용자 데이터/key는 항상 redact

`templates/case-study-book.md.template` 참조. 책 case는 7-section을 그대로 유지하되 "교훈" 섹션을 강화 (독자가 다른 시스템에 적용할 수 있게).

## 7. RCA 도구

| 카테고리 | 도구 | 용도 |
|---|---|---|
| 이슈 추적 | GitHub Issues / Linear / Jira | 사고 티켓 + 액션 아이템 |
| 메트릭 | Grafana 사고 시점 스냅샷 | p99/에러율 시계열 |
| 로그 | ELK / Loki / CloudWatch Logs | 5분 전후 grep |
| 트레이싱 | OpenTelemetry / Sentry | 분산 호출 체인, 예외 stack |
| 데이터 | DB backup 시점 비교 | row 손실 범위 측정 |
| 코드 | git bisect / blame | 회귀 도입 commit 식별 |

postmortem 작성 시 "근본 원인" 섹션에 도구 출력 인용 (Grafana 스크린샷, Loki 쿼리 결과, commit URL).

## 8. blameless 문화

postmortem이 "처벌 회피용 형식"이 되지 않으려면 문화가 받쳐줘야 한다.

- 팀 미팅에서 공유 (15-30분, RCA 발표 + Q&A)
- 사고 → 패턴 → skill 추출 (gem-llm: case 18 → env-isolation-pattern, case 19 → shell-cli-dispatch-pattern, case 20 → api-route-consistency-pattern)
- 신규 입사자 onboarding에 case 모음 포함 ("이 사고들을 알면 같은 지뢰 안 밟음")
- "사고 발견자 칭찬" 명문화 — silent bug 감지가 가장 어렵다
- 매니저는 "누가 잘못?"이 아니라 "어떤 시스템 결함?"만 묻는다

## 9. gem-llm 검증 통계 (메타 인사이트)

20 cases / 53 hours 누적 사고 시간 분석:

- 영역 분포: 코드 50% / 환경 15% / 설정 15% / 운영 10% / 사용자 실수 10%
- 평균 5-Why 깊이: 4.2 (4-Why 미만은 시스템 원인 미도달)
- "사람" 근본 원인: **0건** — 모두 시스템 원인으로 재정의
- 액션 아이템 평균: 3.5개/case
- 새 skill 추출: case → skill 70% (14/20)
- 재발 사고: 1건 (case 18 후 같은 패턴 1회 — 재발 후 skill 작성으로 종결)
- 평균 복구 시간: 2.6시간 (감지 → 복구)

가장 비싼 case (시간):
1. case 18 (env leak, validate-all DB wipe): 8시간
2. case 6 (vLLM 의존성 mismatch): 6시간
3. case 14 (K-EXAONE CoT 미출력): 5시간

## 10. 흔한 함정

| 함정 | 결과 | 회피 |
|---|---|---|
| postmortem이 "누가 잘못?" 회의 | 정보 은폐, 재발 | blameless 명문화, 매니저 가드 |
| 액션 아이템 추적 X | 6개월 후 같은 사고 | 표 + 담당 + 마감 + 주간 점검 |
| 같은 사고 재발 | 신뢰 하락 | skill 추출 + onboarding 포함 |
| 책에 그대로 옮김 | 회사 정보 유출 | 익명화 체크리스트 (§6) |
| 5-Why 2-깊이로 멈춤 | "사람" 원인으로 끝남 | 4 이상 강제, 리뷰어가 "왜?" 추가 |
| TL;DR 누락 | 미팅에서 30분 설명 | 3줄 요약 + timeline 표 |
| 단일 사고만 보고 패턴 못 봄 | 같은 영역 반복 | 분기별 메타 분석 (§9) |

## 11. 관련 skill

- `bilingual-book-authoring` — 책 case study 통합 (한/영 동시)
- `shell-cli-dispatch-pattern` — case 19 일반화 (sub-cmd dispatch 누락)
- `api-route-consistency-pattern` — case 20 일반화 (4-way 라우트 일관성)
- `env-isolation-pattern` — case 18 일반화 (운영 → 테스트 leak)
- `cicd-github-actions-pattern` — 액션 아이템 자동 검증 CI
- `claude-code-skill-authoring` — case → skill 추출 메타 가이드

## 빠른 시작

```bash
mkdir -p docs/postmortems
cp ~/.claude/skills/production-postmortem-pattern/templates/postmortem.md.template \
   docs/postmortems/2026-05-03-incident-name.md
# 7 section 채움 + 액션 아이템 표 + PR로 review
```

책 통합 시:

```bash
cp ~/.claude/skills/production-postmortem-pattern/templates/case-study-book.md.template \
   book/ko/16-case-study/case-21.md
# 익명화 후 7-section 그대로 이전
```
