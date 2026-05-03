---
name: coverage-instrumentation-pattern
description: 'Python 3.12+ coverage 측정 도구 선택 (ctrace vs sysmon) 패턴. 사용 시점 — "coverage missing", "async 라인 누락", "Python 3.12 coverage", "pytest --cov 부정확", "sys.monitoring", "PEP-669", "FastAPI coverage", "httpx TestClient coverage". COVERAGE_CORE=sysmon 환경변수 + CI gate 적정값 + 도구 검증.'
---

# Coverage Instrumentation Pattern (ctrace vs sysmon)

Python 3.12+ 환경에서 `pytest --cov` 측정값이 의심스러울 때 — 특히 async/await + FastAPI + httpx 가 섞인 경우 — coverage backend (`ctrace` vs `sysmon`) 를 비교하고 올바른 backend 를 선택하는 패턴.

## 1. 사용 시점

다음 조건 중 하나라도 해당하면 이 패턴 적용:

- **Python 3.12+** 환경 (PEP-669 sys.monitoring 지원)
- **async/await + FastAPI** 또는 **httpx ASGI TestClient** 사용
- **테스트를 추가했는데 coverage 가 늘어나지 않음** — 의심스러움
- `pytest --cov` 결과가 코드 직접 검증과 어긋남
- coverage backend 비교가 필요함 (CI gate 재산정 등)

핵심: **default `ctrace` backend 는 Python 3.12 의 async/asyncio 진입점 일부를 놓침**. `sys.monitoring` (PEP-669) 기반 `sysmon` backend 가 정확.

## 2. ctrace vs sysmon 비교

| 백엔드 | 내부 API | Python 버전 | 정확도 (3.12 async) | 성능 | 권장 |
|---|---|---|---|---|---|
| `ctrace` (default) | `sys.settrace` | 모든 버전 | **낮음** (라인 누락) | 느림 | 3.11 이하 호환용 |
| `sysmon` | `sys.monitoring` (PEP-669) | **3.12+** | **높음** | 빠름 (~10-30%) | **3.12+ 권장** |

`sysmon` 은 Python 3.12 에서 추가된 monitoring API 를 사용하므로 async frame, generator, ASGI middleware 같은 진입점도 정확히 포착한다. `ctrace` 는 settrace 의 한계로 일부 async 콜스택에서 라인을 누락한다.

## 3. 활성화 방법

### 3.1 환경변수 (가장 단순)

```bash
COVERAGE_CORE=sysmon pytest --cov=src/
```

### 3.2 .coveragerc

```ini
[run]
core = sysmon
source = src/
```

### 3.3 pyproject.toml

```toml
[tool.coverage.run]
core = "sysmon"
source = ["src/"]
```

세 방법 모두 동등. CI 에서는 환경변수가 가장 명시적이고 디버깅이 쉽다.

## 4. 검증된 사례 (gem-llm case 23)

테스트 코드는 동일, **backend 만 변경** 해서 측정한 결과:

| 모듈 | ctrace | sysmon | 차이 |
|---|---|---|---|
| `gateway/admin.py` | 47% | **100%** | +53pt |
| `admin-ui/users.py` | 49% | **100%** | +51pt |
| `admin-ui/keys.py` | 50% | **100%** | +50pt |
| `gateway/proxy.py` | 22% | **78%+** | +56pt |
| `gateway/crypto.py` | 39% | **72%+** | +33pt |

→ ctrace 가 보고하던 "missing 라인" 의 절반 이상이 **거짓 음성** 이었음. 실제로는 테스트가 해당 라인을 통과했지만 settrace 가 async 콜스택에서 놓친 것.

이 사례는 책 16장 case 23 (Python 3.12 ctrace 한계 발견) 으로 정리되어 있다.

## 5. CI gate 적정값

**중요**: ctrace 기준 gate 를 그대로 sysmon 으로 옮기면 시작부터 통과해버려 의미가 없다. **backend 변경 시 gate 재산정 필수**.

| backend | 권장 gate (실측 - 5pt 마진) |
|---|---|
| ctrace | gateway 75 / cli 65 / admin 75 |
| **sysmon** | gateway 85 / cli 80 / admin 90 |

원칙: 실측치에서 5pt 빼서 — 일시적 변동 흡수 + 회귀 차단 둘 다 만족.

## 6. CI workflow 통합

```yaml
- name: pytest --cov (sysmon)
  env:
    COVERAGE_CORE: sysmon   # ← Python 3.12 정확 측정
  run: pytest --cov=src/ --cov-fail-under=85
```

`coverage>=7.4` 권장 (sysmon backend 안정 버전). `coverage>=7.6` 이면 더 안전.

## 7. 이중 측정 (의심 시)

테스트 추가했는데 coverage 가 안 늘어나면 두 backend 로 동시에 측정해서 비교한다:

```bash
echo "=== ctrace (default) ==="
pytest --cov=src/ --cov-report=term

echo "=== sysmon (PEP-669) ==="
COVERAGE_CORE=sysmon pytest --cov=src/ --cov-report=term
```

**차이 > 10pt** → ctrace 한계, sysmon 으로 전환.
**차이 < 2pt** → sync-only 코드, 둘 다 동등.

## 8. 흔한 함정

| 증상 | 원인 | 해결 |
|---|---|---|
| 테스트 추가했는데 coverage 안 늘어남 | ctrace async 미계측 | `COVERAGE_CORE=sysmon` |
| async route 일부 라인 missing | ctrace + httpx ASGI 한계 | sysmon |
| CI gate 항상 fail | 백엔드 변경 후 게이트 안 바꿈 | 재산정 (5장) |
| Python 3.11 에서 sysmon 시도 | PEP-669 미지원 | Python 3.12+ 필수 |
| 측정값이 100% 인데 missing 라인 보임 | ctrace 의 거짓 음성 | sysmon 으로 재측정 |
| sysmon 에서도 안 늘어남 | 진짜 미테스트 | 테스트 추가 필요 |

## 9. 트러블슈팅 한 줄 진단

```bash
# 현재 설정된 backend 확인
python3 -c "import coverage; print(coverage.Coverage().config.run_core)"
# → "ctrace" 또는 "sysmon"
```

```bash
# coverage 버전 확인 (sysmon 은 7.4+ 필요)
python3 -c "import coverage; print(coverage.__version__)"
```

```bash
# Python 버전 확인 (sysmon 은 3.12+ 필요)
python3 --version
```

## 10. 관련 패턴

- **`pytest-fastapi-pattern`**: 단위 테스트 작성 (httpx async + ASGITransport + lifespan)
- **`cicd-github-actions-pattern`**: CI 통합 (sysmon gate workflow)
- **`api-contract-testing-pattern`**: 행동 검증 (커버리지가 100% 라도 contract 따로 검증)
- **`production-postmortem-pattern`**: case 23 (gem-llm 발견 사례 → 책 16장)

## 11. 참고

- **PEP-669** — Low Impact Monitoring for CPython
  https://peps.python.org/pep-0669/
- **coverage.py docs** — sys.monitoring backend
  https://coverage.readthedocs.io/en/latest/cmd.html#sys-monitoring
- **gem-llm case 23** (book ch.16) — Python 3.12 ctrace 한계 발견 사례
  47% → 100% (admin.py, users.py), backend 변경만으로 +50pt 달성

## 템플릿

- `templates/pytest-cov-config.toml.template` — pyproject.toml coverage 설정 (sysmon 활성화 + fail_under)
- `templates/ci-coverage.yml.template` — GitHub Actions workflow (Python 3.12 + sysmon)
