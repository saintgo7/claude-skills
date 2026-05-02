# bilingual-book-authoring

한/영 두 권을 동시에 써내려가는 기술서적 저작 워크플로 (~1000p 검증).

## 사용 시점

- "한/영 책 동시에 쓰자", "기술서적 한 번에 양쪽 언어로"
- "OUTLINE 한/영 mirror", "다이어그램 카탈로그 한/영 공유"
- "병렬로 책 본문 작성", "Part 멀티 에이전트 분산"
- "직역 말고 자연스러운 영어로 동시 작성"
- "에러 사례 챕터 (실제 운영 사례)"

## 설치

```bash
./install.sh bilingual-book-authoring
```

OUTLINE mirror 방식, 다이어그램 ID 공유 규칙, Part별 멀티에이전트 디스패치, 한/영 미세 차이 처리 (idiom vs 자연스러움), 에러 사례 수집 패턴은 [SKILL.md](SKILL.md) 참조.

빌드 인프라만 필요 → `pandoc-bilingual-build` / 병렬 디스패치 일반 패턴 → `multi-agent-orchestrator` / 빈 프로젝트부터 → `project-bootstrap`.
