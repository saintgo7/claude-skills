---
name: html-static-dashboard-pattern
description: '정적 HTML 헬스 대시보드 (Grafana 부재 대안) 검증된 패턴. 사용 시점 — "Grafana 없음", "정적 대시보드", "K8s pod cron 안 됨", "HTML 한 페이지 모니터링", "5분 갱신", "헬스 + GPU + 메트릭 통합", "운영 모니터 lightweight". bash + curl + nvidia-smi + grid layout + XSS 회피.'
---

# html-static-dashboard-pattern

Grafana / Prometheus / Loki 가 없거나 K8s pod 환경 때문에 무거운 스택을 못 띄우는
프로젝트에서 한 화면짜리 운영 대시보드를 **정적 HTML 한 파일**로 만드는 패턴.
bash + curl + nvidia-smi + cron(또는 supervisor hook) 만으로 충분하다.

검증: gem-llm 라운드 70 `scripts/health-dashboard.sh` (144 lines, 8 섹션,
5분 cron 갱신, llm.pamout.com 운영 28일).

---

## 1. 사용 시점

- **Grafana / Prometheus 미가동** — 단일 노드, 운영자 1~2명, 풀 옵저버빌리티 스택은 과함.
- **K8s pod / 컨테이너** — systemd 없음, cronie 미설치, web UI 한 페이지가 가장 빠름.
- **빠른 운영 가시성** — 스마트폰에서 새벽에 한 번 새로 고쳐 보면 끝.
- **정적 자산만 외부 노출 가능** — Cloudflare Tunnel + nginx 로 HTML 한 파일만 흘려보낼 때.
- **postmortem 첨부** — 사고 시점 스냅샷을 그대로 git 에 커밋해 둘 수 있음.

반대로 **시계열 알림 / drilldown / 다차원 필터** 가 필요하면 Grafana 로 가야 한다.
관련: `observability-bundle` (Prom+Loki+OTel), `prometheus-fastapi-metrics`.

---

## 2. 정적 vs 동적 대시보드 비교

| 옵션 | 셋업 비용 | 의존성 | 시계열 | 알림 | 적합 |
|------|----------|--------|--------|------|------|
| Grafana + Prom | 높음 | DB + scrape | O | O | 팀 운영, SLO |
| **정적 HTML (이 패턴)** | **5분** | bash + curl | X (스냅샷) | X | 1~2인 운영, K8s pod |
| Streamlit / Dash | 중간 | Python 데몬 | O | X | 데이터 탐색 |
| Metabase / Superset | 높음 | DB 커넥터 | O | O | BI / 대시보드 빌더 |

정적 HTML 의 강점은 "**파일 하나**" 라는 단순성 — 백업, 외부 노출, 사고 첨부 모두 쉽다.

---

## 3. 데이터 수집

`templates/dashboard.sh.template` 참고. 8개 표준 섹션:

1. **supervisor / 프로세스 상태** — `supervisor.sh status`, `systemctl`, `ps -ef | grep`.
2. **GPU** — `nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader,nounits`.
3. **외부 tunnel / endpoint** — `curl -s -m 5 -o /dev/null -w "%{http_code} (%{time_total}s)" $URL`.
4. **사용자 / API key 카운트** — `admin-cli list-users | jq length`.
5. **시스템 리소스** — `uptime` (load), `free -h` (RAM), `df -h` (disk).
6. **Prometheus /metrics** — `curl -s localhost:8080/metrics | grep -E '^(my_app_requests|...)\b' | head -20`.
7. **최근 git commits** — `git log --oneline -5` (gem-llm + claude-skills 두 repo).
8. **메타** — 생성 시각 (UTC), hostname, refresh 링크.

**원칙**:
- 모든 외부 명령은 `2>/dev/null || true` 또는 fallback 텍스트 — 실패해도 페이지가 망가지지 않도록.
- `curl -m 5` (timeout) 필수, 안 그러면 cron 이 hang.
- jq, awk 같은 의존성은 `command -v` 로 확인하고 없으면 plain text fallback.

---

## 4. HTML 생성 (heredoc)

bash heredoc 으로 한 번에 출력. 외부 템플릿 엔진 안 쓴다 (의존성 늘리지 말 것).

```bash
cat > "$OUTPUT" <<HTML
<!DOCTYPE html>
<html lang="ko"><head><meta charset="UTF-8"><title>$TITLE</title>
<style>$(cat templates/dashboard-style.css)</style>
</head><body>
<h1>$TITLE</h1>
<div class="grid">
  <div><h2>1. Supervisor</h2><pre>$SUPERVISOR</pre></div>
  <div><h2>2. GPU</h2><table>$GPU_TABLE</table></div>
  ...
</div>
</body></html>
HTML
```

CSS Grid (`grid-template-columns: 1fr 1fr`) 로 2열 레이아웃, 800px 이하 1열로 떨어뜨림.

---

## 5. XSS 회피 (필수)

외부 명령 출력 = 신뢰 못 함. 반드시 escape:

