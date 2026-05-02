# pandoc-bilingual-build

Pandoc + XeTeX로 한/영 동시 책/매뉴얼/논문 빌드 파이프라인을 기존 프로젝트에 추가하는 스킬.

## 사용 시점

- "Pandoc 빌드 파이프라인", "한영 책 빌드 추가"
- "IEEEtran 논문 템플릿", "KCI 논문"
- "Mermaid SVG 빌드"
- "한글 PDF 안 됨", "xeCJK 셋업"

## 설치

```bash
./install.sh pandoc-bilingual-build
```

`project-bootstrap`의 빌드 부분만 분리한 스킬. 4 포맷 (PDF/DOCX/TEX/MD) × 6 타겟 매핑은 [SKILL.md](SKILL.md) 참조.
