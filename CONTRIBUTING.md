# Contributing to claude-skills

Claude Code skill을 추가하거나 기존 skill을 개선하는 가이드.

## TL;DR

```bash
# 1. fork + clone
git clone https://github.com/<you>/claude-skills.git
cd claude-skills

# 2. 새 skill 디렉토리 + SKILL.md
mkdir my-skill
cat > my-skill/SKILL.md << 'EOF'
---
name: my-skill
description: 'When to invoke. Trigger phrases: "...", "...". Brief role.'
---

# my-skill
...
EOF

# 3. install.sh REGISTRY에 한 줄 추가
# REGISTRY=( ... "my-skill|skill|간단한 설명" )

# 4. PR
git checkout -b add-my-skill
git add my-skill/ install.sh
git commit -m "feat: add my-skill"
git push origin add-my-skill
```

## Skill 형식

### 디렉토리 구조

```
my-skill/
├── SKILL.md              # 필수 — frontmatter + 본문
├── scripts/              # 선택 — 보조 셸 스크립트
│   └── *.sh
├── templates/            # 선택 — 파일 템플릿 (예: project-bootstrap)
│   └── ...
├── CHECKLIST.md          # 선택 — 사용자 체크리스트
└── README.md             # 선택 — GitHub에서 보일 README (SKILL.md와 별개)
```

### SKILL.md frontmatter

```yaml
---
name: skill-name
description: 'When to invoke this skill. Trigger phrases: "phrase 1", "phrase 2", "...". One-sentence role description. Optional context about scope.'
---
```

규칙:
- **`name`**: 소문자/숫자/하이픈만, 최대 64자, install.sh REGISTRY와 일치
- **`description`**: 최대 1024자. **트리거 phrase 5~10개** 명시 — Claude Code가 이 description을 읽고 언제 자동 invocation할지 판단
- description에 콜론(:) 들어가면 quote로 감싸야 함 (`'`로)

### 본문 구조 권장

```markdown
# skill-name

한 줄 요약 (이 skill이 무엇을 하는지).

## When to use
- "트리거 phrase 1"
- "트리거 phrase 2"
- 구체 시나리오

## 핵심 명령 / 코드

(가장 자주 쓰이는 한 줄 명령부터)

## 옵션 / 변형

## 흔한 문제

| 증상 | 해결 |
|---|---|

## 관련 skill

- `다른-skill` — 이때 사용
```

길이는 50~300줄 권장. 너무 길면 SKILL.md를 짧게 유지하고 추가 자료를 같은 디렉토리의 별도 파일로 (CHECKLIST.md, scripts/*).

## install.sh REGISTRY 등록

새 skill을 추가하면 `install.sh`의 `REGISTRY` 배열에 한 줄 추가:

```bash
REGISTRY=(
  ...
  "my-skill|skill|짧은 설명 (REGISTRY는 한 줄 — 멀티라인 X)"
  # type: "skill" → ~/.claude/skills/<name>/
  # type: "command" → ~/.claude/commands/<name>.md
)
```

`./install.sh --list`로 노출되며, sparse checkout으로 가벼운 설치 가능.

## 좋은 skill의 조건

✅ **명확한 트리거** — description에 "이런 발화일 때 사용" 5~10개 phrase
✅ **재현 가능한 명령** — 본문에 `bash <command>` 형식의 실제 동작하는 명령
✅ **흔한 함정** — 사용 시 부딪힐만한 에러 + 해결책
✅ **다른 skill과의 경계** — "이건 X-skill이 아니라 Y-skill로" 구분
✅ **버전/의존성 명시** — Pandoc 3.x, vLLM 0.19+ 등 검증된 조합

❌ 트리거 phrase 없음 (Claude Code가 언제 invocation할지 모름)
❌ 추상적 — "가이드라인" 같은 일반론 (실제 명령 없음)
❌ 너무 길어서 800줄 — 분할 또는 보조 파일로

## 새 skill 아이디어

이 repo에 환영하는 skill 카테고리:

- **인프라 운영** — Cloudflare Tunnel, K8s pod, GPFS 등
- **빌드 파이프라인** — Pandoc bilingual, LaTeX 학회 템플릿, mermaid 자동화
- **LLM 운영** — vLLM 변종, FastAPI gateway 패턴, OpenAI 호환 프록시
- **데이터 작업** — pandas/duckdb 워크플로, ML pipeline
- **문서/저작** — 기술서적 챕터 작성, API 문서 자동 생성
- **시험/평가 운영** — exam-system 스타일

각 skill은 *실제 운영해 본 경험*을 바탕으로 작성하면 가치가 큼.

## 변경 검증

skill 변경 후 검증:

```bash
# YAML frontmatter 유효성
python3 -c "
import yaml
from pathlib import Path
text = Path('my-skill/SKILL.md').read_text()
end = text.find('---', 3)
fm = yaml.safe_load(text[3:end])
print(f'name={fm[\"name\"]}, desc={len(fm[\"description\"])}자')
"

# install.sh REGISTRY 일치
./install.sh --list | grep my-skill
```

## PR 가이드

- 한 PR에 한 skill (대규모 변경은 여러 PR로)
- commit 메시지 prefix: `feat(my-skill):`, `fix(my-skill):`, `docs(my-skill):`
- 변경 이유 + 검증 방법을 PR description에

## 라이선스

기여한 코드/문서는 MIT 라이선스로 배포됩니다.

## 도움 / 질문

- Issues: https://github.com/saintgo7/claude-skills/issues
- 한국어/영어 모두 OK

감사합니다 — 더 많은 사람이 Claude Code의 skill 시스템을 잘 활용할 수 있도록.
