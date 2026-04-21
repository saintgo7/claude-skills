# Claude Code Skills

| Skill | Description |
|-------|-------------|
| [searcam-book](commands/) | SearCam 기술 서적 챕터 작성 슬래시 커맨드 |
| [exam-system](exam-system/) | 온라인 시험 운영 플레이북 |

## 설치

```bash
# 1. 저장소 clone (install.sh만 필요)
git clone --depth=1 https://github.com/saintgo7/claude-skills.git
cd claude-skills

# 2. 원하는 스킬만 선택 설치
./install.sh --list           # 목록 확인
./install.sh exam-system      # 시험 시스템 스킬 설치
./install.sh searcam-book     # 서적 작성 커맨드 설치

# 3. 삭제
./install.sh --remove exam-system
```

Claude Code 재시작 후 사용 가능.
