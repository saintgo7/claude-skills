---
name: cloudflare-tunnel-ssh-access-pattern
description: 'Cloudflare Tunnel 경유 SSH 외부 접속 패턴 (K8s pod / no-public-IP 환경). 사용 시점 — "K8s SSH 외부", "공인 IP 없음 SSH", "cloudflared access ssh", "ProxyCommand", "private network SSH", "pod 안 sshd", "노드별 터널", "Zero Trust SSH". sshd 2222 + cloudflared ingress + ~/.ssh/config ProxyCommand. gem-llm 3노드 클러스터 검증.'
---

# cloudflare-tunnel-ssh-access-pattern

공인 IP 없는 K8s pod / 사내 네트워크 / IoT 노드에 외부에서 SSH 접속하는 검증된 패턴. **Cloudflare Tunnel + `cloudflared access ssh` ProxyCommand** 조합. gem-llm 3노드 클러스터 (master/n1/n3) 에서 운영 검증.

## 1. 사용 시점

다음 중 하나라도 해당하면 이 skill:

- 공인 IP 없는 노드에 외부에서 SSH 들어가야 함 (K8s pod, 사내망, 가정 회선, IoT)
- HTTP-only 라우터 / 사내 firewall 뒤에서 22 포트 inbound 불가
- root 권한 제한적 → port 22 binding 못 함 (사용자 영역 sshd 필요)
- 여러 노드를 외부에 노출하되 *장애 격리* 원함 (한 노드 죽어도 다른 노드 살아있게)
- Cloudflare Access (제로 트러스트) 통합으로 *특정 이메일만* 접속 허용 원함
- VPN 설치 / 사내 점프 호스트 운영이 부담스러움

## 2. 핵심 아키텍처

```
[외부 노트북] ──TLS──> Cloudflare Edge ──암호화 터널──> cloudflared (in pod)
                                                          │
                                                          │ localhost:2222
                                                          ▼
                                                       sshd (in pod)
```

- 외부 클라이언트는 `cloudflared access ssh` 를 SSH 의 `ProxyCommand` 로 사용
- pod 안에서 sshd 와 cloudflared 가 같은 호스트(localhost) 에서 통신
- 외부 → Cloudflare Edge: 표준 TLS 443
- Cloudflare Edge → cloudflared: outbound-only (pod 가 *나가는* 연결만 만듦, NAT/firewall 친화)

## 3. sshd 설정 (사용자 영역, 2222 포트)

K8s pod 환경의 핵심 제약: root 없음, port 22 막힘, systemd 없음. → 모두 사용자 영역으로 해결.

| 항목 | 위치 | 비고 |
|---|---|---|
| binary | `/usr/sbin/sshd` | OS 기본 (없으면 `apt-get install -y openssh-server`) |
| host key | `~/.ssh/host_ed25519_key` | 영속 볼륨 (재시작 후 known_hosts 회귀 방지) |
| config | `~/.ssh/sshd_config` | `Port 2222`, `PubkeyAuthentication yes`, `PasswordAuthentication no` |
| pid | `~/.ssh/sshd.pid` | idempotent 재시작 |
| authorized_keys | `~/.ssh/authorized_keys` | 600 권한, 외부 클라이언트 공개키 |

`templates/sshd_config.template` 참고. 검증:

```bash
/usr/sbin/sshd -t -f ~/.ssh/sshd_config && echo "config OK"
/usr/sbin/sshd -f ~/.ssh/sshd_config
ss -tlnp | grep ":2222"
```

## 4. cloudflared 설정

**원칙: 노드별 *개별* 터널** (장애 격리). 한 cloudflared 가 여러 노드를 묶지 말 것.

```bash
# 1) login (한 번만, cert.pem 발급)
cloudflared login

# 2) tunnel create (노드별 다른 이름)
cloudflared tunnel create research-portal-<NODE>
TUNNEL_ID=$(cloudflared tunnel list | awk '/research-portal-<NODE>/ {print $1}')

# 3) config.yml — templates/cloudflared-config.yml.template 참고
```

config.yml 핵심:

