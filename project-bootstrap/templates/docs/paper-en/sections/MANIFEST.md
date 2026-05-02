# GEM-LLM English IEEE Conference Paper -- MANIFEST

> Build manifest for `docs/paper-en/sections/`. Pandoc concatenates the
> source files in the order listed below.

## Adopted Title

**GEM-LLM: A Multi-Tenant OpenAI-Compatible Coding Assistant on a Single 8×B200 Node Co-Hosting Dense and MoE Models**

(Synthesized from OUTLINE candidates 1 and 2.)

## Build Order

| # | File | Section | Approx. typeset pages |
|---|------|---------|-----------------------|
| 1 | `00-abstract.md` | Abstract + index terms | 0.3 |
| 2 | `01-introduction.md` | I. Introduction | 1.0 |
| 3 | `02-related-work.md` | II. Related Work | 1.5 |
| 4 | `03-system-design.md` | III. System Design | 2.0 |
| 5 | `04-implementation.md` | IV. Implementation | 2.0 |
| 6 | `05-evaluation.md` | V. Evaluation | 2.0 |
| 7 | `06-discussion.md` | VI. Discussion | 1.0 |
| 8 | `07-conclusion.md` | VII. Conclusion + Acknowledgments | 0.5 |
| -- | `references.bib` | References | 1.0 |
| **Total** | | | **~11.3** |

Within the IEEE conference 8--12 page target.

## Diagrams Used

| Figure | Diagram ID | Section |
|--------|-----------|---------|
| Fig. 1 | `diagram-01` (whole-system view) | Section I-E |
| Fig. 2 | `diagram-06` (component relationship) | Section III-B |
| Fig. 3 | `diagram-17` (GPU partition) | Section III-C |
| Fig. 4 | `diagram-21` (ER diagram) | Section III-I |
| Fig. 5 | `diagram-09` (gateway internals) | Section IV-B |
| Fig. 6 | `diagram-25` (deployment topology) | Section IV-F |
| Fig. 7 | `diagram-37` (performance chart, pending) | Section V-D |

> Diagram catalog: `/home/jovyan/gem-llm/docs/diagrams/CATALOG.md`

## Citations

`references.bib` contains 14 entries.

| Cite key | Type | Status |
|----------|------|--------|
| `Kwon23` | inproceedings (SOSP) | verified |
| `Jiang24` | misc (arXiv) | verified |
| `Llama3` | misc (arXiv) | verified |
| `GPT4` | misc (arXiv) | verified |
| `Shazeer17` | inproceedings (ICLR) | verified |
| `Zheng24` | inproceedings (NeurIPS) | verified |
| `OpenAI24` | misc (URL) | placeholder |
| `Anthropic25` | misc (URL) | placeholder |
| `LiteLLM24` | misc (URL) | placeholder |
| `FastAPI` | misc (URL) | placeholder |
| `HF-TGI24` | misc (URL) | placeholder |
| `NVIDIA24` | misc (URL) | placeholder |
| `Pandoc` | misc (URL) | placeholder |
| `Cloudflare25` | misc (URL) | placeholder |

Verified: 6. Placeholder (TODO): 8.

## `[measurement pending]` Placeholder Locations

| Section | Location |
|---------|----------|
| V-D | All cells of Table VI |
| V-D | Fig. 7 (performance chart, deferred) |
| V-E | All cells of Table VII |
| V-F | SSE vs non-streaming numerical comparison |
| V-H | Explicit acknowledgment of pending measurements |
| VII-B | Limitation reference back to V-H |

These markers will be replaced with measured values in the camera-ready
submission, or the affected paragraphs will be revised to describe the
methodology only.

## Build Notes

- Input: 8 markdown sections (`00-abstract` through `07-conclusion`).
- Bibliography: `references.bib` (shared cite-key namespace with the
  Korean companion paper; safe to symlink).
- Recommended Pandoc command:

```
pandoc \
  --from markdown --to latex \
  --citeproc --bibliography references.bib \
  --csl ieee.csl \
  --template ieeetran-conference \
  -o gem-llm-paper-en.pdf \
  00-abstract.md 01-introduction.md 02-related-work.md \
  03-system-design.md 04-implementation.md 05-evaluation.md \
  06-discussion.md 07-conclusion.md
```

- Layout: IEEEtran double-column, 10 pt body, US-letter.
- Fonts: Times Roman or IEEEtran-bundled equivalent.

## Pre-Submission Checklist

- [ ] Replace every `[measurement pending]` placeholder with measured
      values (Sections V-D through V-F).
- [ ] Re-verify each placeholder BibTeX entry; remove `% TODO: verify`.
- [ ] Confirm IEEEtran template renders all seven figures within the
      double-column boundary.
- [ ] Ensure 8--12 page total after typesetting (currently estimated
      11.3 pages).
- [ ] Check that all `Fig. N` and `Table N` references resolve.
- [ ] Spell-check; passive-voice review; double-blind anonymization.
