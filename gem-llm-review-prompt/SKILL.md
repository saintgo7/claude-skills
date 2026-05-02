---
name: gem-llm-review-prompt
description: Review and critique prompts (system prompts, few-shot exemplars, tool descriptions, dataset prompts) used in the GEM-LLM project for clarity, leakage, ambiguity, length, language-mix risk, and Gemma/EXAONE-specific failure modes. Use when the user says "프롬프트 리뷰", "이 프롬프트 봐줘", "system prompt 리뷰", "few-shot 검토", "프롬프트 개선", "프롬프트 평가", "tool description 리뷰". Produces a structured rubric (clarity / specificity / safety / format / language / token-cost) with concrete rewrite suggestions. Knows that K-EXAONE produces English CoT, so Korean output requires explicit constraints.
---

# gem-llm-review-prompt

GEM-LLM 프로젝트에서 사용하는 프롬프트(시스템 프롬프트, few-shot, tool description, 데이터 생성 템플릿) 리뷰 스킬.

## When to use

- "이 프롬프트 봐줘", "프롬프트 리뷰"
- "system prompt 개선"
- "few-shot 예시 평가"
- "tool description 리뷰"
- "데이터 생성 프롬프트 검토"
- "프롬프트가 왜 이상한 응답을 내는지"

## Project-specific context (memory)

- 메인 모델: K-EXAONE 기반 — **영어로 CoT 사고** 후 출력. 한국어 응답을 원하면 system prompt에 명시:
  > Always think in English internally but respond ONLY in Korean.
- 데이터 생성: 영어 프롬프트 사용이 거의 필수
- Gemma 4 tool calling: hermes parser 사용 → JSON 인용/escape 엄격

## Review rubric (출력 형식)

각 프롬프트에 대해 다음 6축으로 점수(1~5) + 근거 + 개선안:

1. **Clarity** — 모호한 지시어("적절히", "잘", "필요시") 제거됐는가
2. **Specificity** — 출력 형식(JSON/마크다운/plain)/길이/언어 명시됐는가
3. **Safety / leakage** — 시스템 지시어가 사용자에게 노출될 위험
4. **Format constraints** — 코드블록, JSON schema, 헤더 레벨 등 일관성
5. **Language strategy** — CoT 언어 vs 출력 언어 분리 명시
6. **Token cost** — 불필요 반복, 중복 예시, 장문 boilerplate

## Common findings (체크리스트)

- [ ] system prompt 안에 사용자 input 직접 인용 없음 (prompt injection 방지)
- [ ] few-shot 예시들이 출력 형식을 모두 동일하게 따름
- [ ] tool description에 "when to call" / "when NOT to call" 둘 다 있음
- [ ] JSON schema 의 `required` 필드와 예시 일치
- [ ] 한국어 출력 요청 시 "한국어로만 답하라" 명시 (영어 CoT 흘러나옴 방지)
- [ ] `temperature`, `max_tokens` 같은 모델 파라미터와 prompt 의도 충돌 없음
- [ ] 마크다운 vs plain text 혼재 없음

## Procedure

1. 사용자가 제시한 프롬프트 전문을 그대로 인용
2. 6축 rubric 표 출력
3. 가장 시급한 3가지 문제 우선순위
4. 각 문제별 **rewrite 예시** 제공 (before/after)
5. 토큰 절감 가능량 추정

## Output template

```
## 리뷰 대상
<원본 프롬프트>

## 점수 (1=최악, 5=최상)
| 축 | 점수 | 근거 |
|---|---|---|
| Clarity | x/5 | ... |
| Specificity | x/5 | ... |
| Safety | x/5 | ... |
| Format | x/5 | ... |
| Language | x/5 | ... |
| Token cost | x/5 | ... |

## Top 3 issues
1. ...
2. ...
3. ...

## Rewrite (제안)
<개선판>

## 토큰 절감 추정
원본 ~N tokens -> 제안 ~M tokens (-K%)
```

## Safety

- 사용자 프롬프트의 비공개 정보(API key, 내부 URL)가 보이면 즉시 마스킹 안내
- 외부 모델 평가 호출 금지 (로컬 vllm만 사용)
