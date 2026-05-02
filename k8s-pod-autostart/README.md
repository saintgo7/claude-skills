# k8s-pod-autostart

Kubernetes Pod 자동 기동/복구 스킬. 단일 Pod 환경에서 재부팅 후 vLLM/Gateway/Admin 등을 자동 복원.

## 사용 시점

- "재부팅 후 자동 시작", "pod 자동 복구"
- "k8s 자동 시작", "supervisor 등록"
- "노드 재기동 시 서비스 복원"

## 설치

```bash
./install.sh k8s-pod-autostart
```

자동 기동 훅 등록, 의존 순서, 복구 검증 절차는 [SKILL.md](SKILL.md) 참조.
