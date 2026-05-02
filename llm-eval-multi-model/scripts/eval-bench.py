#!/usr/bin/env python3
"""eval-bench.py — 다중 LLM endpoint 벤치마크.

Usage:
  python eval-bench.py \
    --endpoints http://h1:8001,http://h2:8002 \
    --keys k1,k2 \
    --models m-a,m-b \
    --prompts prompts.txt --runs 10

Optional:
  --judge-endpoint URL --judge-key K --judge-model M  (LLM-as-judge)
  --temperature 0.0  --max-tokens 512  --warmup 2  --concurrency 5
"""
from __future__ import annotations

import argparse
import asyncio
import json
import statistics
import sys
import time
from datetime import datetime
from pathlib import Path

import httpx


async def call_one(client, endpoint, key, model, prompt, temperature, max_tokens):
    t0 = time.perf_counter()
    try:
        r = await client.post(
            f"{endpoint.rstrip('/')}/v1/chat/completions",
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
            json={
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "temperature": temperature,
                "max_tokens": max_tokens,
            },
            timeout=120,
        )
        dt = time.perf_counter() - t0
        j = r.json()
        usage = j.get("usage", {})
        return {
            "ok": True,
            "endpoint": endpoint,
            "model": model,
            "latency_s": dt,
            "prompt_tokens": usage.get("prompt_tokens", 0),
            "completion_tokens": usage.get("completion_tokens", 0),
            "response": j["choices"][0]["message"].get("content", ""),
        }
    except Exception as e:
        return {"ok": False, "endpoint": endpoint, "model": model,
                "latency_s": time.perf_counter() - t0, "error": str(e)}


def percentile(values, q):
    if not values:
        return 0.0
    s = sorted(values)
    idx = min(int(len(s) * q), len(s) - 1)
    return s[idx]


def summarize(rows):
    ok = [r for r in rows if r.get("ok")]
    lats = [r["latency_s"] for r in ok]
    out_tok = [r["completion_tokens"] for r in ok]
    if not lats:
        return {"n_ok": 0, "n_err": len(rows) - len(ok)}
    tps = [(t / s) for t, s in zip(out_tok, lats) if s > 0]
    return {
        "n_ok": len(ok),
        "n_err": len(rows) - len(ok),
        "lat_p50": statistics.median(lats),
        "lat_p95": percentile(lats, 0.95),
        "lat_p99": percentile(lats, 0.99),
        "lat_mean": statistics.mean(lats),
        "lat_stdev": statistics.stdev(lats) if len(lats) > 1 else 0,
        "tps_mean": statistics.mean(tps) if tps else 0,
        "out_tok_mean": statistics.mean(out_tok) if out_tok else 0,
    }


