# GEM-LLM English Manual OUTLINE

> **Composition:** Three manuals — User Guide / Admin Guide / Troubleshooting
> **Audience:** End users, internal admins, ops team
> **Diagrams:** `/home/jovyan/gem-llm/docs/diagrams/CATALOG.md`
> **Note:** Mirror of `manual-ko/OUTLINE.md`; section structure and diagram IDs identical.

---

# Part 1. User Guide

## 1. Getting Started (~10p)
**Learning objectives:**
- Log in to GEM-LLM and send your first request

- 1.1 What is GEM-LLM — one-line summary
- 1.2 Supported models (Qwen2.5-Coder-32B Dense / 26B-A4B MoE)
- 1.3 Endpoint — `https://llm.pamout.com`
- 1.4 Prerequisites — corporate account, client environment
- 1.5 First request in five minutes (curl example)
- **Diagrams:** diagram-02
- **Hands-on box:** Hello world via curl

## 2. Installation (~10p)
- 2.1 CLI install — `pip install gem-llm-cli` (working name)
- 2.2 System requirements
- 2.3 macOS / Linux / Windows (WSL) install
- 2.4 Verify install — `gemcli --version`
- 2.5 Auto-update option
- **Code listing:** `Listing 2.1 - install script`

## 3. Login & Authentication (API key) (~8p)
- 3.1 Obtaining an API key (admin request workflow)
- 3.2 The `gemcli login` command
- 3.3 Credential file — `~/.gem-llm/credentials`
- 3.4 Environment variable — `GEM_LLM_API_KEY`
- 3.5 Key rotation and expiry
- **Diagrams:** diagram-13

## 4. CLI Basics (~12p)
- 4.1 Start a conversation — `gemcli chat`
- 4.2 Model selection — `--model qwen2.5-coder-32b-dense` / `qwen3-coder-30b-moe`
- 4.3 System prompt
- 4.4 Streaming output
- 4.5 Save/load conversations
- 4.6 Multi-line input
- **Diagrams:** diagram-29

## 5. Tools — read/write/edit/bash/grep (~15p)
- 5.1 read — file reading example
- 5.2 write — creating new files
- 5.3 edit — partial mutation of an existing file
- 5.4 bash — execution & safety policy
- 5.5 grep — codebase search
- 5.6 Auto vs manual tool invocation
- **Code listing:** `Listing 5.1 - read/write workflow`
- **Diagrams:** diagram-30

## 6. Slash Commands (~8p)
- 6.1 `/help`
- 6.2 `/model` — switch model
- 6.3 `/clear` — reset context
- 6.4 `/login` / `/logout`
- 6.5 `/usage` — personal usage
- 6.6 `/save`, `/load`
- 6.7 `/exit`
- **Diagrams:** diagram-31

## 7. Using the OpenAI-Compatible SDK (~8p)
- 7.1 Python SDK (`openai` library)
- 7.2 Setting `base_url` — `https://llm.pamout.com/v1`
- 7.3 chat.completions / embeddings
- 7.4 LangChain integration
- 7.5 Node.js SDK example
- **Code listing:** `Listing 7.1 - openai-py call`

## 8. Quotas & Etiquette (~5p)
- 8.1 50-concurrent-user cap
- 8.2 Token / RPM quotas
- 8.3 Sensitive-data input policy
- 8.4 What to do when answers are poor

---

# Part 2. Admin Guide

## 9. Admin Web UI Overview (~6p)
- 9.1 Access — `/admin`
- 9.2 Five-screen layout
- 9.3 Permission model (admin / user / readonly)
- **Diagrams:** diagram-33

## 10. User Management (~8p)
- 10.1 Add user — email + role
- 10.2 Disable/delete users
- 10.3 Change roles
- 10.4 OAuth auto-provisioning policy (Phase 2)
- **Diagrams:** diagram-34

## 11. API Key Issue/Revoke (~10p)
- 11.1 Issue a new key — TTL, scope, rate limit
- 11.2 List keys
- 11.3 Immediate revocation
- 11.4 Auto rotation
- 11.5 Suspected leak procedure
- **Diagrams:** diagram-13
- **Hands-on box:** Issue → use → revoke walkthrough

