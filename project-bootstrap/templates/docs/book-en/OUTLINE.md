# GEM-LLM English Book Detailed OUTLINE (~500p)

> **Project:** GEM-LLM — Concurrent serving of Qwen Coder Dense (31B) and MoE (26B-A4B) on a single 8×B200 node
> **Audience:** LLM serving engineers, ML infra operators, system architects
> **Total length:** ~450p body + 50p appendices = 500p
> **Diagrams:** diagram-01 ~ diagram-40 (shared with Korean book; see `/home/jovyan/gem-llm/docs/diagrams/CATALOG.md`)
> **Note:** This is an exact mirror of `book-ko/OUTLINE.md`; section structure and diagram IDs are identical.

---

## Part I — Foundations — ~80p / 3 Chapters

### Chapter 1. Why GEM-LLM (~25p)
**Learning objectives:**
- Understand the business and technical reasons for serving two models concurrently on a single node
- Grasp the implications of the constraints: 50 concurrent users, OpenAI compatibility, intranet
- Acquire the full roadmap of this book

- 1.1 The current state of the LLM serving market (~3p)
- 1.2 When self-hosting becomes necessary — data sovereignty, cost curve, compliance (~4p)
- 1.3 The five design principles of GEM-LLM (single-node, multi-model, OpenAI-compatible, OAuth-ready, observable) (~4p)
- 1.4 Use scenarios — internal chatbot, code assistant, document summarizer (~4p)
- 1.5 How to read this book (Part-by-Part guide) (~3p)
- 1.6 Prerequisites checklist — accounts, tools, background (~3p)
- 1.7 Terminology — Dense, MoE, Active Param, Tunnel (~4p)
- **Diagrams:** diagram-01, diagram-02
- **Hands-on box:** First call via `curl https://llm.pamout.com/v1/models`

### Chapter 2. Infrastructure — B200, GPFS, K8s Pod (~30p)
**Learning objectives:**
- Understand the actual topology of an 8×B200 node (NVLink/PCIe/memory) and its limits
- Recognize the constraints of Kakao Cloud K8s (no NCCL/RDMA)
- Master model weight placement strategies on GPFS shared storage

- 2.1 NVIDIA B200 — successor to Hopper, FP8/BF16, memory bandwidth (~5p)
- 2.2 Node topology — 8 GPU × 180GB HBM, NVLink domain (~4p)
- 2.3 Kakao Cloud K8s — pod-level placement, NCCL/RDMA disabled environment (~4p)
- 2.4 GPFS distributed file system — sharing model weights/checkpoints (~4p)
- 2.5 CUDA/cuDNN/NCCL version matrix (~3p)
- 2.6 Single-node vs multi-node — why this project is single-node (~4p)
- 2.7 Memory budgeting — co-residency of Dense 31B + MoE 26B (~4p)
- 2.8 Network — Cloudflare Tunnel ingress at a glance (~2p)
- **Diagrams:** diagram-03, diagram-04
- **Code listing:** `Listing 2.1 - Interpreting nvidia-smi topo -m output`

### Chapter 3. The Qwen Coder Model Family (~25p)
**Learning objectives:**
- Understand the structural differences between Qwen2.5-Coder-32B Dense and 26B-A4B MoE
- Grasp the meaning of 4B active parameters and its inference cost impact
- Know the differences in context length, tokenizer, and chat format

- 3.1 Qwen2.5-Coder-32B Dense — architecture overview (~4p)
- 3.2 Qwen3-Coder-30B-A3B MoE — routing, expert count, top-k (~5p)
- 3.3 Tokenizer — SentencePiece, vocab, Korean handling (~3p)
- 3.4 Context length policy — 32K/128K, RoPE scaling (~3p)
- 3.5 Chat template — system/user/assistant format (~3p)
- 3.6 Function (tool) calling capability comparison (~3p)
- 3.7 Model selection guide — when Dense, when MoE (~4p)
- **Diagrams:** diagram-05
- **Code listing:** `Listing 3.1 - Applying chat_template`

---

## Part II — Architecture — ~100p / 4 Chapters

### Chapter 4. System Design Overview (~25p)
**Learning objectives:**
- Understand the role separation across the six components (vLLM x2, Gateway, CLI, Admin UI, Auth)
- Identify synchronous/asynchronous boundaries and queueing points

