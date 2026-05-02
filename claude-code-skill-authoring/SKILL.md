---
name: claude-code-skill-authoring
description: 'Claude Code skill 작성 메타 가이드 — 좋은 SKILL.md 형식, 트리거 phrase 5~10개, REGISTRY 등록, install/uninstall 사이클, CI validation. 사용 시점 — "skill 만들기", "SKILL.md 작성", "트리거 phrase", "claude-skills 추가", "skill scaffolding", "skill 검증", "메타 skill", "새 skill 부트스트랩". 32+ skill 작성 경험에서 검증된 패턴 — 평균 147줄, sweet spot 200~300줄, frontmatter 1024자 제약, REGISTRY 단일 라인 등록.'
---

# claude-code-skill-authoring

Claude Code skill을 **작성하는** skill — 32+ skill 작성에서 검증된 패턴 모음.

## 사용 시점

- "skill 만들기" / "새 skill 추가"
- "SKILL.md 어떻게 써?"
- "트리거 phrase 작성법"
- "claude-skills repo에 기여"
- "skill scaffolding"
- "skill validation 실패"
- "REGISTRY 등록 까먹음"
- "install/uninstall 사이클 검증"

## 다른 skill과의 경계

| Skill | 다루는 범위 |
|---|---|
| `CONTRIBUTING.md` | PR 워크플로 (fork → branch → PR) |
| **이 skill** | 기술 가이드 (frontmatter 디테일, scaffold, 검증) |
| `multi-agent-orchestrator` | skill 본문에 들어갈 내용 (작성 전 dispatch 패턴) |

CONTRIBUTING은 *어떻게 PR 보내나*, 이 skill은 *어떻게 좋은 SKILL.md 만드나*.

## 1. 좋은 skill의 5조건

✅ **명확한 트리거** — description에 발화 phrase 5~10개
✅ **재현 가능한 명령** — `bash <command>` 형식, copy-paste 동작
✅ **흔한 함정** — 사용 시 부딪힐 에러 + 해결책
✅ **다른 skill 경계** — "이건 X-skill로, 이건 Y-skill로"
✅ **검증된 의존성** — Pandoc 3.x, vLLM 0.19+ 등 실측 조합

❌ 트리거 phrase 없음 → Claude Code가 invocation 못 함
❌ 추상적 일반론 → 실제 명령 없음
❌ 800줄 초과 → 분할 또는 보조 파일로

## 2. SKILL.md 구조 (필수 섹션)

```markdown
---
name: <name>           # 소문자/숫자/하이픈, max 64자
description: '...'     # 1024자 이내, 트리거 phrase 포함
---

# <name>

(한 줄 요약)

## 사용 시점
- "phrase 1"
- "phrase 2"
...

## 핵심 명령

(가장 자주 쓰이는 한 줄 명령부터)

## 옵션 / 변형

## 흔한 함정

| 증상 | 해결 |
|---|---|

## 관련 skill

- `다른-skill` — 이때 사용
```

길이 권장 **50~300줄**. 평균 147줄, sweet spot **200~300**.

## 3. 트리거 phrase 작성법

description의 트리거 phrase가 Claude Code의 자동 invocation 키. 잘 작성된 예시:

```yaml
description: '...사용 시점 — "병렬로 작업", "여러 에이전트로", "한 번에 빠르게",
  "대량 문서 작성", "전체 멀티 에이전트로", "8 에이전트 동시", "ultrathink 병렬"...'
```

규칙:
- 사용자가 **자연스럽게 말할 phrase** (기술 용어 X)
- 5~10개 다양한 표현
- 한국어 + 영문 혼용 가능
- description에 콜론(`:`) 들어가면 quote (`'`)로 감싸기

❌ `"trigger phrase invocation pattern"` — 너무 기술적
✅ `"병렬로 작업", "한 번에 빠르게", "ultrathink 병렬"` — 실제 발화

## 4. install.sh REGISTRY 등록 (3 단계)

새 skill 추가 시 **반드시** 3 단계 모두:

1. **디렉토리 생성** (`<name>/`)
2. **SKILL.md 작성** (frontmatter + 본문)
3. **install.sh REGISTRY 한 줄 추가**

```bash
REGISTRY=(
  ...
  "<name>|skill|짧은 설명 (한 줄, 멀티라인 X)"
)
```

`type`:
- `skill` → `~/.claude/skills/<name>/`
- `command` → `~/.claude/commands/<name>.md`

CI는 REGISTRY ↔ 디렉토리 일치를 자동 검증 — 빠뜨리면 PR 빨간불.

