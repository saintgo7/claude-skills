---
name: playbook-authoring-pattern
description: 'Claude Code / 사람이 그대로 실행 가능한 절차서 작성 패턴. 사용 시점 — "playbook 작성", "절차서", "step by step 가이드", "runbook", "operational guide", "Claude Code 시킬 문서", "각 단계 검증". 4-tuple 구조 ([목적][명령][기대출력][실패복구]) + pre-flight + idempotent 가드.'
---

# playbook-authoring-pattern

Claude Code 또는 사람이 처음부터 끝까지 막힘 없이 실행 가능한 절차서 (playbook / runbook) 작성 패턴.
gem-llm `docs/ops/ssh-external-access.md` v1 (438 lines) → v2 (1193 lines, +172%) 상세화로 검증.

## 1. 사용 시점

- 운영 절차서 (배포, 마이그레이션, 백업/복구)
- 신규 환경 setup (3-노드 클러스터, K8s, OpenSSL CA, Cloudflare Tunnel)
- Claude Code 에게 그대로 시킬 가이드 (`@docs/...md 절차 X.Y 수행`)
- 사고 복구 runbook (postmortem 의 [예방] → 절차서로 변환)
- "한 번 짜놓고 두 번째부터는 그대로 돌리고 싶은" 모든 작업

## 2. 4-tuple 구조 (핵심)

각 단계는 다음 5 요소로 구성한다 (편의상 "4-tuple" 이라 부르지만 [검증] 포함 5개):

```markdown
#### N.M.K <단계 제목>

**[목적]** 왜 이 단계가 필요한지 (1-2 문장).
**[명령]**
\`\`\`bash
실제 실행 명령 (변수는 <PLACEHOLDER> 명시)
\`\`\`
**[기대 출력]** 정상 시 보일 텍스트 (예: "OK", "200", 또는 "(없음 — silent)").
**[검증]**
\`\`\`bash
효과 확인 명령 (state 변화를 외부에서 확인)
\`\`\`
**[실패 시]**
- 증상 A → 원인 → 해결 명령
- 증상 B → 원인 → 해결 명령
```

5 요소 모두 있어야 자율 실행 가능.

## 3. 왜 4-tuple 인가

| 요소 | 없으면 |
|---|---|
| 목적 | 왜 하는지 모름 → skip / 잘못된 응용 |
| 명령 | 실행 불가 |
| 기대 출력 | 성공 여부 판단 X → 다음 단계로 잘못 진행 |
| 검증 | 명령은 됐는데 효과 없음 (silent fail) |
| 실패 시 | 막히면 사용자/문서 작성자에게 떠넘김 |

검증 수치: ssh-external-access.md v1 (목적/명령만) → Claude Code 가 단계 7/13 에서 막힘.
v2 (4-tuple 전체) → 13/13 자율 완료.

## 4. pre-flight check (절차 시작 전)

큰 절차서는 §3.0 같은 pre-flight 섹션을 둔다:

- 필수 도구 설치 여부 (`which cloudflared`, `dpkg -l | grep openssh-server`)
- 권한 (sudo 가능? root? specific group?)
- 디스크 / 메모리 여유 (`df -h /`, `free -g`)
- 네트워크 도달성 (`curl -sS --max-time 5 https://...`)
- 기존 상태 (이미 일부 설정됨? — idempotent 분기)

pre-flight 없으면 절차 §3 에서야 "포트 22 막힘" 발견 → 처음부터 다시.

## 5. idempotent 가드 패턴

```bash
# 키 생성
[ -f ~/.ssh/key ] || ssh-keygen ...

# 라인 추가 (이미 있으면 skip)
grep -q "MARKER" ~/.bashrc || cat >> ~/.bashrc <<'EOF'
# MARKER
...
EOF

# 패키지
dpkg -l | grep -q cloudflared || sudo apt-get install -y cloudflared

# 파일 권한
[ "$(stat -c %a ~/.ssh)" = "700" ] || chmod 700 ~/.ssh

# 서비스
systemctl is-active --quiet ssh || sudo systemctl start ssh
```

