---
name: cloudflare-tunnel-setup
description: 'Cloudflare Tunnel을 처음부터 셋업 — 도메인 → 로컬 서비스 HTTPS 노출. 사용 시점 — "cloudflared 설치", "tunnel 새로 만들기", "도메인 라우팅", "k8s pod 외부 노출", "방화벽 우회 https", "내 노트북 서비스 인터넷에", "고정 IP 없이 외부 접근", "ssh 외부에서 들어가기", "여러 도메인 한 tunnel", "https 무료 인증서". 토큰 인증, ingress config, systemd-style 운영, 다중 hostname, SSH ProxyCommand 패턴 포함.'
---

# cloudflare-tunnel-setup

Cloudflare Tunnel(이전 Argo Tunnel)을 사용해 **고정 IP·포트포워딩·인증서 발급 없이** 로컬 서비스를 도메인 HTTPS로 외부 노출하는 *처음부터* 가이드.

NAT/방화벽 뒤(K8s pod, 사내망, 가정 회선)에서도 작동하며, 무료 플랜으로 충분.

## 사용 시점 (트리거 phrase)

- "cloudflared 설치"
- "tunnel 새로 만들기"
- "도메인 라우팅 추가"
- "K8s pod 외부 노출"
- "방화벽 우회 HTTPS"
- "고정 IP 없이 외부 접근"
- "ssh 외부에서 들어가기"
- "여러 도메인 한 tunnel"
- "https 무료 인증서"
- "내 노트북을 인터넷에"

## 토폴로지 (개념)

```
[Internet user]
    ↓ HTTPS (443)
[Cloudflare CDN edge]
    ↓ outbound-only QUIC/HTTP2 tunnel
[cloudflared on your host]  ← 방화벽 뒤도 OK (outbound 443만 열려 있으면)
    ↓ http://localhost:<port>
[Local service]
```

핵심: cloudflared가 **outbound로** Cloudflare에 연결하므로 inbound 포트를 열지 않아도 됨.

## 사전 조건

| 항목 | 비고 |
|---|---|
| Cloudflare 계정 | 무료 플랜 OK |
| 등록 도메인 | Cloudflare DNS로 nameserver 위임된 상태 (대시보드에서 "Active") |
| 호스트 OS | Linux/macOS/Windows. 이 가이드는 Linux 기준 |
| outbound 443 | 방화벽이 outbound 차단 시 작동 안 함 (드물음) |

도메인이 아직 Cloudflare에 없으면: Cloudflare 대시보드 → "Add a site" → 기존 레지스트라에서 nameserver를 Cloudflare 것으로 변경 (전파 ~수시간).

## Step 1 — cloudflared 설치

### Linux (apt 패키지, snap 우회)

```bash
# x86_64
curl -L --output cloudflared.deb \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb

# ARM64 (Raspberry Pi, AWS Graviton 등)
curl -L --output cloudflared.deb \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
sudo dpkg -i cloudflared.deb
```

### Linux (sudo 불가, 사용자 home에 설치)

K8s pod / 공유 서버에서 자주 필요:

```bash
mkdir -p ~/.local/bin
curl -L --output ~/.local/bin/cloudflared \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x ~/.local/bin/cloudflared
export PATH="$HOME/.local/bin:$PATH"
cloudflared --version
```

### macOS

```bash
brew install cloudflared
```

⚠️ **snap 미사용**: Ubuntu의 `snap install cloudflare-warp` 등은 confinement로 인해 `~/.cloudflared/` 경로를 못 보는 경우가 있음. 위 .deb / GitHub 바이너리 권장.

## Step 2 — 인증 (한 번만)

```bash
cloudflared tunnel login
```

브라우저 OAuth 창이 뜨고 도메인을 선택하면 origin certificate가 `~/.cloudflared/cert.pem`에 저장됨. 헤드리스 서버면 출력된 URL을 로컬 브라우저에 복붙.

