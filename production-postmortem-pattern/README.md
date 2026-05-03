# production-postmortem-pattern

운영 사고 postmortem (사후분석) 검증된 패턴. 7-section 형식 (영역/시점/증상/근본원인/해결/예방/교훈) + 액션 아이템 추적 + 책 case 통합. gem-llm 책 16장 case 1-20 (53시간 사고)에서 검증.

## 사용 시점

- 운영 장애 / 데이터 손실 / 보안 사고 / silent bug 사후분석
- 사고 → 패턴 → skill 추출
- 사내 postmortem → 책 case study 통합 (익명화)

## 설치

```bash
./install.sh production-postmortem-pattern
```

## 빠른 시작

```bash
mkdir -p docs/postmortems
cp ~/.claude/skills/production-postmortem-pattern/templates/postmortem.md.template \
   docs/postmortems/$(date +%F)-incident.md
```

## 자세한 사용법

[SKILL.md](SKILL.md)