```yaml
tunnel: <TUNNEL_ID>
credentials-file: <HOME>/.cloudflared/<TUNNEL_ID>.json
ingress:
  - hostname: <NODE>-ssh.<DOMAIN>
    service: ssh://localhost:2222
  - service: http_status:404
```

검증:

```bash
cloudflared tunnel ingress validate
cloudflared tunnel --config ~/.cloudflared/config.yml run research-portal-<NODE>
# 로그에 "Connection ... registered" 4회 = OK
```

## 5. DNS 라우팅

```bash
cloudflared tunnel route dns "$TUNNEL_ID" <NODE>-ssh.<DOMAIN>
```

Cloudflare 가 자동으로 CNAME 등록: `<NODE>-ssh.<DOMAIN> → <UUID>.cfargotunnel.com.`

검증:

```bash
sleep 30
dig +short <NODE>-ssh.<DOMAIN> CNAME
# 기대: <UUID>.cfargotunnel.com.
```

## 6. 외부 클라이언트 ~/.ssh/config

`templates/client-ssh-config.template` 참고. 핵심 한 블록으로 N 노드 처리:

```ssh-config
Host master n1 n3
  User jovyan
  Port 2222
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ProxyCommand cloudflared access ssh --hostname %h-ssh.<DOMAIN>
  ServerAliveInterval 60
  UserKnownHostsFile ~/.ssh/known_hosts.<DOMAIN>
```

`%h` 토큰이 호스트별로 자동 치환되므로 N 노드를 한 블록으로 처리. 외부 클라이언트는 `cloudflared` 바이너리만 PATH 에 있으면 됨 (사전 `cloudflared login` 필요).

## 7. Cloudflare Access (제로 트러스트, 권장)

위 6 까지로도 작동하지만 *전 세계 누구나* SSH 시도 가능 (키 인증으로 막히긴 함). Cloudflare Access 정책으로 ProxyCommand 단계에서 차단 → sshd 까지 도달 못 함.

절차:

1. https://one.dash.cloudflare.com → Access → Applications
2. Add an application → Self-hosted
3. Subdomain `<NODE>-ssh`, Domain `<DOMAIN>`
4. Identity providers: 이메일 OTP / Google / GitHub 중 1개 이상
5. Policies: Action `Allow`, Include `Emails: <user>@example.com`

이후 외부에서 `ssh <NODE>` 첫 실행 시 브라우저 자동 열림 → 인증 → 토큰 7일 유효.

토큰 갱신: `cloudflared access login <NODE>-ssh.<DOMAIN>`

## 8. K8s pod 자동 시작 (systemd 없음)

pod 재시작 시 sshd / cloudflared 자동 부활 패턴 4개:

| 패턴 | 트리거 | 장단점 |
|---|---|---|
| `~/.bashrc` idempotent autostart | 셸 진입 (`bash -lc :`) | 가장 간단. 셸 진입 안 하면 발동 안 됨 |
| s6 `cont-init.d` | 컨테이너 시작 | 표준화, 베이스 이미지가 s6 써야 함 |
| `supervisord` | 컨테이너 시작 | 프로세스 감시, 별도 설치 필요 |
| K8s `lifecycle.postStart` | pod 생성 시 1회 | manifest 수정 권한 필요 |

`~/.bashrc` 패턴 (가장 흔함):

```bash
# === AUTOSTART_SSHD_2222 (idempotent) ===
if [ -f "$HOME/.ssh/sshd_config" ] && \
   ! pgrep -f "sshd.*-f $HOME/.ssh/sshd_config" >/dev/null 2>&1; then
  /usr/sbin/sshd -f "$HOME/.ssh/sshd_config" 2>/dev/null
fi

# === AUTOSTART_CLOUDFLARED_<NODE> (idempotent) ===
if [ -f "$HOME/.cloudflared/config.yml" ] && \
   ! pgrep -f "cloudflared.*research-portal-<NODE>" >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/log"
  nohup cloudflared tunnel --config "$HOME/.cloudflared/config.yml" run research-portal-<NODE> \
        >>"$HOME/.local/log/cloudflared.log" 2>&1 &
fi
```

