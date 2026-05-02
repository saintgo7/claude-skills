# project-bootstrap CHECKLIST

부트스트랩 직후 확인 사항.

## ✅ 자동 완료 (init-project.sh)

- [ ] 디렉토리 구조 (`src/`, `docs/`, `plan/`, `tests/`, `scripts/`, `_trash/`, `_logs/`, `_data/`)
- [ ] 심볼릭 링크 `~/<project>` → `/home/jovyan/wku-vs-01-datavol-1/<project>`
- [ ] `.gitignore`
- [ ] `README.md`
- [ ] Git init + 첫 commit
- [ ] GitHub `saintgo7/<project>` 생성 + push (master SSH 가능 시)
- [ ] Cloudflare DNS 라우팅 (도메인 지정 시)
- [ ] 메모리 `project_<name>.md` 작성 + MEMORY.md 인덱스

## 🔧 수동 단계 (필요 시)

### 1. n1 cloudflared ingress 추가 (도메인 사용 시)

`~/.cloudflared/config.yml`에 다음 항목 추가 (Gateway 포트는 프로젝트마다 다름):

```yaml
- hostname: <domain>
  service: http://localhost:<port>
```

cloudflared 재시작:
```bash
kill -TERM $(pgrep -f "cloudflared.*tunnel.*run")
nohup ~/.local/bin/cloudflared tunnel --config ~/.cloudflared/config.yml \
  run research-portal-n1 > ~/cloudflared-n1.log 2>&1 &
```

### 2. 첫 챕터 본문 채우기

```bash
cd ~/<project>
# 한국어 책 Part I Chapter 1
vim docs/book-ko/parts/part-1/01-introduction.md
# 영문 mirror
vim docs/book-en/parts/part-1/01-introduction.md
# 논문
vim docs/paper-ko/sections/01-introduction.md
vim docs/paper-en/sections/01-introduction.md
```

### 3. SPEC/ADR 작성

```bash
vim plan/specs/SPEC-01-architecture.md
vim plan/decisions/ADR-001-*.md
vim plan/roadmap/MASTER_PLAN.md
```

### 4. 시스템 의존성 (한 번만 — 다른 프로젝트와 공유)

```bash
sudo apt install -y texlive-xetex texlive-publishers texlive-lang-cjk \
  texlive-fonts-recommended fonts-noto-cjk fonts-noto-cjk-extra librsvg2-bin
npm install -g @mermaid-js/mermaid-cli  # nvm npm 권장
# Chrome libs (mermaid puppeteer): libatk-bridge2.0-0 libatk1.0-0 libcups2 libdrm2 libgbm1 libgtk-3-0 libnspr4 libnss3 libxcomposite1 libxdamage1 libxfixes3 libxkbcommon0 libxrandr2 libpango-1.0-0 libcairo2 libasound2t64 libxshmfence1
```

### 5. 빌드 검증

```bash
make diagrams           # 40 Mermaid → SVG (chromium 필요)
make book-ko book-en    # 한/영 책 PDF
make paper-ko paper-en  # 논문 PDF
make all                # 6 targets × 4 formats = 24 산출물
```

## 🐛 흔한 문제

| 증상 | 해결 |
|---|---|
| `make book-ko` 실패: missing IEEEtran | `sudo apt install texlive-publishers` |
| Mermaid SVG 빌드 실패: libatk | Chrome libs 설치 (위 4번) |
| 한글 폰트 없음 | `sudo apt install fonts-noto-cjk` |
| GitHub push 실패: 401 | master에서 `gh auth login` 또는 PAT 재발급 |
| Cloudflare DNS 추가 실패 | master에서 `cloudflared tunnel route dns ...` 직접 |

## 📚 다음 단계 (대형 프로젝트)

### 코드 부트스트랩 (선택)

GEM-LLM 같은 LLM 시스템이면:
```bash
mkdir src/{vllm-serve,gateway,cli,admin-ui,common}
# Gateway: FastAPI + SQLAlchemy + alembic
# CLI: prompt_toolkit + rich + typer
# Admin UI: Jinja2 + HTMX
```

연구 프로젝트면:
```bash
mkdir src/{data,models,training,evaluation,utils}
```

### 멀티에이전트 워크플로

대량 본문 작성 필요 시 (책 ~500p × 2 언어):
```
Agent #1 (general-purpose): Part I+II 한국어 본문
Agent #2: Part III 한국어
Agent #3: Part IV+V+부록
Agent #4-6: 영문 mirror 동일 분할
Agent #7: 논문 한국어 본문
Agent #8: 논문 영문 본문
```

## 📦 산출물 GitHub

자동:
- 첫 commit 메시지: `feat: initial <project> bootstrap`
- main 브랜치
- Private repo (saintgo7 namespace)

전환 (필요 시):
```bash
gh repo edit saintgo7/<project> --visibility public  # private → public
```
