# bulk-user-onboarding-pattern

CSV/JSON 사용자 일괄 등록 검증된 패턴 (admin API + 1회 list-users 캐싱 + 신규/중복/실패 3카운터). GEM-LLM 76 users (50 bulk + 26 수동) 등록 + idempotent 50/50 dup_count 검증 + 100동접 부하에서 모든 키 인증 통과.

## 사용 시점

- "bulk add", "bulk register", "CSV 일괄"
- "사용자 마이그레이션", "idempotent 사용자 등록"
- "신규 vs 중복 카운트"

## 설치

```bash
./install.sh bulk-user-onboarding-pattern
```

CSV 형식, idempotent 핵심 패턴, 3카운터 출력, 키 자동 발급, JSON 변형, 함정 7가지, 보안 5원칙은 [SKILL.md](SKILL.md) 참조. 즉시 쓸 수 있는 셸 스크립트는 [scripts/bulk-users.sh.template](scripts/bulk-users.sh.template).