`pgrep -f` 가드가 idempotent 키. 셸 진입 N 회 = 프로세스 1 개 보장. 자세한 패턴은 skill `k8s-cron-alternatives` / `k8s-pod-autostart` 참고.

## 9. 검증 (3단 체크)

외부 클라이언트에서:

```bash
# 1) DNS
dig +short <NODE>-ssh.<DOMAIN> CNAME
# 기대: <UUID>.cfargotunnel.com.

# 2) HTTPS edge (1033 = SSH origin, 정상)
curl -sI https://<NODE>-ssh.<DOMAIN> 2>&1 | head -1
# 기대: HTTP/2 530

# 3) SSH end-to-end
ssh <NODE> "hostname"
# 기대: 노드 hostname 출력
```

3 단계 모두 통과해야 인프라 완성. 1 단계 실패 → DNS 라우팅 (5장), 2 단계 실패 → cloudflared 죽음, 3 단계 실패 → sshd 또는 authorized_keys.

## 10. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| `Permission denied (publickey)` | authorized_keys 미등록 / ~/.ssh 권한 | 노드: `chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys`; 외부 키 추가 |
| cloudflared 로그 `connection refused 127.0.0.1:2222` | sshd 죽음 또는 다른 포트 | 노드: `pgrep -af sshd`; `ss -tlnp \| grep 2222`; 없으면 sshd 재시작 |
| `kex_exchange_identification: Connection closed` | cloudflared 가 edge 도달 X | 노드: `tail ~/.local/log/cloudflared.log`; outbound 네트워크 / firewall 확인 |
| `Host key verification failed` | known_hosts 옛 키 | 외부: `ssh-keygen -R <NODE> -f ~/.ssh/known_hosts.<DOMAIN>` |
| pod 재시작 후 모두 안 됨 | autostart 미발동 (셸 미진입) | 새 셸 (`bash -lc :`) 진입 또는 `lifecycle.postStart` 추가 |
| `1016 Origin DNS error` | DNS 라우팅 실패 / 옛날 CNAME 잔존 | `cloudflared tunnel route dns` 재실행; Cloudflare 대시보드에서 중복 정리 |
| 530 도 아니고 1033 한참 | 다른 터널이 같은 호스트명 점유 | Cloudflare 대시보드 → DNS → CNAME 정리; 한 호스트명 = 한 터널 |

추가 진단 (외부 클라이언트):

```bash
ssh -vvv <NODE> 2>&1 | grep -E "Executing|Server version|Authent|Connection|Permission"
```

`Executing proxy command` → `Server version` (cloudflared 통과) → `Authentication succeeded` 까지 어디서 멈췄는지 한눈에.

## 11. 보안

| 계층 | 조치 |
|---|---|
| Edge | Cloudflare Access (7장) — 가장 강력. ProxyCommand 단계에서 차단 |
| Transport | 자동 (Cloudflare TLS, 별도 설정 X) |
| Auth | `PasswordAuthentication no` 강제, ed25519 키만 |
| sshd hardening | `MaxAuthTries 3`, `LoginGraceTime 30`, `AllowUsers <user>`, `PermitRootLogin no` |
| Host key 핀 | 외부 `~/.ssh/known_hosts.<DOMAIN>` 분리 (다른 ssh 와 충돌 방지) |
| Brute-force | Cloudflare Access (권장) > fail2ban (보조) |
| Key rotation | authorized_keys 의 해당 줄 삭제 + Cloudflare Access 이메일 차단 |

`templates/sshd_config.template` 에 hardening 옵션 포함.

## 12. 관련 skill

- `cloudflare-tunnel-setup` — HTTP/HTTPS 라우팅 (이 skill 의 형제, 함께 쓰면 한 cloudflared 가 SSH + HTTP 동시 라우팅)
- `k8s-cron-alternatives` / `k8s-pod-autostart` — 8장 autostart 패턴 상세
- `bash-cli-best-practices` — sshd_config 템플릿 / autostart 스크립트 작성
- `production-postmortem-pattern` — book case 4 (Cloudflare HTTP-only 제약)