```bash
html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

SUPERVISOR=$(supervisor.sh status 2>&1 | html_escape || true)
LOAD=$(uptime | awk -F'load average: ' '{print $2}' | html_escape)
```

**암묵적 위험**:
- log 출력에 사용자가 만든 식별자 (이메일, key 이름, prompt) 가 섞여 들어감 → `<script>` 주입 가능.
- `git log` 메시지도 제3자가 PR 로 넣은 텍스트 — escape 필수.
- 숫자만 들어가는 필드 (port, count) 도 습관적으로 escape — 미래에 string 으로 바뀌어도 안전.

`&` → `&amp;` 가 **첫 번째** 여야 함 (그렇지 않으면 `<` → `&lt;` 의 `&` 가 다시 escape 되어 깨짐).

---

## 6. 자동 갱신

### cron (호스트 / VM)
```cron
*/5 * * * * /home/user/scripts/dashboard.sh /var/www/html/health.html >/dev/null 2>&1
```

### supervisor hook (K8s pod, cron 없음)
`supervisor.sh start` 끝에 background loop 추가:
```bash
( while true; do bash scripts/dashboard.sh /tmp/health.html; sleep 300; done ) &
```
관련: `k8s-cron-alternatives` skill 의 watchdog / s6-cron 패턴.

### inotify / on-event
변경 이벤트 (예: 사용자 추가) 가 잦지 않으면 cron 5분이 가장 단순.

---

## 7. 다중 페이지 / 시계열 확장

스냅샷만으론 부족하면:
1. **history.csv 추가 기록** — `dashboard.sh` 끝에 한 줄 append (`timestamp,gpu_util,ram_used,...`).
2. **JS chart** — `<script src="https://cdn.jsdelivr.net/npm/chart.js">` + `fetch('history.csv')`.
3. **다중 페이지** — `health-detail.html`, `health-billing.html`, 메인에서 링크.

단, 이 시점에 Grafana 가 더 싸진다 — 시계열 50개 넘으면 패턴 갈아탈 것.

---

## 8. 다크 / 라이트 테마

Catppuccin Mocha 팔레트 (이 skill 의 `dashboard-style.css.template`).
`prefers-color-scheme` 쿼리로 자동 전환:

```css
:root { --bg: #1e1e2e; --fg: #cdd6f4; --accent: #89b4fa; }
@media (prefers-color-scheme: light) {
  :root { --bg: #eff1f5; --fg: #4c4f69; --accent: #1e66f5; }
}
body { background: var(--bg); color: var(--fg); }
```

---

## 9. 권한 / 노출

정적 HTML 은 어떤 web server 든 띄울 수 있다:
- **nginx / Caddy** — `root /var/www/html;` 한 줄.
- **Cloudflare Tunnel** — `service: http://localhost/health.html` (관련: `cloudflare-tunnel-setup`).
- **GitHub Pages / S3** — git push 후 자동 배포 (단, 데이터 노출 주의).

**보안**:
- 외부에 노출하면 hostname, GPU 모델, user count 가 누구에게나 보임 → basic auth 또는 IP allowlist.
- API key, 토큰, 비밀번호는 절대 페이지에 출력하지 말 것.
- `metrics` 같은 경로는 사내망 only — 대시보드 페이지만 외부 노출.

---

## 10. 흔한 함정

| 함정 | 증상 | 해결 |
|------|------|------|
| XSS escape 누락 | log 의 `<` 가 HTML 태그로 해석 | 모든 외부 입력 `html_escape` 통과 |
| `&` 를 마지막에 escape | `&amp;` 가 `&amp;amp;` 로 깨짐 | `&` 를 **첫 번째** 로 escape |
| curl timeout 미설정 | cron 이 1시간씩 hang | `curl -m 5` 필수 |
| 캐시 헤더 부재 | 브라우저가 5분 전 페이지 보여줌 | `<meta http-equiv="refresh" content="300">` 또는 Cache-Control 헤더 |
| 로컬 파일 권한 | nginx 가 못 읽음 | `chmod 644`, `chown www-data` |
| heredoc quote | `$VAR` 가 literal 로 출력 | `<<HTML` (no quote) vs `<<'HTML'` (literal) 구분 |
| nvidia-smi 미가용 | 페이지 전체 fail | `command -v nvidia-smi` 가드 + fallback |

---

## 11. 관련 skill

- `prometheus-fastapi-metrics` — 섹션 6 (Gateway /metrics) 의 데이터 소스.
- `observability-bundle` — Grafana 를 띄울 수 있는 환경이면 이쪽으로.
- `k8s-cron-alternatives` — cron 없는 환경에서 5분 갱신 트리거.
- `bash-cli-best-practices` — `set -euo pipefail`, sub-cmd dispatch.
- `cloudflare-tunnel-setup` — 외부 노출 시.
- `production-postmortem-pattern` — 사고 발생 시 대시보드 스냅샷 첨부.

---

## 검증

- gem-llm 라운드 70 `scripts/health-dashboard.sh` (144 lines).
- 8 섹션, 5분 cron, 28일 운영 무결.
- XSS 회피 검증: log 에 `<script>alert(1)</script>` 흘려보내도 escape 통과.
