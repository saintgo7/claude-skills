# korean-tech-blog-authoring

한국어 기술 블로그/아티클/매뉴얼/책 챕터 작성을 위한 6 원칙 (격식체, 영문 식별자, 기술 용어, 코드 인용, 다이어그램, 구조) + 한국어 특화 함정 (혼용 문체, 번역체, 수동태 남용, AI 흔적).

## 사용 시점

- "한국어 기술 글 / 한글 아티클 / 기술서적 챕터 / 한국어 자연스럽게"
- "격식체 vs 평어 / 영문 식별자 어디까지 / 한국어 기술 용어"
- "AI 번역 흔적 빼기 / 번역체 정리"

## 설치

```bash
./install.sh korean-tech-blog-authoring
```

6 원칙 + 좋은/나쁜 예시 + 한/영 mirror 가이드 + 길이 가이드는 [SKILL.md](SKILL.md). 시작용 템플릿은 [templates/blog-post.md.template](templates/blog-post.md.template). 한/영 동시 운영은 `bilingual-book-authoring`, 빌드 인프라는 `pandoc-bilingual-build`.
