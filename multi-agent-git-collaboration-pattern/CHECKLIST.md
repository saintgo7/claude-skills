# multi-agent-git-collaboration-pattern — 체크리스트

## A. 신규 skill 추가 시 (10 항목)

- [ ] `git pull --rebase origin main` 으로 최신 동기화
- [ ] 새 디렉토리 생성 (`<skill-name>/`) 및 SKILL.md / README.md 작성
- [ ] frontmatter `name` / `description` (≤1024 char) 작성
- [ ] templates / CHECKLIST / 기타 보조 파일 작성
- [ ] install.sh REGISTRY 에 entry 추가 (자기 카테고리 anchor 다음)
- [ ] entry 형식: `"<name>|skill|<description>"`
- [ ] `.githooks/pre-commit` 활성화 확인 (`git config core.hooksPath`)
- [ ] `git status` 로 같은 commit에 SKILL.md + install.sh 모두 staging 확인
- [ ] atomic commit (메시지 본문 + Co-Authored-By)
- [ ] push (실패 시 §B 절차)

## B. race 발생 시 회복 (8 항목)

- [ ] 패닉 금지 — force push / 전체 Write 덮어쓰기 시도 금지
- [ ] Edit "modified since read" 라면 → §B-1, push 거부라면 → §B-2
- [ ] (B-1) `grep -n "<pattern>" <file>` 로 다른 에이전트 변경 확인
- [ ] (B-1) Read tool 재실행 → 자기 anchor 영향 없음 검증 → Edit 재시도
- [ ] (B-2) `git pull --rebase origin main`
- [ ] (B-2) rebase conflict 시 양쪽 변경 모두 보존
- [ ] (B-2) hook이 diff 비어 reject 시 description 미세 갱신
- [ ] (B-2) `git push origin main` 재시도 (1-2회)

## C. pre-commit hook 설치 검증 (5 항목)

- [ ] `.githooks/pre-commit` 파일 존재 + 실행 권한
- [ ] `git config core.hooksPath` 결과가 `.githooks`
- [ ] dummy commit (SKILL.md 만 add) → 거부 확인
- [ ] dummy commit (install.sh entry 만 add) → 거부 확인
- [ ] dummy commit (둘 다 add) → 통과 확인 후 reset
