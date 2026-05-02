---
name: gem-llm-cloudflare-tunnel
description: GEM-LLM 외부 노출 (llm.pamout.com) Cloudflare Tunnel 운영. 사용 시점 — "외부 502", "tunnel 안 돼", "DNS 추가", "새 서브도메인", "cloudflared 재시작", "llm.pamout.com 안 열려". n1 cloudflared와 master cloudflared 역할 구분 + 재시작 방법.
---

# gem-llm-cloudflare-tunnel

## 토폴로지

```
[Internet]
    ↓ HTTPS
[Cloudflare CDN edge]
    ↓ tunnel
[n1 cloudflared (UUID 10f3cb24-...)] — n1에서 실행
    ↓ http://localhost:8080
[Gateway]
```

`paper.pamout.com` (master:8000 code-server)는 별도 master cloudflared (UUID e9781f73-...).

## n1 cloudflared 설정

`/home/jovyan/.cloudflared/config.yml`:

```yaml
tunnel: 10f3cb24-f38c-48d4-9389-766203da3860
credentials-file: /home/jovyan/.cloudflared/10f3cb24-f38c-48d4-9389-766203da3860.json
ingress:
- hostname: llm.pamout.com
  service: http://localhost:8080
- hostname: n1-paper.pamout.com
  service: http://localhost:8001
- hostname: n1-ssh.pamout.com
  service: ssh://localhost:2222
- service: http_status:404
```

## n1 cloudflared 운영

```bash
# 상태
pgrep -af cloudflared

# 재시작 (SIGHUP 안 먹으니 kill + 새로)
CF_PID=$(pgrep -f "cloudflared.*tunnel.*run.*research-portal-n1" | head -1)
kill -TERM $CF_PID
sleep 2
nohup /home/jovyan/.local/bin/cloudflared tunnel \
  --config /home/jovyan/.cloudflared/config.yml \
  run research-portal-n1 \
  > ~/cloudflared-n1.log 2>&1 &
```

정상 로그:
```
Registered tunnel connection connIndex=0 ... ip=198.41.192.7 location=icn06 protocol=quic
```

## 새 서브도메인 추가

**master에서 DNS 라우팅 등록** (n1 cloudflared가 아닌 master에서):

```bash
ssh master "/home/jovyan/.local/bin/cloudflared tunnel route dns 10f3cb24-f38c-48d4-9389-766203da3860 newdomain.pamout.com"
```

응답: `Added CNAME newdomain.pamout.com which will route to this tunnel`

그 후 n1 config.yml에 ingress 추가:
```yaml
- hostname: newdomain.pamout.com
  service: http://localhost:9000
```

n1 cloudflared 재시작 (위 절차).

## 검증 단계

```bash
# DNS resolve
getent hosts llm.pamout.com   # IPv6 = Cloudflare CDN

# 외부 HTTPS
curl -s -m 5 -o /dev/null -w "%{http_code}\n" https://llm.pamout.com/healthz
# 200 = 정상, 502 = Gateway 죽음, 503 = service:http_status:404 fallback (ingress 매칭 실패)
```

## 트러블슈팅

### llm.pamout.com → 502 / 503

| HTTP | 의미 | 진단 |
|---|---|---|
| 502 | Gateway 죽음 또는 8080 미응답 | `supervisor.sh status` |
| 503 | tunnel 자체 작동 안 함 | n1 cloudflared 죽음 가능성, `pgrep -af cloudflared` |
| 404 | ingress 매칭 실패 | config.yml hostname 오타 |
| 525 | TLS handshake 실패 | Cloudflare cert 만료 (드물음) |
| 521 | origin 거부 | 8080이 0.0.0.0 listen 안 함 (uvicorn `--host 0.0.0.0`) |

### Cloudflare 자체 차단 시

`error code: 1xxx` 오면 Cloudflare 대시보드에서 확인. master 계정 e8both@gmail.com.

## n1 → master SSH (보너스, 같은 cloudflared 메커니즘)

`~/.ssh/config`:
```
Host master
  HostName vs02-ssh.pamout.com
  User jovyan
  ProxyCommand /home/jovyan/.local/bin/cloudflared access ssh --hostname %h
  IdentityFile ~/.ssh/id_ed25519
  StrictHostKeyChecking accept-new
  ServerAliveInterval 30
```

`ssh master` 작동. 동일 패턴으로 `Host n3` (n3-ssh.pamout.com).

## SSH access ssh가 작동 안 할 때

- `Connection reset by peer` → master sshd가 IP 차단 (정상, K8s pod 격리). cloudflared로만 접근 가능.
- master에서는 `cloudflared access` 인증 캐시 (`~/.cloudflared/cred.json` 또는 cookie). 만료 시 재로그인.

## tunnel 인증 자료

- master: `cert.pem` (cloudflared login 한 번 한 결과), credentials JSON `e9781f73-...json`
- n1: 동일 origin certificate, credentials JSON `10f3cb24-...json`
- 둘 다 같은 Cloudflare 계정 (e8both@gmail.com 또는 saintgo7) 소속

새 노드에 cloudflared 셋업 시 master의 cert.pem을 scp로 가져오고 `cloudflared tunnel create <name>` → credentials JSON 받기.

## 메모리

- `project_master_hub.md` — master가 인증 허브
- `project_gem_llm_runtime.md` — llm.pamout.com 라우팅 사실
