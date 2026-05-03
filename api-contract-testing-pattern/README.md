# api-contract-testing-pattern

FastAPI/REST API contract 테스트 검증된 패턴. smoke (라우트 존재 + 200 OK)만으로 부족할 때, 응답 schema/openapi.json 스냅샷/happy & error path/정확한 status code 까지 검증한다. gem-llm case 20 회귀 방지 17/17 smoke + contract 패턴을 일반화.

## 사용 시점

- "contract test", "API 명세 검증", "openapi snapshot"
- "schema validation", "response shape", "API drift 감지"
- "200 OK는 충분치 않음", "router 통합 테스트"

## 설치

```bash
./install.sh api-contract-testing-pattern
```

## 빠른 시작

```bash
mkdir -p tests/contract
cp ~/.claude/skills/api-contract-testing-pattern/templates/*.template tests/contract/
# .template 제거 + APP_IMPORT / EXPECTED_ROUTES / ResponseSchema 본 프로젝트에 맞게 수정
pytest tests/contract/ -m contract --tb=short
```

## 자세한 사용법

[SKILL.md](SKILL.md)