- 4.1 The six components defined (~3p)
- 4.2 Control plane vs data plane (~3p)
- 4.3 Request lifecycle (CLI → Gateway → vLLM → response) (~4p)
- 4.4 Model routing policy — name-based dispatch (~3p)
- 4.5 Concurrency model — async, semaphore, 50-concurrency handling (~4p)
- 4.6 Failure domains — what dies when which part dies (~4p)
- 4.7 External dependency map (Cloudflare, GPFS, HF Hub) (~4p)
- **Diagrams:** diagram-06, diagram-07

### Chapter 5. Diagram Atlas — GEM-LLM Visualized (~30p)
**Learning objectives:**
- Survey, in one place, the core diagrams used throughout the book
- Build precise interpretive ability for each diagram

- 5.1 Whole-system view (diagram-01, 08) (~5p)
- 5.2 Authentication & authorization flows (diagram-13~16) (~5p)
- 5.3 vLLM topology — TP/PP/EP usage (diagram-17~20) (~6p)
- 5.4 Data model ERD (diagram-21~22) (~4p)
- 5.5 Deployment topology — Cloudflare Tunnel (diagram-25~28) (~4p)
- 5.6 CLI usage flows (diagram-29~32) (~3p)
- 5.7 Monitoring dashboards (diagram-36~38) (~3p)
- **Diagrams:** diagram-01, 06~08, 13~22, 25~32, 36~38

### Chapter 6. Data Model (~22p)
**Learning objectives:**
- Understand the design intent of the five core entities (User/APIKey/Conversation/Message/UsageLog)
- Learn migration strategy and indexing policy

- 6.1 ERD overview (~3p)
- 6.2 User — id, email, role, created_at, oauth_sub (~3p)
- 6.3 APIKey — hashed_key, scope, rate_limit, expires_at (~4p)
- 6.4 Conversation/Message — chat history persistence (~4p)
- 6.5 UsageLog — token in/out, model, latency_ms (~3p)
- 6.6 Indexing/partitioning strategy (~3p)
- 6.7 Migrations — Alembic operation (~2p)
- **Diagrams:** diagram-21, diagram-22
- **Code listing:** `Listing 6.1 - SQLAlchemy model definitions`

### Chapter 7. Security Model (~23p)
**Learning objectives:**
- Understand API key hashing/rotation/revocation mechanisms
- Grasp the rationale and staging of Google OAuth (Phase 2)
- Understand the security boundary provided by Cloudflare Tunnel

- 7.1 Threat model — STRIDE applied (~4p)
- 7.2 API key lifecycle — issue/store/verify/revoke (~4p)
- 7.3 Google OAuth 2.0 — Authorization Code Flow (~4p)
- 7.4 RBAC — admin/user/readonly (~3p)
- 7.5 Rate limiting — per key/user/model (~3p)
- 7.6 Cloudflare Tunnel — applicability of Zero Trust (~3p)
- 7.7 Audit log — who did what when (~2p)
- **Diagrams:** diagram-13, diagram-14, diagram-16
- **Hands-on box:** Issue and revoke an API key end-to-end via the admin console

---

## Part III — Implementation — ~150p / 5 Chapters

### Chapter 8. Model Serving — vLLM 0.17.1 (~35p)
**Learning objectives:**
- Co-host Dense and MoE on one node with vLLM 0.17.1
- Decide on memory partitioning (GPUs 0-3 Dense, 4-7 MoE)

- 8.1 Highlights of vLLM 0.17.1 (~3p)
- 8.2 Engine options — `--tensor-parallel-size`, `--gpu-memory-utilization` (~5p)
- 8.3 Dense model launch (~4p)
- 8.4 MoE model launch — `--enable-expert-parallel`, etc. (~5p)
- 8.5 GPU partitioning strategy across the two models (~5p)
- 8.6 KV cache tuning — block_size, swap (~4p)
- 8.7 Batching/scheduling — continuous batching (~4p)
- 8.8 Logs/metrics — Prometheus exporter (~3p)
- 8.9 Health-check endpoints (~2p)
- **Diagrams:** diagram-17, diagram-18, diagram-19, diagram-20
- **Code listings:** `Listing 8.1 - dense_launch.sh`, `Listing 8.2 - moe_launch.sh`, `Listing 8.3 - vLLM health-check client`
- **Hands-on box:** Bring up Dense on 4 of 8 GPUs and inspect via nvidia-smi

