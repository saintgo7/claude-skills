# deployment-checklist

LLM/API 서비스 production 배포 전 체크리스트 — 7 영역 × 5~10 항목 = **56 항목**. GEM-LLM 28일 운영 + 219 테스트 + 100 동접 부하 통과 후 역산.

## 사용 시점

- "배포 체크리스트", "production ready"
- "go-live", "런칭 점검"
- "사전 검증 체크"

## 설치

```bash
./install.sh deployment-checklist
```

7 영역 (인증 / 보안 / 모니터링 / 스케일 / 문서 / 롤백 / 외부) 항목 + Go-Live 단축판 5 + GEM-LLM 87% 충족 사례는 [SKILL.md](SKILL.md). 새 프로젝트 배포에는 [templates/checklist.md.template](templates/checklist.md.template) 복사.