이걸로 절차서를 두 번 돌려도 안전 (재시작 / 부분 실패 후 재개).

## 6. 분기 (옵션 A / B)

큰 결정점은 옵션을 명시하고 trade-off 를 표기:

```markdown
**[옵션 A — 외부에서 scp]**
- 장점: 빠름 (1 명령)
- 단점: 외부 노출, 공인 IP 필요
- 명령: ...

**[옵션 B — 노드 안에서 login (권장)]**
- 장점: 외부 노출 X
- 단점: 2-step (수동 paste)
- 명령: ...
```

trade-off (시간 / 복잡도 / 권한 / 보안) 를 명시하면 독자가 판단 가능.

## 7. 한 줄 요약 (Claude Code 명령)

긴 절차서 끝에 Claude Code 가 그대로 사용할 invocation 을 넣는다:

```markdown
## 9. Claude Code 에게 시킬 때

@docs/ops/ssh-external-access.md 절차 §4.2 수행.
호스트=<NODE_NAME>, 사용자=<USER>. 실패 시 멈춤 + 보고.
끝나면 §5 검증 결과 출력.
```

placeholder (`<NODE_NAME>`, `<USER>`) 는 Claude Code 가 호출 시 치환할 부분.

## 8. 트러블슈팅 표 (필수)

```markdown
## 6.1 자주 보는 실패

| # | 증상 | 가능 원인 | 해결 |
|---|---|---|---|
| 1 | `Permission denied (publickey)` | authorized_keys 권한 644 | `chmod 600` |
| 2 | `Connection refused` | sshd 미기동 | `systemctl start ssh` |
| 3 | `Host key verification failed` | known_hosts 오염 | `ssh-keygen -R <host>` |
```

본문이 1000 줄이어도 트러블슈팅 표는 1 화면. 막혔을 때 가장 먼저 찾는 곳.

## 9. 검증 단계 (전체 동작)

마지막 §5 같은 종합 검증 (한 셸 한 줄로 자동화):

```bash
# 모든 노드 SSH + tunnel + DNS 한 번에
for n in master n1 n3; do
  ssh "$n" "hostname" >/dev/null 2>&1 && echo "OK: $n" || echo "FAIL: $n"
done

# 기대 출력
# OK: master
# OK: n1
# OK: n3
```

검증 단계가 모두 OK 면 절차서 적용 완료. 하나라도 FAIL 이면 §6.1 트러블슈팅으로 분기.

## 10. 흔한 함정

| 증상 | 원인 | 해결 |
|---|---|---|
| 절차 중간에 막힘 | 실패 시 분기 X | 4-tuple 강제 |
| 두 번 돌리면 깨짐 | idempotent X | §5 가드 패턴 |
| Claude Code 가 변수 치환 못 함 | 자리 표시자 모호 | `<NODE>` 같은 명시적 placeholder |
| 검증 단계 누락 | 중간 명령만 있고 효과 확인 X | [검증] 분리 |
| 1000 줄 절차서 → 안 읽힘 | 트러블슈팅 표 없음 | §6.1 한 화면 표 |
| 옵션 분기 모호 | A/B 불명확 | "[옵션 A]" 명시 |
| pre-flight 없음 | 사전 조건 가정 | §3.0 자가진단 |
| 출력 예시 없음 | 성공 판단 불가 | [기대 출력] 항목 |
| sudo / 권한 모호 | 절반은 user, 절반은 root | 각 명령 prompt (`$` vs `#`) 명시 |
| 명령 복붙 시 깨짐 | placeholder 가 한글 / 특수문자 | `<UPPER_SNAKE>` 만 사용 |

## 11. 관련 skill

- `production-postmortem-pattern` — 사후분석 7-section 형식 (postmortem [예방] → 본 패턴 절차서로 변환)
- `claude-code-skill-authoring` — skill 자체를 작성할 때 (이 문서가 그 결과물)
- `bilingual-book-authoring` — 책의 운영 chapter 가 절차서일 때
- `deployment-checklist` — 절차서 §3.0 pre-flight 의 항목 리스트
- `bash-cli-best-practices` — 절차서 안의 bash 명령 품질
