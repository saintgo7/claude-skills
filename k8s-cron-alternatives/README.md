# k8s-cron-alternatives

K8s pod / 컨테이너 환경 (cron / systemd 미설치) 정기 작업 자동화 패턴 5종.

## 사용 시점

- "cron 없는 환경 정기 작업"
- "k8s 정기 작업", "watchdog daemon", "k8s CronJob"
- "external scheduler", "@reboot 대체"

## 설치

```bash
./install.sh k8s-cron-alternatives
```

5 패턴 비교, watchdog/CronJob 템플릿, 흔한 함정은 [SKILL.md](SKILL.md) 참조.