이 cert.pem은 **계정-도메인 자격증명** — DNS 라우팅 등록과 tunnel 생성에 사용. 한 번 받아 다른 노드로 scp 가능.

## Step 3 — Tunnel 생성

```bash
cloudflared tunnel create my-tunnel
```

출력:
```
Created tunnel my-tunnel with id 12345678-abcd-...
```

자격증명 JSON이 `~/.cloudflared/<UUID>.json`에 저장됨. **이걸 분실하면 같은 tunnel 재사용 불가** — 반드시 백업.

목록 확인:
```bash
cloudflared tunnel list
```

## Step 4 — DNS 라우팅

Cloudflare DNS에 CNAME 자동 등록:

```bash
cloudflared tunnel route dns my-tunnel app.example.com
```

출력: `Added CNAME app.example.com which will route to this tunnel`

여러 도메인 노출은 이 명령을 hostname 별로 반복.

## Step 5 — Ingress config.yml 작성

`~/.cloudflared/config.yml`:

```yaml
tunnel: 12345678-abcd-...           # Step 3의 UUID
credentials-file: /home/USER/.cloudflared/12345678-abcd-....json

ingress:
  # HTTP 서비스
  - hostname: app.example.com
    service: http://localhost:8080

  # 다른 HTTP 포트
  - hostname: api.example.com
    service: http://localhost:9000

  # SSH (TCP) — Step 7의 ProxyCommand 패턴과 결합
  - hostname: ssh.example.com
    service: ssh://localhost:22

  # 일반 TCP (e.g. Postgres)
  - hostname: db.example.com
    service: tcp://localhost:5432

  # 로컬 정적 파일 디렉토리
  # - hostname: files.example.com
  #   service: file:///var/www

  # 매칭 안 되면 404 (마지막 catch-all 필수)
  - service: http_status:404
```

검증:
```bash
cloudflared tunnel ingress validate
```

## Step 6 — Tunnel 실행

### 포그라운드 (테스트)

```bash
cloudflared tunnel --config ~/.cloudflared/config.yml run my-tunnel
```

정상 로그 패턴:
```
Registered tunnel connection connIndex=0 ... protocol=quic
```

### 백그라운드 (sudo 가능 — systemd)

```bash
sudo cloudflared service install
sudo systemctl enable --now cloudflared
sudo systemctl status cloudflared
```

### 백그라운드 (sudo 불가 — nohup)

K8s pod / 공유 jovyan 환경:

```bash
nohup ~/.local/bin/cloudflared tunnel \
  --config ~/.cloudflared/config.yml \
  run my-tunnel \
  > ~/cloudflared.log 2>&1 &
```

재시작 (SIGHUP 안 먹음):
```bash
CF_PID=$(pgrep -f "cloudflared.*tunnel.*run.*my-tunnel" | head -1)
kill -TERM "$CF_PID"
sleep 2
nohup ~/.local/bin/cloudflared tunnel --config ~/.cloudflared/config.yml run my-tunnel \
  > ~/cloudflared.log 2>&1 &
```

## 검증

```bash
# DNS 전파
getent hosts app.example.com    # Cloudflare IP (104.x / 172.x / IPv6)

# HTTPS 응답
curl -s -m 5 -o /dev/null -w "%{http_code}\n" https://app.example.com/
# 200 = 정상
```

## 다중 hostname (한 tunnel에서 여러 도메인)

새 hostname 추가 절차:

1. **DNS 라우팅 등록** (cert.pem 있는 노드에서):
   ```bash
   cloudflared tunnel route dns my-tunnel new.example.com
   ```

2. **config.yml ingress 추가**:
   ```yaml
   - hostname: new.example.com
     service: http://localhost:9001
   ```

3. **cloudflared 재시작** (위 절차)

같은 tunnel UUID 하나로 수십 개 hostname 라우팅 가능.

## SSH 우회 — `cloudflared access ssh` ProxyCommand

방화벽 뒤 호스트 SSH 노출. 서버 측 ingress:
```yaml
- hostname: ssh.example.com
  service: ssh://localhost:22
```

