"""Bit-exact simulator of NeuroVault's on-chain LIF layer + ratchet.

Mirrors the Solidity integer math (WAD fixed point, floor division) so parameters
tuned here behave identically on-chain. Use it to:
  * tune tau / weight / theta / trailBps before the cold wallet signs them
  * render the spike raster + stop line for the demo
  * export params.json for the deploy script

Usage:
  python3 sim/snn_sim.py                      # synthetic regime-switching price path
  python3 sim/snn_sim.py --csv prices.csv     # columns: timestamp,price (USD)
"""

import argparse
import json
import math
import random

WAD = 10**18
BPS = 10_000

DEFAULT_PARAMS = {
    "tau": [600, 600, 600],
    "weight": [WAD, WAD, WAD],
    "theta": [10**16, 2 * 10**16, 4 * 10**16],  # 1%, 2%, 4% integrated |return|
    "trailBps": [200, 350, 500, 800],
    "memoryWindow": 1800,
    "minMoveBps": 10,
    "minPokeInterval": 60,
    "maxOracleAge": 3600,
}


class NeuroVaultSim:
    def __init__(self, p, entry_price_wad, t0, is_long=True):
        self.p = p
        n = len(p["tau"])
        self.v = [0] * n
        self.last_spike = [0] * n
        self.regime = 0
        self.last_price = entry_price_wad
        self.last_t = t0
        self.is_long = is_long
        trail = p["trailBps"][0]
        self.extreme = entry_price_wad
        self.stop = (entry_price_wad * (BPS - trail)) // BPS if is_long else (entry_price_wad * (BPS + trail)) // BPS
        self.active = True
        self.venue_updates = 0

    def step(self, price, t):
        """One poke(). Returns list of neuron indices that spiked."""
        p = self.p
        dt = t - self.last_t
        lp = self.last_price
        x = ((price - lp) * WAD) // lp if price > lp else ((lp - price) * WAD) // lp
        spikes, new_regime = [], 0
        for i, tau in enumerate(p["tau"]):
            v = (self.v[i] * tau) // (tau + dt)
            v += (p["weight"][i] * x) // WAD
            if v >= p["theta"][i]:
                v = 0
                self.last_spike[i] = t
                spikes.append(i)
            self.v[i] = v
            if self.last_spike[i] != 0 and t - self.last_spike[i] <= p["memoryWindow"]:
                new_regime = i + 1
        self.regime = new_regime
        self.last_price, self.last_t = price, t
        if self.active:
            self._ratchet(price)
        return spikes

    def _ratchet(self, price):
        p = self.p
        if (price <= self.stop) if self.is_long else (price >= self.stop):
            self.active = False
            return
        trail = p["trailBps"][self.regime]
        if self.is_long:
            self.extreme = max(self.extreme, price)
            cand = (self.extreme * (BPS - trail)) // BPS
            if cand <= self.stop or (cand - self.stop) * BPS < p["minMoveBps"] * self.stop:
                return
        else:
            self.extreme = min(self.extreme, price)
            cand = (self.extreme * (BPS + trail)) // BPS
            if cand >= self.stop or (self.stop - cand) * BPS < p["minMoveBps"] * self.stop:
                return
        self.stop = cand
        self.venue_updates += 1
        if (price <= self.stop) if self.is_long else (price >= self.stop):
            self.active = False


def synthetic_path(n=720, dt=60, p0=2000.0, seed=6):
    """Calm -> volatile burst -> calm, per-minute samples (~12h)."""
    rng = random.Random(seed)
    t, price, out = 1_700_000_000, p0, []
    for k in range(n):
        sigma = 0.0035 if (n // 3) <= k < (n // 3 + 90) else 0.0003
        drift = 0.00008 if not ((n // 3) <= k < (n // 3 + 90)) else 0.0
        price *= math.exp(drift + sigma * rng.gauss(0, 1))
        t += dt
        out.append((t, price))
    return out


def load_csv(path):
    rows = []
    with open(path) as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) < 2 or not parts[0].replace(".", "").isdigit():
                continue
            rows.append((int(float(parts[0])), float(parts[1])))
    return rows


def run(path, params):
    to_wad = lambda usd: int(round(usd * 1e8)) * 10**10  # oracle is 8 decimals
    t0, p0 = path[0]
    sim = NeuroVaultSim(params, to_wad(p0), t0)
    trace = []
    for t, usd in path[1:]:
        spikes = sim.step(to_wad(usd), t)
        trace.append({
            "t": t, "price": usd, "stop": sim.stop / WAD, "regime": sim.regime,
            "trailBps": params["trailBps"][sim.regime], "spikes": spikes,
            "potentials": [v / WAD for v in sim.v], "active": sim.active,
        })
        if not sim.active:
            break
    return sim, trace


def plot(trace, params, out_png):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    ts = [(r["t"] - trace[0]["t"]) / 3600 for r in trace]
    fig, ax = plt.subplots(3, 1, figsize=(11, 7), sharex=True, gridspec_kw={"height_ratios": [3, 1.4, 1]})
    ax[0].plot(ts, [r["price"] for r in trace], color="#2a6fdb", lw=1.2, label="oracle price")
    ax[0].step(ts, [r["stop"] for r in trace], where="post", color="#d64545", lw=1.4, label="ratcheted stop")
    ax[0].set_ylabel("USD")
    ax[0].legend(loc="upper left", frameon=False)
    ax[0].set_title("NeuroVault: on-chain LIF neurons ratcheting a trailing stop")
    for i, th in enumerate(params["theta"]):
        ax[1].plot(ts, [r["potentials"][i] * 100 for r in trace], lw=1, label=f"neuron {i} (θ={th / WAD:.0%})")
    ax[1].set_ylabel("membrane %")
    ax[1].legend(loc="upper left", frameon=False, fontsize=8)
    for i in range(len(params["theta"])):
        xs = [ts[k] for k, r in enumerate(trace) if i in r["spikes"]]
        ax[2].scatter(xs, [i] * len(xs), marker="|", s=120, color="black")
    ax[2].set_yticks(range(len(params["theta"])))
    ax[2].set_ylabel("spikes")
    ax[2].set_xlabel("hours")
    fig.tight_layout()
    fig.savefig(out_png, dpi=130)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv")
    ap.add_argument("--params")
    ap.add_argument("--out", default="sim/out")
    a = ap.parse_args()

    params = json.load(open(a.params)) if a.params else DEFAULT_PARAMS
    path = load_csv(a.csv) if a.csv else synthetic_path()
    sim, trace = run(path, params)

    import os
    os.makedirs(a.out, exist_ok=True)
    json.dump(params, open(f"{a.out}/params.json", "w"), indent=2)
    json.dump(trace, open(f"{a.out}/trace.json", "w"))
    plot(trace, params, f"{a.out}/raster.png")

    # Honest baseline: a fixed trail at the calm width, same ratchet + anti-spam rules.
    fixed = dict(params, theta=[10**30] * len(params["theta"]),
                 trailBps=[params["trailBps"][0]] * len(params["trailBps"]))
    base, base_trace = run(path, fixed)

    n_spikes = sum(len(r["spikes"]) for r in trace)
    print(f"SNN   : samples={len(trace)} spikes={n_spikes} venue_updates={sim.venue_updates} "
          f"stop={sim.stop / WAD:.2f} still_open={sim.active}")
    print(f"FIXED : samples={len(base_trace)} venue_updates={base.venue_updates} "
          f"stop={base.stop / WAD:.2f} still_open={base.active}")


if __name__ == "__main__":
    main()
