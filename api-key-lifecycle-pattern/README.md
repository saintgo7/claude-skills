# api-key-lifecycle-pattern

API key 발급/회수/검증 라이프사이클 패턴 (`gem_live_<32hex>` 형식 + prefix 8자 lookup + SHA256+salt hash). GEM-LLM Gateway 의 `admin-cli` (issue-key / list-keys / revoke-key / set-quota) 가 28일 운영 + 200 동접 부하에서 검증.

## 사용 시점

- "api key 발급 / 회수 / rotation" 설계
- "raw key 노출 범위", "key prefix lookup 인덱스"
- "argon2 vs sha256" 선택

## 설치

```bash
./install.sh api-key-lifecycle-pattern
```

키 형식, DB 스키마, 발급/검증/회수 코드, 보안 5원칙, 함정 5가지, admin-cli 표준은 [SKILL.md](SKILL.md) 참조.