클라이언트 `~/.ssh/config`:
```
Host myserver
  HostName ssh.example.com
  User USERNAME
  ProxyCommand cloudflared access ssh --hostname %h
  IdentityFile ~/.ssh/id_ed25519
  StrictHostKeyChecking accept-new
  ServerAliveInterval 30
```

이제 `ssh myserver` 작동. 첫 접속 시 브라우저 OAuth 1회 (Cloudflare Access 정책 설정 시).

## 트러블슈팅

| 증상 | 원인 / 진단 |
|---|---|
| HTTP 502 | origin 서비스 죽음 또는 listen 안 됨. `curl http://localhost:<port>` 직접 확인 |
| HTTP 503 | tunnel 자체 작동 안 함. `pgrep -af cloudflared`, 로그 확인 |
| HTTP 521 | origin이 0.0.0.0이 아니라 127.0.0.1만 listen — 보통 OK지만 docker/k8s에서 포트 매핑 문제 가능 |
| HTTP 525 | TLS handshake 실패 (origin이 https인데 cert 문제) — `service: http://`로 평문 사용 |
| HTTP 1033 | "Tunnel does not exist" — UUID 오타 또는 credentials JSON 분실 |
| `EADDRINUSE` | 같은 포트에 이미 cloudflared 실행 중. `pgrep -af cloudflared`로 중복 제거 |
| `failed to sufficiently increase receive buffer size` | 경고일 뿐 (QUIC 최적화). 무시 가능 |
| snap cloudflared가 `~/.cloudflared/` 못 봄 | snap confinement. .deb / 바이너리로 교체 |
| 브라우저 로그인 안 뜸 | 헤드리스 서버. URL 복사해 로컬 브라우저에서 열고 cert.pem만 scp로 가져오기 |
| `error code: 1xxx` | Cloudflare 자체 차단. 대시보드에서 보안 설정 확인 |

## Tunnel 자격증명 백업 / 다중 노드 공유

한 계정 + 한 도메인이면 **다른 노드에서도 같은 cert.pem 재사용**:

```bash
# 노드 A (cloudflared login 완료)에서:
scp ~/.cloudflared/cert.pem nodeB:~/.cloudflared/

# 노드 B에서 새 tunnel 생성:
cloudflared tunnel create nodeB-tunnel
# → 새 UUID + 새 credentials JSON
```

같은 hostname을 여러 노드로 분산하려면 **load balancer** 기능 사용 (Cloudflare 유료). 무료 플랜은 hostname당 한 tunnel만.

## 보안 체크리스트

- [ ] credentials JSON (`<UUID>.json`)을 git에 커밋 안 함 (.gitignore)
- [ ] cert.pem 권한 600 (`chmod 600 ~/.cloudflared/cert.pem`)
- [ ] origin 서비스가 인증 없이 노출되면 위험 — Cloudflare Access 정책 추가 고려
- [ ] SSH는 password 인증 끄고 키만 (sshd_config: `PasswordAuthentication no`)

## 자동화 스크립트

`scripts/setup-tunnel.sh <tunnel-name> <hostname> <local-port>` —
설치 확인 + tunnel 생성 + DNS 라우팅 + config.yml 생성 + foreground run.
인증(Step 2)은 사람이 한 번 해야 하므로 자동화 안 함.

## 관련 skill

- `project-bootstrap` — 새 프로젝트 시작 시 도메인 노출 단계
- `gem-llm-cloudflare-tunnel` — 이 패턴의 GEM-LLM 특화 사례 (master/n1 운영)

## 메모

- Cloudflare Tunnel은 **Cloudflare가 무료로 제공** (Argo Tunnel 시절 유료였으나 2022년 Zero Trust 무료 플랜 통합)
- 트래픽 한도 제한 거의 없음 — 일반 웹·API 노출 무제한
- WebSocket, gRPC, HTTP/2 모두 지원