async def judge_pair(client, endpoint, key, model, prompt, resp_a, resp_b, model_a, model_b):
    judge_prompt = (
        f"Question: {prompt}\n\n"
        f"Response A (model={model_a}): {resp_a}\n\n"
        f"Response B (model={model_b}): {resp_b}\n\n"
        "Score correctness, clarity, language-fit each 0-10. "
        'Output JSON only: {"a":{"correctness":n,"clarity":n,"lang":n},'
        '"b":{"correctness":n,"clarity":n,"lang":n},"winner":"a"|"b"|"tie"}'
    )
    r = await call_one(client, endpoint, key, model, judge_prompt, 0.0, 400)
    if not r.get("ok"):
        return None
    try:
        text = r["response"].strip()
        if text.startswith("```"):
            text = text.split("```")[1].lstrip("json\n")
        return json.loads(text)
    except Exception:
        return {"raw": r["response"]}


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoints", required=True)
    ap.add_argument("--keys", required=True)
    ap.add_argument("--models", required=True)
    ap.add_argument("--prompts", required=True)
    ap.add_argument("--runs", type=int, default=10)
    ap.add_argument("--warmup", type=int, default=2)
    ap.add_argument("--temperature", type=float, default=0.0)
    ap.add_argument("--max-tokens", type=int, default=512)
    ap.add_argument("--concurrency", type=int, default=5)
    ap.add_argument("--judge-endpoint", default=None)
    ap.add_argument("--judge-key", default=None)
    ap.add_argument("--judge-model", default=None)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    endpoints = args.endpoints.split(",")
    keys = args.keys.split(",")
    models = args.models.split(",")
    if not (len(endpoints) == len(keys) == len(models)):
        sys.exit("ERROR: --endpoints, --keys, --models must have same length")

    configs = [{"endpoint": e, "key": k, "model": m}
               for e, k, m in zip(endpoints, keys, models)]
    prompts = [p.strip() for p in Path(args.prompts).read_text().splitlines() if p.strip()]
    print(f"endpoints={len(configs)}, prompts={len(prompts)}, runs={args.runs} (warmup={args.warmup})")

    results = {m: [] for m in models}
    samples = {m: {} for m in models}  # prompt → first sample
    sem = asyncio.Semaphore(args.concurrency)

    async with httpx.AsyncClient() as client:
        async def bounded(c, p):
            async with sem:
                return await call_one(client, c["endpoint"], c["key"], c["model"], p,
                                      args.temperature, args.max_tokens)

        for run in range(args.runs):
            tag = "WARMUP" if run < args.warmup else f"run {run + 1 - args.warmup}/{args.runs - args.warmup}"
            for p in prompts:
                tasks = [bounded(c, p) for c in configs]
                rows = await asyncio.gather(*tasks)
                for r in rows:
                    if run >= args.warmup:
                        results[r["model"]].append(r)
                        samples[r["model"]].setdefault(p, r.get("response", r.get("error", "")))
            print(f"  {tag} done")

    # Optional LLM-as-judge (compare first two models pairwise)
    judges = []
    if args.judge_endpoint and len(models) >= 2:
        async with httpx.AsyncClient() as client:
            for p in prompts:
                a = samples[models[0]].get(p, "")
                b = samples[models[1]].get(p, "")
                j = await judge_pair(client, args.judge_endpoint, args.judge_key,
                                     args.judge_model, p, a, b, models[0], models[1])
                judges.append({"prompt": p, "verdict": j})

    # Build markdown
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    out_path = args.out or f"eval-results-{ts}.md"
    lines = [f"# Eval Results — {ts}\n",
             f"prompts={len(prompts)}, runs={args.runs - args.warmup}, "
             f"warmup={args.warmup}, temperature={args.temperature}\n",
             "## Metrics\n",
             "| model | n_ok | lat_p50 | lat_p95 | lat_p99 | lat_mean | tps | out_tok |",
             "|---|---|---|---|---|---|---|---|"]
    for m in models:
        s = summarize(results[m])
        if s.get("n_ok"):
            lines.append(f"| `{m}` | {s['n_ok']} | {s['lat_p50']:.3f} | "
                         f"{s['lat_p95']:.3f} | {s['lat_p99']:.3f} | "
                         f"{s['lat_mean']:.3f} | {s['tps_mean']:.1f} | "
                         f"{s['out_tok_mean']:.0f} |")
        else:
            lines.append(f"| `{m}` | 0 (all err: {s.get('n_err', 0)}) | - | - | - | - | - | - |")

    lines.append("\n## Response Samples\n")
    for i, p in enumerate(prompts[:10], 1):
        lines.append(f"### Prompt {i}\n```\n{p[:300]}\n```\n")
        for m in models:
            txt = samples[m].get(p, "")[:800].replace("\n", " ")
            lines.append(f"**{m}:** {txt}\n")
        if judges and i <= len(judges):
            v = judges[i - 1]["verdict"]
            lines.append(f"**judge:** `{json.dumps(v, ensure_ascii=False)[:400]}`\n")

    Path(out_path).write_text("\n".join(lines), encoding="utf-8")
    print(f"\n→ {out_path}")


if __name__ == "__main__":
    asyncio.run(main())
