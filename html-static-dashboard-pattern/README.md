# html-static-dashboard-pattern

Grafana 부재 환경에서 정적 HTML 헬스 대시보드를 만드는 검증된 패턴.
bash + curl + nvidia-smi + cron 조합, 한 파일로 끝.

- `SKILL.md` — 11 섹션 가이드 (사용 시점, 데이터 수집, XSS 회피, 다크 테마, 흔한 함정).
- `templates/dashboard.sh.template` — 환경변수로 일반화된 생성 스크립트.
- `templates/dashboard-style.css.template` — Catppuccin 다크/라이트 테마.

검증: gem-llm 라운드 70 `scripts/health-dashboard.sh` (144 lines, 8 섹션, 5분 cron, 28일 운영).

설치: `./install.sh html-static-dashboard-pattern`
