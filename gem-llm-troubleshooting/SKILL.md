---
name: gem-llm-troubleshooting
description: GEM-LLM 운영 중 발생하는 13개 알려진 에러 사례 빠른 참조 + 해결책. 사용 시점 — "에러", "안 돼", "500", "디버그", "OOM", "disk I/O", "QueuePool", "unknown_model", "Connection refused", "layer_scalar", "vLLM 죽었어", "왜 느려". 책 16장 case 1-13의 압축 버전.
---

# gem-llm-troubleshooting

## 빠른 진단 흐름

```
증상 발생 → supervisor.sh status → 빨간 컴포넌트 logs → 아래 13 케이스 매칭
```

## 13 케이스 (책 Ch.16 압축)

### Case 1 — Mermaid 다이어그램 빌드 실패 (구문)
**증상:** `mmdc` 변환 시 syntax error  
**원인:** 다중 공백, 단일 hyphen edge (`-` vs `---`)  
**해결:** CATALOG.md에서 직접 수정 + `scripts/build-diagrams.sh`

### Case 2 — Chromium libs 부재 (puppeteer)
**증상:** `libatk-1.0.so.0: cannot open`  
**해결:** `sudo apt install libatk-bridge2.0-0 libatk1.0-0 libcups2 libdrm2 libgbm1 libgtk-3-0 libnspr4 libnss3 libxcomposite1 libxdamage1 libxfixes3 libxkbcommon0 libxrandr2 libpango-1.0-0 libcairo2 libasound2t64 libxshmfence1 fonts-liberation`

### Case 3 — K-EXAONE 영어 CoT 가정 오류
**증상:** 한국어 응답 거의 없고 영어 CoT 길게  
**해결:** 영어 system prompt + TEACHER_INSTRUCTION으로 한국어 답변 강제

### Case 4 — n1↔master SSH 단방향
**증상:** `ssh master` Connection reset  
**해결:** ~/.ssh/config에 `ProxyCommand /home/jovyan/.local/bin/cloudflared access ssh --hostname vs02-ssh.pamout.com` 사용

### Case 5 — HF cache 862GB 폭증
**해결:** datavol-1 (9.8TB) 활용. 심볼릭 링크 `~/.cache/huggingface → /home/jovyan/wku-vs-01-datavol-1/hf-cache`

### Case 6 — SPEC vs README 불일치
**증상:** CLI 슬래시 명령어 다름  
**해결:** 코드를 source-of-truth로 두고 SPEC을 동기화

### Case 7 — Plan 서브에이전트 read-only
**증상:** `Agent(subagent_type=Plan)`이 Write 도구 없어 SPEC 작성 실패  
**해결:** `subagent_type=general-purpose`로 재디스패치

### Case 8 — vLLM stream `include_usage` 가정
**증상:** SSE 응답에 `usage` trailer 없음  
**해결:** `stream_options.include_usage=True` 명시. 미지원 시 prompt+completion 토큰 별도 추정.

### Case 9 — GPU OOM
**증상:** `OutOfMemoryError`, vLLM 부팅 실패  
**해결:** `--max-model-len 32768` (64K → 32K), `--gpu-memory-utilization 0.85`, KV cache 줄이기

### Case 10 — argon2 분기 인덱스
**증상:** API key 검증이 일부 환경에서 느림  
**해결:** `utils/crypto.py`에서 sha256+salt 단일화 (argon2는 옵션)

### Case 11 — Gemma 4 weight 호환 깨짐 (`layer_scalar`)
**증상:** `KeyError: layer_scalar` vLLM 부팅 실패  
**해결:** **Qwen Coder 듀얼로 전환** (Qwen2.5-Coder-32B + Qwen3-Coder-30B-A3B). 현재 운영 중 모델.

### Case 12 — SQLAlchemy QueuePool 100× 병목
**증상:** 50동접에서 25% 성공, p50=30s, `QueuePool limit of size 5 overflow 10`  
**해결:** `db.py`에 `pool_size=50, max_overflow=150, pool_timeout=10`. 결과 100% 성공, 45 req/s.

### Case 13 — SQLite WAL `mv`로 DB 손상
**증상:** `sqlite3.OperationalError: disk I/O error`, 모든 chat 500  
**원인:** WAL 모드에서 `.db-shm`/`.db-wal` 파일을 살아있는 DB와 함께 `mv`  
**해결:**
1. 손상된 `_data/`를 `_trash/data-broken-<ts>/`로 격리 (`mv`)
2. 빈 `_data/` 만들고 `alembic upgrade head`
3. 사용자/키 재발급

**예방:** WAL 파일은 절대 `mv` 금지. `.gitignore` 추가는 OK. 옮길 필요 있으면 DB 종료 후.

## 증상 → 케이스 매핑

| 키워드 | 후보 케이스 |
|---|---|
| `layer_scalar` / `KeyError` 가중치 | 11 |
| `disk I/O error` SQLite | 13 |
| `QueuePool limit` | 12 |
| `OutOfMemoryError` GPU | 9 |
| `Connection reset by peer` SSH | 4 |
| `unknown model: gem-31b` | 모델명 동기화 (case 11 확장) |
| 한국어 안 나옴 | 3 |
| Cloudflare 502 외부 | n1 cloudflared 죽음 |
| `puppeteer` libatk | 2 |
| Mermaid 빌드 실패 | 1 |

## 일반 디버깅 순서

1. `bash scripts/supervisor.sh status` — 어디 빨간색?
2. `tail -50 _logs/<failed-service>.log` — Traceback 위치
3. `grep -B2 -A5 "ERROR\|Exception\|raise" _logs/<service>.log | tail -30` — 핵심 에러
4. 위 13 케이스 매핑
5. 케이스 없음 → `gem-llm-overview` + 책 Ch.16 직접 참조

## 참조

- 책 한국어 Ch.16: `/home/jovyan/gem-llm/docs/book-ko/parts/part-5/16-error-cases.md` (전체 사례)
- 책 영문 Ch.16: 동일 파일 영문판
- 매뉴얼 Troubleshooting: `docs/manual-{ko,en}/chapters/04-troubleshooting.md`
