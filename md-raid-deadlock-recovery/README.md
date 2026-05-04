# md-raid-deadlock-recovery

Linux md (mdadm) RAID5/6 stripe-cache 데드락 진단 + 안전 재부팅 + 재발 방지.

대용량 RAID5/6 어레이에서 mdcheck (정합성 검사) 진행 중 `raid5_get_active_stripe` ↔ `kthread_stop` 데드락 발생 시:

- 디스크는 정상 (SMART PASSED, in_flight=0)
- `/data` 위 모든 fsync/COMMIT이 hang
- `mdadm --stop`, `umount`, `sync` 등 모든 회복 시도가 또 다른 D-state 만듦
- **재부팅이 유일 회복**, 단 그냥 reboot하면 같은 데드락 재발 또는 SSH 못 들어가서 서버실 가야 함

이 skill은 그 4가지 위험을 자동 점검 + 차단:

1. **mdcheck 자동 재트리거** — timer disable + `/var/lib/mdcheck/MD_UUID_*` 제거 + `AUTOCHECK=false`
2. **루트 fsck로 부팅 지연** — `tune2fs -c 0`로 mount-count 기반 fsck 비활성
3. **SSH 백업 경로 확보** — Cloudflare Tunnel SSH (`cloudflared access ssh`) 사전 검증
4. **컨테이너 자동 기동** — restart 정책 분포 점검, `unless-stopped` 보존

## 검증

abada-int-65 (Xeon Gold 5215, 28TB RAID5, 136 컨테이너) 2026-05-04 사고 — 모든 사전 점검 통과 + 재부팅 절차 문서화.

## 사용

```bash
# 1. 데드락 의심 시 진단
sudo ./scripts/diagnose.sh md0

# 2. 데드락 확정 시 사전 작업
sudo ./scripts/pre-reboot-harden.sh

# 3. 사용자 GO 사인 후
sudo reboot

# 4. 부팅 후 검증 (다른 PC에서 cloudflared SSH로 접속해 실행)
HEALTH_URLS='https://blog.example.com https://app.example.com' \
  sudo ./scripts/post-reboot-verify.sh md0
```

자세한 절차는 [SKILL.md](SKILL.md) 참고.

## 자산

| 파일 | 용도 |
|---|---|
| `SKILL.md` | Claude Code skill 본체 (frontmatter + playbook) |
| `scripts/diagnose.sh` | 7개 지표 자동 감지 (load/iowait/blocked/sync_action/in_flight/stack/SMART) |
| `scripts/pre-reboot-harden.sh` | 4가지 위험 자동 차단 |
| `scripts/post-reboot-verify.sh` | 부팅 후 6단계 검증 |
| `case-studies/abada-int-65-2026-05-04.md` | 실제 사고 노트 (kernel stack trace, pg_stat_activity, SMART) |

## 관련

- `cloudflare-tunnel-ssh-access-pattern` — 백업 SSH 셋업
- `production-postmortem-pattern` — 사고 후 postmortem
- `deployment-checklist` — 운영 점검
