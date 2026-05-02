# mermaid-diagram-authoring

Mermaid 다이어그램 작성 + Pandoc 통합 5단계 (CATALOG.md → extract-mmd → mmdc SVG → Lua filter → 본문 참조). GEM-LLM 한/영 책 40 다이어그램 (36 한/영 공유) 검증.

## 사용 시점

- "다이어그램 작성", "mermaid 카탈로그", "mmdc 빌드"
- "SVG 자동 삽입", "한글 라벨 다이어그램", "syntax error mermaid"

## 설치

```bash
./install.sh mermaid-diagram-authoring
```

5단계 워크플로, 6 카테고리, mermaid syntax 함정 (case 1), 한글 폰트 설정은 [SKILL.md](SKILL.md) 참조.
