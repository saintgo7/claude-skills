# GEM-LLM English R&D Paper OUTLINE (IEEE/ACM Conference, 8–12p)

> **Format:** IEEE conference (or ACM sigconf) double-column, 8–12 pages including references
> **Diagrams:** see `/home/jovyan/gem-llm/docs/diagrams/CATALOG.md`

---

## Title Candidates
1. **GEM-LLM: Co-Hosting Dense and MoE Large Language Models on a Single 8×B200 Node**
2. **A 50-Concurrent-User OpenAI-Compatible Gateway for Heterogeneous LLM Serving**
3. **GEM-LLM: Production LLM Serving at Single-Node Scale with vLLM, FastAPI, and Cloudflare Tunnel**

---

## Abstract (~150 words)
> We present **GEM-LLM**, a single-node LLM-serving platform that concurrently hosts Qwen2.5-Coder-32B Dense and 26B-A4B MoE models on an 8×B200 GPU node. Built on vLLM 0.17.1 with per-GPU partitioning (4 GPUs Dense, 4 GPUs MoE), GEM-LLM exposes an OpenAI-compatible FastAPI gateway, enforces 50-concurrent-user admission, and routes requests by model name to the appropriate vLLM instance. We securely publish the Kubernetes pod via Cloudflare Tunnel and ship a Claude-Code-style CLI plus an Admin Web UI for user, API-key, usage, and model lifecycle management. Phase 2 adds Google OAuth alongside API keys. Under a 50-concurrent-user load test, GEM-LLM sustains p95 < 2 s and ≥ 30 RPS while keeping GPU utilization above 80 %. We catalog eight production failure modes with mitigations and discuss the constraints of NCCL/RDMA-disabled cloud Kubernetes. We release configurations to enable reproduction.

**Keywords:** LLM serving, Qwen Coder, vLLM, mixture of experts, multi-tenant inference, OpenAI-compatible API, Cloudflare Tunnel

---

## I. Introduction (~1p)
- A. Self-hosted LLMs and their drivers
- B. Single-node multi-model challenges
- C. Contributions
  1. Single-node co-residency architecture for Dense + MoE
  2. Bounded 50-concurrent-user OpenAI-compatible gateway
  3. Operational guidance for NCCL/RDMA-disabled K8s
  4. Eight real-world failure modes & mitigations
- D. Paper organization
- **Figure:** Fig. 1 — diagram-01 (whole-system view)

## II. Related Work (~1.5p)
- A. vLLM and PagedAttention [1]
- B. Mixture-of-Experts: Switch Transformer [3], Mixtral [2]
- C. OpenAI-compatible API ecosystem [4]
- D. Multi-tenant LLM serving — TGI [8], TensorRT-LLM [7], SGLang [10]
- E. LLM gateways — LiteLLM [11], OpenRouter
- F. Position of this work

## III. System Design (~2p)
- A. Requirements (50 concurrent users, OpenAI compatibility, intranet, dual model)
- B. Six-component decomposition
- C. GPU partitioning policy
- D. Request lifecycle
- E. Authentication model — Phase 1 API key, Phase 2 OAuth additive
- F. Data model (User/APIKey/UsageLog)
- **Figures:** Fig. 2 — diagram-06; Fig. 3 — diagram-17; Fig. 4 — diagram-21

## IV. Implementation (~2p)
- A. vLLM 0.17.1 launch options for both instances
- B. FastAPI gateway — async routing, semaphore=50
- C. SSE streaming and backpressure
- D. CLI — read/write/edit/bash/grep tools
- E. Admin Web UI — React + Vite
- F. Deployment — K8s pod + Cloudflare Tunnel
- **Figures:** Fig. 5 — diagram-09; Fig. 6 — diagram-25

