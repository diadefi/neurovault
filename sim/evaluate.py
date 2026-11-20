"""Reproducible 50-seed evaluation of the existing snn_sim model; no chain calls."""
import csv
import json
from pathlib import Path
from statistics import mean

from snn_sim import DEFAULT_PARAMS, run, synthetic_path


def main():
    out = Path(__file__).resolve().parent / "out"
    out.mkdir(exist_ok=True)
    params = dict(DEFAULT_PARAMS)
    fixed = dict(params, theta=[10**30] * len(params["theta"]), trailBps=[200] * 4)
    rows = []
    for seed in range(50):
        path = synthetic_path(n=720, dt=60, p0=2000.0, seed=seed)
        burst_end = path[329][0]  # generator: indices 240 through 329, inclusive
        for strategy, settings in [("SNN", params), ("Fixed 2%", fixed)]:
            sim, trace = run(path, settings)
            stopped = not sim.active
            exit_at = trace[-1]["t"] if stopped else None
            rows.append({
                "seed": seed, "strategy": strategy,
                "survived_burst": exit_at is None or exit_at > burst_end,
                "stopped": stopped, "exit_timestamp": exit_at,
                "exit_price_usd": trace[-1]["price"] if stopped else None,
                "stop_updates": sim.venue_updates,
                "entry_price_usd": path[0][1],
            })
    summary = {}
    for strategy in ("SNN", "Fixed 2%"):
        selected = [r for r in rows if r["strategy"] == strategy]
        exits = [r["exit_price_usd"] for r in selected if r["stopped"]]
        summary[strategy] = {
            "seeds": len(selected),
            "survived_burst": sum(r["survived_burst"] for r in selected),
            "stopped_by_end": len(exits),
            "mean_exit_when_stopped_usd": mean(exits) if exits else None,
            "mean_stop_updates": mean(r["stop_updates"] for r in selected),
            "total_stop_updates": sum(r["stop_updates"] for r in selected),
        }
    pairs = [(rows[i], rows[i+1]) for i in range(0, len(rows), 2)
             if rows[i]["stopped"] and rows[i+1]["stopped"]]
    paired = {
        "both_stopped_seeds": len(pairs),
        "snn_exit_lower_count": sum(a["exit_price_usd"] < b["exit_price_usd"] for a, b in pairs),
        "mean_snn_minus_fixed_exit_usd": mean(a["exit_price_usd"] - b["exit_price_usd"] for a, b in pairs) if pairs else None,
    }
    result = {
        "method": "snn_sim.synthetic_path/run; seeds 0..49; 720 one-minute samples; long; burst indices 240..329; default params; same minMoveBps=10; no fees/slippage",
        "params": params, "summary": summary, "paired_stopped": paired, "rows": rows,
    }
    (out / "evaluation.json").write_text(json.dumps(result, indent=2) + "\n")
    with (out / "evaluation.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps({"summary": summary, "paired_stopped": paired}, indent=2))


if __name__ == "__main__":
    main()
