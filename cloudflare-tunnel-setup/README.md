# cloudflare-tunnel-setup

Cloudflare Tunnel을 처음부터 셋업해 NAT/방화벽 뒤 로컬 서비스를 도메인 HTTPS로 외부 노출하는 가이드.

## 사용 시점

- "cloudflared 설치", "tunnel 새로 만들기"
- "도메인 라우팅", "k8s pod 외부 노출"
- "고정 IP 없이 외부 접근", "ssh 외부에서 들어가기"
- "여러 도메인 한 tunnel", "https 무료 인증서"

## 설치

```bash
./install.sh cloudflare-tunnel-setup
```

자세한 셋업 절차, ingress config, systemd 운영, SSH ProxyCommand 패턴은 [SKILL.md](SKILL.md) 참조.
