# api-route-consistency-pattern

Gateway 라우트 ↔ CLI/admin-cli 호출 ↔ 매뉴얼 ↔ 테스트 4-way 일관성 검증 패턴. gem-llm case 20 (admin-cli `list-keys` 4xx silent fail) 사후 분석에서 추출.

## 사용 시점

- "admin-cli가 빈 결과 (silent fail)"
- "라우트 변경 후 매뉴얼/CLI/테스트 outdated"
- "API contract drift 방지"

## 설치

```bash
./install.sh api-route-consistency-pattern
```

## 빠른 시작

```bash
mkdir -p scripts
cp ~/.claude/skills/api-route-consistency-pattern/scripts/*.template scripts/
# .template 제거 + repo 형태에 맞게 GATEWAY_MODULE / CLI_FILE / MANUAL_GLOB 수정
```

## 자세한 사용법

[SKILL.md](SKILL.md)
