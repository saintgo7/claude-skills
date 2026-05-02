---
name: project-bootstrap
description: 'bilingual research/code 프로젝트를 한 번에 자동 부트스트랩. GitHub repo 생성 + Cloudflare 서브도메인 + 한/영 개발 책 (Pandoc/LaTeX, ~500p 골격) + 한/영 연구개발 논문 (KCI + IEEE 템플릿) + Mermaid 다이어그램 빌드 + plan/specs/decisions 골격을 한 번에. 사용 시점 — "새 프로젝트 시작", "프로젝트 부트스트랩", "프로젝트 init", "한영 책 같이", "논문 템플릿 자동", "GEM-LLM 같은 구조로 새로 시작", "research-project init". 인자: 프로젝트 이름 + 선택적 도메인. master 노드 cloudflared/gh 자격증명을 자동 사용 (saintgo7).'
---

# project-bootstrap

GEM-LLM 같은 *bilingual code+research* 프로젝트를 **한 명령**으로 부트스트랩.

## 한 줄 사용

```bash
bash ~/.claude/skills/project-bootstrap/scripts/init-project.sh <project-name> [domain]
# 예시:
bash ~/.claude/skills/project-bootstrap/scripts/init-project.sh fishing-llm fishing.pamout.com
```

자동으로 수행:
1. **GitHub** `saintgo7/<project-name>` Private repo 생성 (master의 gh 자격증명 사용)
2. **Cloudflare** `<domain>` DNS 라우팅 (master cloudflared 통해)
3. **디렉토리 구조** `src/`, `docs/`, `plan/`, `tests/`, `scripts/`, `_trash/`, `_logs/`
4. **한국어 책** `docs/book-ko/` — 5 Part × 18 Chapter, OUTLINE.md + 챕터 stub
5. **영문 책** `docs/book-en/` — 동일 구조 mirror
6. **한국어 논문** `docs/paper-ko/` — KCI 12p, sections + references.bib
7. **영문 논문** `docs/paper-en/` — IEEE/ACM 12p, sections + bib
8. **40 Mermaid 다이어그램** 카탈로그 stub
9. **Pandoc 빌드 파이프라인** Makefile + scripts/build-docs.sh + LaTeX 템플릿 (xeCJK, IEEEtran)
10. **plan/** 12 SPEC + 3 ADR + master roadmap 골격
11. **첫 commit + push**
12. **메모리** project_<name>.md 자동 작성

## 사용 시점 (트리거)

- "새 프로젝트 시작" / "research-project init"
- "한/영 책 같이 만들어"
- "논문도 한/영 둘 다 자동"
- "GEM-LLM 같은 구조로 fishing-llm 만들어"
- "프로젝트 부트스트랩"
- "한 번에 GitHub + Cloudflare + 책 + 논문"

## 사전 조건

- master 노드 SSH 가능 (`ssh master 'hostname'` OK)
- master에 `gh` 인증되어 있음 (`ssh master 'gh auth status'`)
- master에 cloudflared 인증되어 있음 (도메인 사용 시)
- n1에서 git push 가능 (`~/.git-credentials` 또는 PAT)
- Pandoc, XeTeX, mermaid-cli, chromium libs 설치됨 (gem-llm 셋업 후 자동 만족)

## 단계별 실행 (수동)

자동 스크립트 대신 단계별로 하려면:

```bash
SKILLDIR=~/.claude/skills/project-bootstrap

# Step 1: 디렉토리 + 템플릿 복사
PROJECT=fishing-llm
DEST=/home/jovyan/wku-vs-01-datavol-1/$PROJECT
mkdir -p $DEST
cp -r $SKILLDIR/templates/* $DEST/
ln -sfn $DEST /home/jovyan/$PROJECT

# Step 2: 프로젝트 이름 일괄 치환
find $DEST -type f \( -name "*.md" -o -name "*.tex" -o -name "*.yaml" -o -name "Makefile" -o -name "*.sh" \) \
  -exec sed -i "s/__PROJECT__/$PROJECT/g; s/__PROJECT_TITLE__/${PROJECT^^}/g" {} +

# Step 3: GitHub repo 생성 + push
cd $DEST
git init && git add -A && git commit -m "feat: initial $PROJECT bootstrap"
ssh master "gh repo create saintgo7/$PROJECT --private --description '$PROJECT bootstrapped'"
git remote add origin "https://github.com/saintgo7/$PROJECT.git"
git push -u origin main

# Step 4: Cloudflare DNS (도메인 사용 시)
DOMAIN=fishing.pamout.com
N1_TUNNEL=$(grep "^tunnel:" ~/.cloudflared/config.yml | awk '{print $2}')
ssh master "cloudflared tunnel route dns $N1_TUNNEL $DOMAIN"
# n1 cloudflared config.yml에 ingress 추가 필요 (아래 참조)
```

## 산출물

부트스트랩 직후 디렉토리:

```
$PROJECT/
├── .github/
├── README.md
├── Makefile
├── docs/
│   ├── book-ko/
│   │   ├── OUTLINE.md
│   │   ├── parts/{part-1..5}/
│   │   └── parts/appendix/
│   ├── book-en/ (mirror)
│   ├── manual-ko/, manual-en/
│   ├── paper-ko/sections/ + references.bib
│   ├── paper-en/sections/ + references.bib
│   ├── diagrams/ (40 stubs + CATALOG.md)
│   └── build/{out,templates,filters} (Makefile 빌드 산출물)
├── plan/
│   ├── roadmap/MASTER_PLAN.md
│   ├── specs/SPEC-{01..12}-*.md (스텁)
│   └── decisions/ADR-{001..003}-*.md
├── src/, tests/, scripts/
├── _trash/, _logs/, _data/
└── .gitignore
```

## 빌드 명령 (자동 생성됨)

```bash
make book-ko book-en          # 한/영 책 PDF
make manual-ko manual-en      # 한/영 매뉴얼 PDF
make paper-ko paper-en        # 한/영 논문 PDF (KCI + IEEE)
make all                      # 전체 6 PDF (4 포맷 = 24 산출물)
make diagrams                 # 40 Mermaid → SVG
make clean                    # docs/build/out → _trash/
```

## n1 cloudflared ingress 추가 (수동 단계)

도메인 사용 시 `~/.cloudflared/config.yml`에 ingress 추가:

```yaml
- hostname: <domain>
  service: http://localhost:<port>
```

그 후 cloudflared 재시작:
```bash
kill -TERM $(pgrep -f "cloudflared.*tunnel.*run")
nohup ~/.local/bin/cloudflared tunnel --config ~/.cloudflared/config.yml \
  run research-portal-n1 > ~/cloudflared-n1.log 2>&1 &
```

## 검증

부트스트랩 후 1분 검증:

```bash
cd ~/<project-name>
make diagrams        # 40 SVG 빌드
make book-ko         # 책 PDF 빌드 (작은 stub 본문)
ls docs/build/out/   # PDF/DOCX/TEX/MD 산출물
gh repo view saintgo7/<project-name>  # GitHub 정상
curl -s https://<domain>/  # 외부 (Gateway 띄워야 200, 미가동이면 502 정상)
```

## 메모리 자동 작성

스크립트가 다음 메모리 파일을 추가:
- `project_<name>.md` (정적 사실 — 도메인, GitHub URL, 디렉토리)
- `project_<name>_runtime.md` (가동 상태 추후 수동 업데이트)

`MEMORY.md` 인덱스도 자동 추가.

## 참조 자료

- `templates/` — 모든 stub/template 원본
- `scripts/init-project.sh` — 통합 부트스트랩
- `scripts/setup-github.sh`, `setup-cloudflare.sh`, `setup-docs.sh` — 단계별 분리
- `CHECKLIST.md` — 부트스트랩 후 수동 확인 사항

## 제약

- `rm -rf` 절대 미사용 (정책)
- 기존 같은 이름 디렉토리 있으면 `_trash/<name>-old-<ts>/`로 mv 후 진행
- master SSH 실패 시 GitHub/Cloudflare 단계 skip + 수동 안내

## 관련 skill

- `gem-llm-overview` — 기존 GEM-LLM 시스템 (이 skill의 직계 부모)
- `gem-llm-cloudflare-tunnel` — Cloudflare 운영
- `gem-llm-build-docs` — Pandoc 빌드 깊이
- `gem-llm-troubleshooting` — 빌드 실패 13개 패턴
