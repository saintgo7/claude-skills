# gem-llm-cloudflare-tunnel

GEM-LLM 외부 노출 (`llm.pamout.com`) Cloudflare Tunnel 운영 스킬.

## 사용 시점

- "외부 502", "tunnel 안 돼"
- "DNS 추가", "새 서브도메인"
- "cloudflared 재시작"
- "llm.pamout.com 안 열려"

## 설치

```bash
./install.sh gem-llm-cloudflare-tunnel
```

n1 cloudflared와 master cloudflared 역할 구분, 재시작 절차는 [SKILL.md](SKILL.md) 참조.
