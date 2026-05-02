# env-isolation-pattern

운영 환경변수가 테스트/마이그레이션에 누설되어 **운영 DB 가 wipe** 되는 사고 방지 (case 18 일반화).

## 사용 시점

- "테스트가 운영 DB 건드림"
- `os.environ.setdefault(...)` 가 안 먹힘
- supervisor 가 `set -a; source .env; set +a` 로 export
- destructive test (drop_all, truncate) 가 prod 와 한 끗 차이

## 설치

```bash
./install.sh env-isolation-pattern
```

3 패턴 (explicit unset / unconditional override / container isolation), 약한 방어 vs 강한 방어, 누설 경로 7 가지, 검증 방법은 [SKILL.md](SKILL.md) 참조.
