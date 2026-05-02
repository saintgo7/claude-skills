---
name: gem-llm-supervisor
description: GEM-LLM 전체 스택(vLLM 듀얼, Gateway, Admin UI)을 한 번에 시작/정지/상태/재시작. 사용 시점 — "gem-llm 시작", "gem-llm 재시작", "전체 상태 확인", "스택 다 내려", "재부팅 후 복구", "어떤 서비스가 죽었지". 단일 컴포넌트 디버깅이 아니라 *통합 운영*에 사용. 모델 로딩 5분 대기 포함.
---

# gem-llm-supervisor

전체 스택 관리 — `bash /home/jovyan/gem-llm/scripts/supervisor.sh`

## 명령

| | |
|---|---|
| `supervisor.sh status` | 4개 로컬 서비스 + Cloudflare 외부 + GPU 상태 |
| `supervisor.sh start` | vLLM 2개 → 5분 모델 로딩 폴링 → Gateway/Admin 시작 |
| `supervisor.sh stop` | 역순 정지 (admin → gateway → vllm) |
| `supervisor.sh restart` | stop + 3초 + start |
| `supervisor.sh logs [서비스]` | tail -f. 서비스: vllm-31b, vllm-26b, gateway, admin-ui |

## 정상 status 응답 (모두 GREEN)

```
[vllm-31b] 🟢 200 (8001/v1/models)
[vllm-26b] 🟢 200 (8002/v1/models)
[gateway]  🟢 200 (8080/healthz)
[admin-ui] 🟢 200 (8090/login)
llm.pamout.com 🟢 200
GPU: 0..3 ~158GB (Dense), 4..7 ~159GB (MoE)
```

## start 시 폴링 동작

vLLM은 가중치 로딩에 보통 1-2분 (Qwen2.5-Coder-32B 64GB, Qwen3-Coder-30B-A3B 60GB). 스크립트는 10초 간격으로 8001/8002의 `/v1/models`를 폴링하고 둘 다 200이면 Gateway/Admin 시작. 5분 timeout이지만 정상 환경에선 60-100초.

## 한 컴포넌트만 다시 띄우려면

`supervisor.sh restart`는 전체. 한 개만 → PID 파일 + 직접 명령:

```bash
LOG=/home/jovyan/gem-llm/_logs
# Gateway만 재시작 (가장 흔함, vLLM 안 건드리고)
kill -TERM $(cat $LOG/gateway.pid) 2>/dev/null
cd /home/jovyan/gem-llm/src/gateway
set -a; source /home/jovyan/gem-llm/.env; set +a
nohup /home/jovyan/vllm-env/bin/python -m uvicorn gateway.main:app \
  --host 0.0.0.0 --port 8080 > $LOG/gateway.log 2>&1 &
echo $! > $LOG/gateway.pid
```

## 재부팅 후

K8s pod 재시작 시 vLLM 가중치는 메모리에서 사라지므로 재로딩 필수. 단순히 `supervisor.sh start` 1회 + 5분 대기.

## 트러블슈팅

| 증상 | 우선 확인 |
|---|---|
| status 빨간색 | 해당 서비스 로그: `supervisor.sh logs <name>` |
| vllm-31b/26b만 빨간색, 8001/8002 prc 없음 | port 충돌 (`python3 -m http.server 8001` 같은 좀비?) — `case 13.x` 참조 |
| llm.pamout.com 빨간색이지만 로컬 200 | n1 cloudflared 죽음 — `pgrep -af cloudflared`, 필요시 `nohup cloudflared tunnel ... &` |
| vLLM ready인데 Gateway 500 | 케이스 12 (QueuePool) 또는 13 (DB 손상) 의심 — `gem-llm-troubleshooting` |
| GPU 메모리 잔재 (이전 vLLM 죽었는데 GPU 차있음) | `nvidia-smi --query-compute-apps=pid` → `kill -9 <pid>` |

## 기동 시 자동 시작 (systemd 미가능 환경)

K8s pod에서 cron @reboot:

```bash
( crontab -l 2>/dev/null; echo "@reboot sleep 30 && bash /home/jovyan/gem-llm/scripts/supervisor.sh start >> /home/jovyan/gem-llm/_logs/supervisor-reboot.log 2>&1" ) | crontab -
```

(crond가 pod에서 동작하지 않으면 K8s livenessProbe 또는 jupyter notebook 시작 hook 사용 검토.)

## 메모리 / Hard 사실

- vllm 0.19.1, transformers 5.7.0
- /home/jovyan/.env에 GATEWAY_ADMIN_KEY (자동 생성)
- 모델 캐시: ~/.cache/huggingface (datavol-1 심볼릭)
- _data/gateway.db는 SQLite WAL 모드 — 정지 없이 mv 금지