### Chapter 9. The FastAPI Gateway — OpenAI-Compatible API (~35p)
**Learning objectives:**
- Implement `/v1/chat/completions`, `/v1/completions`, `/v1/models`, `/v1/embeddings`
- Route by model name to the two vLLM instances

- 9.1 Mapping the OpenAI spec — what to support (~4p)
- 9.2 Routing — model name → upstream URL (~4p)
- 9.3 Streaming — SSE implementation (~5p)
- 9.4 Authentication middleware — Bearer token parsing (~4p)
- 9.5 Usage logging — async UsageLog writes (~4p)
- 9.6 Error mapping — vLLM → OpenAI error format (~4p)
- 9.7 Backpressure/semaphore — guaranteeing 50 concurrency (~4p)
- 9.8 Dependency injection — FastAPI Depends pattern (~3p)
- 9.9 Integration tests (~3p)
- **Diagrams:** diagram-09, diagram-10
- **Code listings:** `Listing 9.1 - chat_completions handler`, `Listing 9.2 - SSE streaming`, `Listing 9.3 - error mapper`

### Chapter 10. CLI — A Claude-Code-Style Client (~30p)
**Learning objectives:**
- Design the UX of a terminal LLM client
- Implement read/write/edit/bash/grep tools end-to-end

- 10.1 CLI architecture — REPL, command parser, tool runner (~4p)
- 10.2 Credential storage — `~/.gem-llm/credentials` (~3p)
- 10.3 Slash commands — `/help`, `/model`, `/clear`, `/login` (~4p)
- 10.4 Tool: read — file reading (~3p)
- 10.5 Tool: write/edit — file mutation safety (~4p)
- 10.6 Tool: bash — sandboxing/timeouts (~4p)
- 10.7 Tool: grep — wrapping ripgrep (~3p)
- 10.8 Streaming rendering — live markdown render (~3p)
- 10.9 Context management — auto-trim/summarize (~2p)
- **Diagrams:** diagram-29, diagram-30, diagram-31, diagram-32
- **Code listings:** `Listing 10.1 - REPL main loop`, `Listing 10.2 - tool registry`
- **Hands-on box:** Install `gemcli` locally and complete a first conversation

### Chapter 11. Admin Web UI (~25p)
**Learning objectives:**
- Learn the structure of the five core admin screens
- Design navigation for users/keys/usage/model status/audit

- 11.1 Stack — React + Vite, TanStack Query (~3p)
- 11.2 Screen 1: Dashboard — active users, model status (~3p)
- 11.3 Screen 2: User management (~4p)
- 11.4 Screen 3: API key issue/revoke (~4p)
- 11.5 Screen 4: Usage analytics (~4p)
- 11.6 Screen 5: Model control (restart/swap) (~4p)
- 11.7 Permission gating — admin only (~3p)
- **Diagrams:** diagram-33~35
- **Code listing:** `Listing 11.1 - useAuth hook`

### Chapter 12. Phase 2 — Google OAuth Integration (~25p)
**Learning objectives:**
- Migrate from API-key-only to API-key + OAuth in stages
- Master the coexistence model of sessions and keys

- 12.1 Phase 1 vs Phase 2 differences (~3p)
- 12.2 Google Cloud Console setup — OAuth client (~3p)
- 12.3 Authorization Code Flow implementation (~5p)
- 12.4 ID token verification — JWKS, aud, iss (~4p)
- 12.5 Session cookies vs JWT (~3p)
- 12.6 Mapping API keys to OAuth users (~4p)
- 12.7 Logout and session revocation (~3p)
- **Diagrams:** diagram-14, diagram-15
- **Code listing:** `Listing 12.1 - oauth callback handler`

---

## Part IV — Operations — ~70p / 3 Chapters

### Chapter 13. Deployment — Cloudflare Tunnel & K8s (~25p)
**Learning objectives:**
- Configure a Tunnel that safely exposes an intranet K8s pod
- Understand the limits of zero-downtime strategies (rolling/blue-green)

- 13.1 Deployment architecture — all components in one pod (~3p)
- 13.2 Cloudflare Tunnel setup — `cloudflared` (~4p)
- 13.3 `llm.pamout.com` DNS/certificate (~3p)
- 13.4 Environment variables and secrets (~4p)
- 13.5 Automating model weight downloads (~3p)
- 13.6 Health probes (liveness/readiness) (~3p)
- 13.7 Tricks for quasi-zero-downtime model restart (~3p)
- 13.8 Backups — DB dumps, configs (~2p)
- **Diagrams:** diagram-25, diagram-26, diagram-27, diagram-28
- **Code listings:** `Listing 13.1 - cloudflared config.yml`, `Listing 13.2 - K8s Pod manifest`

