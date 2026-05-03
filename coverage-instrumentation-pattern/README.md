# coverage-instrumentation-pattern

Python 3.12+ coverage 측정 도구 선택 (ctrace vs sysmon) 패턴.

`pytest --cov` 결과가 의심스러울 때 (특히 async/await + FastAPI + httpx ASGI),
`COVERAGE_CORE=sysmon` (PEP-669 sys.monitoring) 으로 전환하여 정확 측정.

## 검증된 효과 (gem-llm case 23)

테스트 변경 X, backend 만 sysmon 으로 전환:

- `gateway/admin.py` 47% → **100%**
- `admin-ui/users.py` 49% → **100%**
- `gateway/proxy.py` 22% → **78%+**

→ ctrace 의 거짓 음성 (async 콜스택 미계측) 제거.

## 빠른 사용

```bash
COVERAGE_CORE=sysmon pytest --cov=src/
```

## 설치

```bash
./install.sh coverage-instrumentation-pattern
```

자세한 내용은 SKILL.md 참고.