## V. Evaluation (~2p)
- A. Hardware — 8×B200, 2.2 TB RAM, 288 vCPU
- B. Workload — 50 concurrent users, 1 hour, mean 1K input / 512 output tokens
- C. Metrics — TTFT, TPOT, p50/p95/p99 latency, RPS, GPU utilization
- D. Results — per-model breakdown
- E. Sensitivity — KV cache size, `max_num_seqs`
- F. SSE vs non-stream
- **Figures:** Fig. 7 — diagram-37

## VI. Discussion (~1p)
- A. Why single-node still wins (operationally) given K8s constraints
- B. Limits — no NCCL/RDMA → no native multi-node tensor parallelism
- C. Generalization — porting to Llama / Qwen
- D. Threats to validity — single workload trace, single hardware

## VII. Conclusion (~0.5p)
- Summary of contributions
- Future work — multi-node (RDMA), RAG integration, billing module

## Acknowledgments (~0.1p)

## References (~1p)

### BibTeX Candidate Stubs (8–12)
```bibtex
@inproceedings{kwon2023vllm,
  author    = {Kwon, Woosuk and Li, Zhuohan and Zhuang, Siyuan and others},
  title     = {Efficient Memory Management for Large Language Model Serving with PagedAttention},
  booktitle = {SOSP},
  year      = {2023}
}
@misc{jiang2024mixtral,
  author    = {Jiang, Albert Q. and others},
  title     = {Mixtral of Experts},
  howpublished = {arXiv:2401.04088},
  year      = {2024}
}
@article{fedus2022switch,
  author    = {Fedus, William and Zoph, Barret and Shazeer, Noam},
  title     = {Switch Transformers: Scaling to Trillion Parameter Models with Simple and Efficient Sparsity},
  journal   = {JMLR},
  year      = {2022}
}
@misc{openai2024api,
  author    = {{OpenAI}},
  title     = {OpenAI API Reference},
  howpublished = {https://platform.openai.com/docs},
  year      = {2024}
}
@misc{anthropic2025claudecode,
  author    = {{Anthropic}},
  title     = {Claude Code Documentation},
  year      = {2025}
}
@techreport{google2024gemma,
  author    = {{Google DeepMind}},
  title     = {Gemma: Open Models Based on Gemini Research and Technology},
  year      = {2024}
}
@misc{nvidia2024trtllm,
  author    = {{NVIDIA}},
  title     = {TensorRT-LLM},
  howpublished = {GitHub},
  year      = {2024}
}
@misc{hf2024tgi,
  author    = {{Hugging Face}},
  title     = {Text Generation Inference},
  howpublished = {GitHub},
  year      = {2024}
}
@misc{cloudflare2025tunnel,
  author    = {{Cloudflare}},
  title     = {Cloudflare Tunnel Documentation},
  year      = {2025}
}
@inproceedings{zheng2024sglang,
  author    = {Zheng, Lianmin and others},
  title     = {SGLang: Efficient Execution of Structured Language Model Programs},
  booktitle = {NeurIPS},
  year      = {2024}
}
@misc{litellm2024,
  author    = {{LiteLLM Team}},
  title     = {LiteLLM: Call All LLM APIs Using OpenAI Format},
  howpublished = {GitHub},
  year      = {2024}
}
@misc{shazeer2017outrageously,
  author    = {Shazeer, Noam and others},
  title     = {Outrageously Large Neural Networks: The Sparsely-Gated Mixture-of-Experts Layer},
  howpublished = {arXiv:1701.06538},
  year      = {2017}
}
```

---

## Page Budget
| Section | Pages |
|---|---|
| Abstract | 0.3 |
| I. Introduction | 1.0 |
| II. Related Work | 1.5 |
| III. System Design | 2.0 |
| IV. Implementation | 2.0 |
| V. Evaluation | 2.0 |
| VI. Discussion | 1.0 |
| VII. Conclusion | 0.5 |
| References | 1.0 |
| **Total** | **11.3** |

## Diagrams used
diagram-01, 06, 09, 17, 21, 25, 37