### Chapter 14. Monitoring & Observability (~25p)
**Learning objectives:**
- Collect and visualize vLLM/Gateway/system metrics with Prometheus + Grafana
- Design alert thresholds

- 14.1 The three signals — metrics/logs/traces (~3p)
- 14.2 vLLM metrics — TTFT, TPOT, queue length (~4p)
- 14.3 Gateway metrics — RPS, p50/p95/p99 (~4p)
- 14.4 GPU metrics — DCGM exporter (~3p)
- 14.5 Logs — JSON structured, request_id tracing (~4p)
- 14.6 Dashboards — seven-panel layout (~4p)
- 14.7 Alerts — Slack webhook (~3p)
- **Diagrams:** diagram-36, diagram-37, diagram-38
- **Code listing:** `Listing 14.1 - prometheus.yml scrape config`

### Chapter 15. Skills, MCP, Hooks (~20p)
**Learning objectives:**
- Port Claude Code's Skills/MCP/Hooks concepts to GEM-LLM CLI
- Design custom automation hooks

- 15.1 Skills — reusable domain actions (~4p)
- 15.2 MCP (Model Context Protocol) overview (~4p)
- 15.3 Hooks — pre-prompt/post-tool hooks (~4p)
- 15.4 Case: in-house Confluence MCP (~3p)
- 15.5 Case: PR auto-review hook (~3p)
- 15.6 Security considerations (~2p)
- **Diagrams:** diagram-39
- **Code listing:** `Listing 15.1 - hook definition JSON`

---

## Part V — Case Studies & Tuning — ~50p / 3 Chapters

### Chapter 16. Real-World Error Cases (~20p)
**Learning objectives:**
- Master the eight production errors and their resolution patterns

- 16.1 GPU OOM — KV cache blow-up (~3p)
- 16.2 vLLM model load failure — out of memory (~3p)
- 16.3 Cloudflare Tunnel disconnections (~2p)
- 16.4 Queue explosion past 50 concurrency (~3p)
- 16.5 GPFS I/O bottleneck during warm-up (~2p)
- 16.6 Tokenizer mismatch (~2p)
- 16.7 Missed OAuth token expiry handling (~2p)
- 16.8 In-flight request loss during model hot-swap (~3p)
- **Diagrams:** diagram-40

### Chapter 17. Performance Tuning (~15p)
**Learning objectives:**
- Measure and tune the throughput (RPS) vs latency (p95) trade-off

- 17.1 Benchmark tools — locust, vegeta (~2p)
- 17.2 KV cache sizing (~3p)
- 17.3 max_num_seqs / max_num_batched_tokens (~3p)
- 17.4 SSE streaming vs non-stream (~2p)
- 17.5 Gateway async worker count (~2p)
- 17.6 Result — p95 < 2s at 50 concurrency (~3p)
- **Diagrams:** diagram-37

### Chapter 18. Scaling Scenarios (~15p)
**Learning objectives:**
- Design the next steps beyond a single node

- 18.1 Multi-node expansion — assuming RDMA-enabled environment (~3p)
- 18.2 Adding model families (Llama, Qwen) (~3p)
- 18.3 RAG integration — vector DB (~3p)
- 18.4 Connecting a fine-tuning pipeline (~3p)
- 18.5 Billing/metering module (~3p)

---

## Appendices — ~50p

- A. Full API Reference (~15p)
- B. Configuration Parameter Dictionary (~10p)
- C. Glossary (~5p)
- D. References (~3p)
- E. Licenses — Qwen, vLLM, FastAPI, etc. (~2p)
- F. FAQ (~5p) — 30 frequently asked questions
- G. Changelog (~2p)
- H. Index (~8p)

---

## Per-Part Page Budget

| Part | # Chapters | Pages |
|---|---|---|
| Part I — Foundations | 3 | 80 |
| Part II — Architecture | 4 | 100 |
| Part III — Implementation | 5 | 150 |
| Part IV — Operations | 3 | 70 |
| Part V — Case Studies | 3 | 50 |
| Appendices | 8 | 50 |
| **Total** | **18 + appendices** | **500** |

---

## Diagrams used in this book
diagram-01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40
