# NeuroVault — 2–3 minute video

Target length: 2:30. Record the actual dashboard and explorer; clearly label browser simulation and mock on-chain activity.

**0:00–0:20 — The problem.**
“We are Darshan and Sebastian. NeuroVault keeps risk rules on-chain so an online keeper does not need your owner key. Existing stops already automate execution. We add an adaptive policy without handing a bot withdrawal authority.”

**0:20–0:45 — The rules.**
Show the owner and parameter hash on the live deployment when available.
“The owner approves the neuron settings and opens a mock long. Setup takes multiple signatures in this prototype. After that, anyone can call poke. Only the owner can withdraw, and only to itself.”

**0:45–1:25 — Browser replay.**
Reset replay, show calm conditions, then use Inject volatility. Explain what actually appears; do not promise that a particular injection produces an 8% band or better returns.
“The blue line is the synthetic price. The red line is our stop. Absolute returns accumulate in three spiking neurons. Recent spikes select a wider target trail. Watch the red stop: it can hold or move up, but cannot move down. The grey line is a fixed 2% trailing baseline. This is a controlled illustration, not evidence of general outperformance.”

**1:25–2:00 — On-chain evidence.**
Switch to the deployed Arc vault, show its explorer contract and a successful poke receipt. Show native network fee in USDC and distinguish mUSDC collateral.
“These contracts run on Arc Testnet, and calls pay gas in test USDC. The mock venue uses a separate mintable collateral token and a deployer-controlled price feed. The event log exposes neuron spikes and stop changes.”

If no Arc deployment exists, finish deployment before recording this segment; do not substitute local addresses without disclosure.

**2:00–2:30 — Boundaries and next steps.**
“A wider trail may avoid some shakeouts, but can exit lower. This is safer delegation, not prediction. We have 30 contract tests, including 256 random paths per direction, plus local parity checks between Solidity, Python and browser math. Shoreline-1 signing and a production GMX venue are unfinished. Next we want audited production integration and, later, market-wide protection for thin assets.”

# Four-minute in-person pitch

Spend 40 seconds on the owner-key problem, 100 seconds on the live/replay demo, 50 seconds on authority and economic limitations, and 50 seconds on Arc integration and the roadmap. Reserve the two-minute Q&A for oracle trust, sampling/caller timing, keeper liveness, signature count, synthetic data and the stop/exit trade-off.

Useful answers:
- **Is it AI?** A small deterministic LIF neuron layer; no training or price prediction is claimed.
- **What if nobody pokes?** Adaptation stops. The mock venue also needs a transaction to execute a stop.
- **Can the keeper steal?** It cannot withdraw or choose a recipient. Call timing affects sampling; the oracle admin remains trusted in the mock.
- **Why Arc?** EVM-compatible on-chain policy with USDC-denominated gas; CCTP is not implemented.
- **One signature?** No: multiple setup signatures today, then no owner signature for ongoing pokes.
- **GMX ready?** No live deployment. The three tests check locally recorded order construction/units, not a complete GMX lifecycle.
