# cloudflare-tunnel-ssh-access-pattern

Cloudflare Tunnel 경유 SSH 외부 접속 패턴 (K8s pod / no-public-IP / 사내망). sshd 2222 + `cloudflared access ssh` ProxyCommand 조합.

## 사용 시점

- "K8s pod SSH 외부", "공인 IP 없음 SSH"
- "cloudflared access ssh", "ProxyCommand"
- "private network SSH", "pod 안 sshd"
- "노드별 개별 터널 (장애 격리)", "Zero Trust SSH"

## 설치

```bash
./install.sh cloudflare-tunnel-ssh-access-pattern
```

자세한 12 섹션 (사용 시점 → 아키텍처 → sshd → cloudflared → DNS → 클라이언트 → Access → autostart → 검증 → 트러블슈팅 → 보안 → 관련 skill) 은 [SKILL.md](SKILL.md). 템플릿 3종 (`sshd_config`, `cloudflared-config.yml`, 클라이언트 `~/.ssh/config`) 은 [templates/](templates/). gem-llm 3노드 클러스터 (master/n1/n3) 운영 검증.
