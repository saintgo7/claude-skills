# blue-green-deployment-pattern

LLM 서빙 (vLLM, FastAPI Gateway 등) 의 무중단/저중단 cutover 패턴. GEM-LLM `vllm-env` → `vllm-env-020` (vLLM 0.19 → 0.20) 작업에서 도출 — 격리 venv + 새 포트 검증 + 인터랙티브 승인 + rollback runbook.

## 사용 시점

- "vllm 버전 업그레이드", "blue green 배포", "0 다운타임 전환"
- "서빙 cutover", "rollback runbook"
- "flashinfer cache 격리"

## 설치

```bash
./install.sh blue-green-deployment-pattern
```

10단계 cutover 표준 절차, 5가지 안전 장치 (격리 venv / flashinfer 캐시 / 승인 게이트 / GPU fence / rollback runbook), 흔한 함정 7가지는 [SKILL.md](SKILL.md), 표준 cutover/rollback 스크립트는 [scripts/](scripts/) 참조.