## 12. Usage Monitoring (~10p)
- 12.1 Daily/weekly/monthly token usage
- 12.2 Breakdown by model/user
- 12.3 Anomaly detection
- 12.4 CSV export
- 12.5 Grafana dashboard link
- **Diagrams:** diagram-37

## 13. Model Control (~10p)
- 13.1 Inspect current state of both models
- 13.2 Model restart — safe procedure
- 13.3 Hot-swap weights
- 13.4 Handling GPU memory limits
- **Diagrams:** diagram-28
- **Code listing:** `Listing 13.1 - model restart script`

## 14. Backup & Restore (~8p)
- 14.1 DB dump (PostgreSQL pg_dump)
- 14.2 Configuration backup
- 14.3 Log retention policy
- 14.4 Restore drills
- **Code listing:** `Listing 14.1 - backup cron`

## 15. Security Checklist (~6p)
- 15.1 Confirm API key hashing
- 15.2 Cloudflare Tunnel status
- 15.3 OAuth client-secret rotation
- 15.4 Audit-log review cadence
- 15.5 Incident response playbook

---

# Part 3. Troubleshooting

Each entry: **[Symptom] / [Verbatim error message] / [Cause] / [Resolution] / [Prevention]**

## 16. Authentication (~10p)
- 16.1 `401 Unauthorized: Invalid API key`
- 16.2 `403 Forbidden: Insufficient scope`
- 16.3 OAuth redirect mismatch — `redirect_uri_mismatch`
- 16.4 ID token verification failed — `aud` mismatch
- 16.5 Missing session-expiry handling
- **Diagrams:** diagram-13, diagram-14

## 17. Model Load Failures (~10p)
- 17.1 `CUDA out of memory: tried to allocate ...`
- 17.2 `RuntimeError: model weights not found` — GPFS path issue
- 17.3 `ImportError: vllm.engine.llm_engine` — version mismatch
- 17.4 Tokenizer mismatch — missing `tokenizer.json`
- 17.5 Hugging Face download failure
- **Diagrams:** diagram-19

## 18. GPU OOM (~8p)
- 18.1 KV cache blow-up patterns
- 18.2 Tuning `gpu-memory-utilization`
- 18.3 Reducing `max_model_len`
- 18.4 Capping concurrent requests

## 19. Token / Rate Limits (~6p)
- 19.1 `429 Too Many Requests`
- 19.2 `400 BadRequest: token limit exceeded`
- 19.3 Recommended auto-retry policy

## 20. Network / Tunnel (~8p)
- 20.1 `cloudflared connection lost` — restart Tunnel
- 20.2 DNS propagation delay
- 20.3 `502 Bad Gateway` — upstream vLLM down
- 20.4 SSE stream cut (proxy buffering)
- **Diagrams:** diagram-26, diagram-40

## 21. Performance Degradation (~8p)
- 21.1 TTFT spike — queue backlog
- 21.2 TPOT spike — GPU contention with the other model
- 21.3 GPFS I/O lag during warm-up
- 21.4 Log explosion filling disk

## 22. Data / DB (~6p)
- 22.1 Alembic migration conflicts
- 22.2 UsageLog table bloat — partitioning
- 22.3 PostgreSQL connection pool exhaustion

## 23. CLI Client (~6p)
- 23.1 `~/.gem-llm/credentials` permission errors
- 23.2 Proxy environments (`HTTPS_PROXY`)
- 23.3 Colors/Unicode breakage on Windows
- 23.4 Tool execution permissions

## 24. FAQ (~5p)
- 24.1 Which model to use
- 24.2 Korean vs English quality differences
- 24.3 Where logs are stored
- 24.4 Usage in air-gapped environments
- 24.5 Is fine-tuning supported

---

## Diagrams used in this manual
diagram-02, 13, 14, 19, 26, 28, 29, 30, 31, 33, 34, 37, 40
