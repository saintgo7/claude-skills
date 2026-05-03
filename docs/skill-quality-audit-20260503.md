# Skill Description Quality Audit — 2026-05-03

`claude-skills` 저장소 58개 skill (skill 57 + slash-command 1) 의 frontmatter `description` 품질을
정량 측정하고 약한 description 을 보강한 결과 보고서.

품질 기준:
- **트리거 phrase 5개 이상** (따옴표로 묶인 자동 invocation 키워드)
- **사용 시점 / when to 명시**
- **description 길이 1024자 이하** (frontmatter limit)
- **description 길이 100자 이상** (지나치게 짧지 않음)

## 1. 전체 통계 (after boost)

| 항목 | 수치 |
|---|---|
| 총 skill | 58 |
| 평균 description 길이 | 268 자 |
| 중앙값 description 길이 | 238 자 |
| 최소 / 최대 길이 | 156 / 576 자 |
| 평균 트리거 phrase | 7.4 |
| 중앙값 트리거 phrase | 7 |
| 최소 / 최대 트리거 phrase | 5 / 13 |
| **1024자 초과 (limit 위반)** | **0** |
| **트리거 phrase 5개 미만** | **0** |
| **100자 미만** | **0** |
| **사용 시점/when to 누락** | **0** |

## 2. 약한 description 발견 + 보강 결과

audit 시 **2건** 의 약한 description 을 식별 (5개 미만 트리거, 사용 시점 누락).

| skill | 위치 | 이전 trigger | 이전 length | 이후 trigger | 이후 length | 비고 |
|---|---|---|---|---|---|---|
| `exam-system` | `exam-system/SKILL.md` | 0 | 511 | 13 | 521 | TRIGGER 텍스트만 있고 인용된 phrase 없음 → 따옴표 phrase 13개 + 사용 시점 형식 통일 |
| `searcam-book` | `commands/searcam-book.md` | 0 | 39 | 11 | 256 | 한 줄짜리 description → 사용 시점 + 11 phrase + 빌드 명령 추가 |

### Before / After 예시

**`exam-system` (before):**
```
Flask-based online exam system template with anti-cheat, per-student time gating,
and exam-day operational tooling. TRIGGER when the user wants to build, deploy, or
operate an online exam/quiz/test system; ...
```

**`exam-system` (after):**
```
Flask 기반 온라인 시험 시스템 템플릿 + 시험일 운영 도구 (anti-cheat, per-student
시간 게이팅, 실시간 모니터링). 사용 시점 — "online exam", "quiz system",
"exam timing", "grace period", "shuffle questions", "anti-cheat", "tab switching",
"copy paste block", "fullscreen exam", "F12 block", "extend deadline",
"live exam monitoring", "submission stats". 66명 대학 중간고사 운영 검증
(92% 제출률). SKIP: 시험과 무관한 일반 프로그래밍.
```

**`searcam-book` (before):**
```
SearCam 기술 서적 챕터 작성/업데이트 — 한국어·영어 병렬 작성
```

**`searcam-book` (after):**
```
SearCam 개발기 기술 서적 챕터 작성/업데이트 (한국어·영어 병렬 저술). 사용 시점 —
"searcam book", "searcam chapter", "ch01"~"ch24", "기술 서적 챕터",
"병렬 저술", "parallel authoring", "KO EN 동시 작성", "docs/book chapter",
"make en-md". 챕터 매핑표 + KO/EN 템플릿 + 빌드 명령
(make md/en-md/both) 포함.
```

## 3. 트리거 phrase 분포

| 트리거 phrase 수 | skill 수 | 비율 |
|---|---|---|
| 0 | 0 | 0% |
| 1–4 | 0 | 0% |
| 5–7 | 36 | 62% |
| 8–10 | 20 | 35% |
| 11+ | 2 | 3% |

전 skill 이 추천 최소치 5+ 충족.

## 4. 권장 (다음 라운드 후보)

다음 skill 은 트리거 phrase 가 정확히 5개로 권장 최소치 (5–7) 의 하단:

| skill | 트리거 수 | description 길이 | 보강 권장 |
|---|---|---|---|
| `deployment-checklist` | 5 | 168 자 | 트리거 phrase 2-3 추가 권장 |
| `korean-tech-blog-authoring` | 5 | 156 자 | 트리거 phrase 2-3 추가 권장 |

이번 라운드는 **한도 위반/긴급 약점만 처리**한 atomic 보강이며 borderline (5 trig) 은 다음 라운드에 별도로 검토.

## 5. 검증 방법

```bash
cd /home/jovyan/claude-skills
python3 - <<'PY'
import yaml, re
from pathlib import Path
paths = sorted(Path('.').glob('*/SKILL.md')) + [
    p for p in Path('commands').glob('*.md') if p.name != 'README.md'
]
for p in paths:
    text = p.read_text()
    if not text.startswith('---'): continue
    fm = yaml.safe_load(text[3:text.find('---',3)])
    desc = fm.get('description','') if fm else ''
    trigs = re.findall(r'"([^"]+)"', desc)
    name = (fm.get('name','') or p.parent.name) if fm else p.stem
    if len(trigs) < 5 or len(desc) > 1024 or len(desc) < 100:
        print(f"WEAK: {name} trig={len(trigs)} len={len(desc)}")
PY
```

위 스크립트 출력 0줄이면 audit 통과.

## 6. 결론

- **58 skill 모두 품질 기준 통과**
- 약한 description 2건 → 즉시 보강 (atomic commit)
- 1024자 한도 위반 0건
- 평균 트리거 phrase 7.4 (중앙값 7) 로 자동 invocation 친화적
