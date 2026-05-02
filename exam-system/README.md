# exam-system skill

Flask 기반 온라인 시험 시스템 운영을 위한 Claude Code 플레이북.
시험 당일 모니터링, 돌발 상황 대응, 사후 통계까지 커버.

## 설치

```bash
cp -r exam-system/ ~/.claude/skills/
```

Claude Code 세션에서 "시험 모니터링 해줘" 등으로 호출.

## 구성

```
exam-system/
├── SKILL.md          — 트리거 문구 & 핵심 설계 결정사항
├── playbook.md       — 시험 전/중/후 단계별 운영 가이드
├── scripts/          — 즉시 실행 가능한 운영 스크립트
│   ├── monitor.sh          실시간 대시보드
│   ├── db_snapshot.py      제출 현황 스냅샷
│   ├── auto_reset.py       실수 제출 자동 삭제
│   ├── extend_exam.py      시험 시간 연장
│   ├── revert_on_submit.sh 제출 감지 후 자동 원복
│   ├── check_student.py    학생별 상태 조회
│   ├── final_summary.py    최종 통계 리포트
│   └── security_check.sh   사후 보안 감사
└── templates/        — 재사용 코드 템플릿
    ├── models.py           Quiz/QuizAttempt SQLAlchemy 모델
    ├── exam_api.py         시험 GET/POST API 라우트
    ├── anti_cheat.js       부정행위 방지 JS
    ├── seed_exam_example.py 문제 시딩 예시
    ├── docker-compose.yml  프로덕션 Docker 구성
    └── Dockerfile.prod     gunicorn + healthcheck
```

## 주요 환경변수

| 변수 | 설명 |
|------|------|
| `CONTAINER_NAME` | Docker 컨테이너 이름 |
| `QUIZ_ID` | 시험 Quiz row ID (기본값 1) |
| `EXAM_URL` | 공개 시험 URL |

각 스크립트마다 추가 환경변수는 파일 상단 docstring 참조.