## 5. scaffold.sh로 부트스트랩

```bash
bash scripts/scaffold.sh <skill-name> "<one-line-description>"
```

자동 생성:
- `<skill-name>/` 디렉토리
- `SKILL.md` (frontmatter + 빈 섹션)
- `README.md` (GitHub 표시용)

생성 후 다음 단계 안내 출력:
```
다음 단계:
  1. SKILL.md 본문 작성
  2. install.sh REGISTRY에 추가:
     "<name>|skill|<description>"
  3. git add, commit, push
```

## 6. CI validation (자동, .github/workflows/validate.yml)

push/PR 시 자동 검증:

| 체크 | 실패 조건 |
|---|---|
| frontmatter `name` | 디렉토리 이름과 불일치 |
| frontmatter `description` | 1024자 초과 |
| frontmatter `name` 길이 | 64자 초과 |
| YAML 파싱 | unclosed `---`, parse error |
| bash 문법 | `bash -n` 실패 |
| REGISTRY ↔ 디렉토리 | 등록은 했는데 디렉토리 없음 (또는 그 반대) |

로컬에서 미리:
```bash
python3 -c "
import yaml
from pathlib import Path
text = Path('<my-skill>/SKILL.md').read_text()
end = text.find('---', 3)
fm = yaml.safe_load(text[3:end])
print(f'name={fm[\"name\"]}, desc={len(fm[\"description\"])}자')
"
```

## 7. install/uninstall 사이클 검증 (PR 전 필수)

```bash
# 격리된 HOME으로 install 테스트
mkdir -p /tmp/test-$$
HOME=/tmp/test-$$ ./install.sh <name>
ls /tmp/test-$$/.claude/skills/<name>/  # SKILL.md 있어야 정상

# uninstall 테스트
HOME=/tmp/test-$$ ./install.sh --remove <name>
ls /tmp/test-$$/.claude/skills/  # 디렉토리 없어야 정상

# 정리
rm -rf /tmp/test-$$
```

`./install.sh --list`로 새 skill이 노출되는지도 확인.

## 8. PR 가이드 (CONTRIBUTING.md 참조)

- 한 PR에 한 skill (대규모는 분할)
- commit prefix: `feat(<name>):`, `fix(<name>):`, `docs(<name>):`
- PR description: 변경 이유 + 검증 방법
- 한국어/영어 모두 OK

## 9. 흔한 함정

| 증상 | 원인 / 해결 |
|---|---|
| CI 빨간불: `description too long` | 1024자 초과 → phrase 압축 또는 본문으로 이동 |
| CI 빨간불: `name != directory` | frontmatter `name`과 디렉토리 이름 불일치 |
| YAML parse error | description에 콜론(`:`) 있는데 quote 누락 → `'...'`로 감싸기 |
| install.sh 변경 후 CI 실패 | REGISTRY 등록은 했는데 디렉토리 없음 (또는 반대) |
| 자동 invocation 안 됨 | 트리거 phrase 부족/모호 → 5~10개 자연 발화로 |
| 본문 800줄 초과 | SKILL.md는 코어만, 디테일은 `scripts/`, `CHECKLIST.md`로 분할 |

## 10. 좋은 skill 사례 (이 repo의 baseline)

| Skill | 줄 수 | 특징 |
|---|---|---|
| `multi-agent-orchestrator` | 208 | 검증 사례 표 + 핵심 원칙 + 안티패턴 |
| `vllm-tool-calling` | 192 | 3단계 디펜스 + 케이스 일반화 + 템플릿 |
| `bilingual-book-authoring` | 307 | 1000p 검증 + Part 멀티에이전트 |
| `bash-cli-best-practices` | 233 | 8 검증 패턴 + SQL injection 방지 |

평균 **147줄**, sweet spot **200~300줄**.

## 자기 참조 패턴

이 skill은 *skill을 작성하는 skill*. 본인을 포함해 모든 skill에 같은 검증이 적용됨:
- 이 SKILL.md도 frontmatter 1024자 이내
- name `claude-code-skill-authoring`이 디렉토리 이름과 일치
- REGISTRY에 본인 등록

## 관련 skill / 문서

- `CONTRIBUTING.md` — PR 워크플로 (fork → branch → PR)
- `multi-agent-orchestrator` — skill 본문에 dispatch 패턴 넣을 때
- `bash-cli-best-practices` — scaffold.sh 작성 시 8 패턴 참조
- `.github/workflows/validate.yml` — CI 검증 로직 원본
