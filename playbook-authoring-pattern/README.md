# playbook-authoring-pattern

Claude Code / 사람이 그대로 실행 가능한 절차서 (playbook / runbook) 작성 패턴.
4-tuple 구조 ([목적][명령][기대출력][검증][실패복구]) + pre-flight + idempotent 가드 + 트러블슈팅 표.
gem-llm `docs/ops/ssh-external-access.md` v1 (438 lines) → v2 (1193 lines, +172%) 상세화로 검증.

## 사용 시점

- 운영 절차서 (배포, 마이그레이션, 백업/복구)
- 신규 환경 setup (3-노드 클러스터, K8s, OpenSSL CA)
- Claude Code 에게 그대로 시킬 가이드
- 사고 복구 runbook

## 설치

```bash
./install.sh playbook-authoring-pattern
```

## 빠른 시작

```bash
mkdir -p docs/ops
cp ~/.claude/skills/playbook-authoring-pattern/templates/full-playbook.md.template \
   docs/ops/<your-runbook>.md
```

## 자세한 사용법

[SKILL.md](SKILL.md)
