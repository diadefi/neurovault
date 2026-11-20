# NeuroVault — overnight handoff

## Deadline update — November 20, 11:29 AM CST

- Restyled only the CSS blocks in `frontend/index.html` and `frontend/operate.html`: off-white/charcoal palette with one muted rust accent, system text, monospace values, flat borders, no glow or purple/neon accents. Non-CSS content, element IDs and scripts are byte-equivalent after newline normalization to branch baseline `b737a8e`. Both pages reloaded and were screenshotted with zero console/network errors. CSS work finished in under two minutes.
- New video: [`demo/neurovault-submission-720p.mp4`](demo/neurovault-submission-720p.mp4), exactly **150 seconds**, **1280×720**, H.264, preset `veryfast`, **1,911,062 bytes**, silent with FFmpeg-burned captions. Five scenes follow the requested 20/20/80/20/10-second schedule. Replay at speed 5 captured calm prices, the step-200 burst, spikes and regime changes; sampled stop values never decreased. The actual 30-test count and multiple-setup-signature limitation are stated.
- Recorded with Playwright `record_video`; all non-GET requests blocked, no wallet connection or transactions. Full MP4 decode passed; final frames from each scene visually inspected. Recording and encoding finished in under four minutes after the CSS check.
- Tooling/evidence: `tools/record-submission.py`, `evidence/restyle-check.json`, `evidence/submission-video.json`, and `evidence/submission-video/`. The earlier backup remains unchanged.
- `SendUserFile` is unavailable in this session; the local MP4 was provided as a direct file link. Public download after Pages publishes: https://diadefi.github.io/neurovault/demo/neurovault-submission-720p.mp4. Upload this file to the required YouTube/Drive destination and check judge access before noon.

Prepared Friday, November 20, 2026 (America/Chicago). **No transactions sent during this work. No files in `src/` changed.** No new vault or trading features were added.

## Finished

- README: four deployed Arc addresses with explorer links; GMX marked local ABI-interface integration tests, not deployed; explicit mock/oracle, timing, signer and unaudited-code disclosures.
- Published runner: recovered the existing `operate.html`, pointed its default RPC/explorer to the verified Arc endpoints, and generated `contracts.js` from the same current artifacts as `setup.html`. The existing `abi.js` and vendored ethers are published alongside it.
- CI: moved the existing full check workflow to `.github/workflows/test.yml`, retaining `forge test` on push, pull request and manual dispatch, plus the Node signing/error checks. README links its real status badge.
- Evaluation: ran the existing Python model for seeds **0–49**. SNN burst survival **27/50**, fixed 2% **10/50**; mean exits among stopped positions **$2,011.73 vs $2,034.26**; mean stop updates **28.4 vs 28.6**. Raw CSV/JSON and method are committed. These are synthetic descriptive results, not a market backtest.
- Six-slide deck in `docs/pitch.html`: problem, mechanism, live-demo links and results, safety, agent-wallet comparison, roadmap. Arrow keys navigate; **N** toggles notes. Notes allocate exactly five minutes, including one minute for the demo. All six slides were visually reviewed at 1600×900 with no overflow.
- Local checks passed: **30 Foundry tests** (including 256 long + 256 short fuzz runs), **4 Node tests**, syntax/whitespace checks, and headless page-load checks on dashboard, alternate runner, current control room and pitch. No console errors or failed requests in the local checks.
- Read-only Arc check at **2026-11-20 09:21:31 UTC / 03:21:31 CST**: intended owner matches; vault active with entry $2,000 and stop $1,960; τ 600 seconds, memory 1,800 seconds, cooldown 60 seconds. This is a timestamped snapshot, not a promise about later state.

- Backup recording completed: `demo/backup-replay.mp4`, **150.0 seconds**, H.264, preset `veryfast`, 1600×1000, 3,052,717 bytes. Recorded the public replay at speed 10, including step 200; the model closed at step 318, and captions continue over that actual outcome. FFmpeg decoded every frame without errors; sampled frames were visually inspected. No console errors or non-GET requests were allowed by the recorder.

- **Publication complete.** [Pages run 44710277179](https://github.com/diadefi/neurovault/actions/runs/44710277179) succeeded for content commit `b4efb6d`. Headless Chromium opened the public HTTPS dashboard, `operate.html`, `setup.html` and pitch at **09:24:28 UTC / 03:24:28 CST**: all HTTP 200, **zero console errors**, zero failed requests. `contracts.js`, `abi.js` and vendored ethers also returned 200. These are page-load checks, not wallet/transaction tests.
- **CI passed.** [Test run 44710258119](https://github.com/diadefi/neurovault/actions/runs/44710258119) succeeded under the requested `test.yml`. The README badge was independently fetched and reports **passing**.
- The public MP4 returns HTTP 200 as `video/mp4`, with the expected 3,052,717 bytes. The Solidity tree still matches the starting hash exactly. **All seven requested deliverables are complete; none was blocked.**

## Exact links

| Item | Link |
|---|---|
| Repository / README | https://github.com/diadefi/neurovault |
| Replay dashboard | https://diadefi.github.io/neurovault/index.html |
| Live Arc dashboard | https://diadefi.github.io/neurovault/index.html?mode=live |
| Existing-vault MetaMask control room | https://diadefi.github.io/neurovault/setup.html |
| Alternate compressed demo runner | https://diadefi.github.io/neurovault/operate.html |
| Current deployment artifacts | https://diadefi.github.io/neurovault/contracts.js |
| Dashboard ABI | https://diadefi.github.io/neurovault/abi.js |
| Vendored ethers | https://diadefi.github.io/neurovault/vendor/ethers.umd.min.js |
| Six-slide finalist deck | https://diadefi.github.io/neurovault/docs/pitch.html |
| Backup MP4 | https://diadefi.github.io/neurovault/demo/backup-replay.mp4 |
| CI | https://github.com/diadefi/neurovault/actions/workflows/test.yml |
| Raw evaluation | https://github.com/diadefi/neurovault/blob/codex/arc-hackathon/sim/out/evaluation.csv |
| Arc vault | https://explorer.testnet.arc.io/address/0xe581BF3B5aE2A3B34d7eC08C3af5F914581368a2 |
| Mock oracle | https://explorer.testnet.arc.io/address/0x389135ad0Dcf828a5025335ed1861926fE8E035a |
| Mock venue | https://explorer.testnet.arc.io/address/0x3EbF0b03a581927B3eB87e3E138f7048FefbD57f |
| Mock collateral | https://explorer.testnet.arc.io/address/0x006445db90cbA7a84b03595cC59D27e2AEF025Db |

## Important distinctions / skipped scope

- **Keep using `setup.html` for the deployed vault.** `operate.html` is the older alternate runner for a separate deployment; it does not import the existing setup storage. Do not deploy again merely to use it. It creates a local keeper key on load; user clicks are required before any transaction. That keeper can set mock-oracle prices, but is not the owner.
- **×12 timing applies only to the alternate runner.** It uses τ 50 s and memory 150 s, with ~5 s target pacing and a 4 s cooldown. Receipt latency adds time. The existing Arc vault retains 600 / 1,800 / 60 seconds. No owner settings were changed.
- **GMX wording is deliberately qualified.** The three tests use the repo’s GMX ABI interface and a local recording router. No live GMX integration, deployed-ABI compatibility verification or fork test was performed. Claiming those would overstate the evidence.
- The deck reports **30 tests**, replacing the outdated requested count of 21; no tests or Solidity were added in this work.
- No owner signatures, on-chain demonstrations, wallet changes, real-fund operations, hardware work, or live GMX deployment were attempted. Source verification on the explorer was not added.
- The backup is silent with explanatory captions. It is browser replay, not live transaction evidence. Devpost submission, voice narration and a live Arc recording remain yours; they were not sent or uploaded to a video platform.

## When you wake up

1. Open the live dashboard and current `setup.html`. Retain/download the deployment manifest from the browser you used; do not click Deploy again for this existing vault.
2. For a live recording, show the current vault address and state. From the owner account, set a demo price, approve that transaction, then approve **Poke vault**, respecting the 60-second cooldown. These actions are intentionally left to you. If the position has already closed, inspect state before attempting a new open.
3. Use `demo/backup-replay.mp4` if live recording is unreliable. Add narration if desired; label the clip as browser simulation. The video alone does not prove on-chain deployment—include the explorer link as evidence.
4. Review `submission/DEVPOST.md`, paste the project/repo/demo links, and upload/link your video. Select **DeFi and Onchain Applications** and **Best use of Arc**; no bounties. Per your supplied schedule, aim for 10 AM and submit before **Friday noon CST**. No Devpost submission has been made for you.
5. Rehearse the six-slide deck with Darshan and Sebastian for Saturday. Notes cover five minutes; use only about 30 seconds of the fallback during the demo segment. Follow the event attendance/closing-ceremony requirements you supplied.

## Verification files

- `evidence/browser-local.json`: read-only local headless checks.
- `evidence/browser-https.json`: final public HTTPS checks, including console/network results for each page and asset.
- `evidence/public-media-check.json`: public MP4 headers and passing CI badge.
- `evidence/backup-replay.json`: recording parameters, snapshots and H.264 validation.
- `evidence/overnight-verification.json`: unchanged Solidity tree, test counts and video SHA-256.
- `evidence/arc-readonly-snapshot.json`: timestamped Arc reads, no transactions.
- `evidence/pitch-slide-1.png` through `pitch-slide-6.png`: rendered slides.
- `sim/out/evaluation.json` and `.csv`: all 100 strategy/path observations.
- Solidity source tree at the start: `45dff5d41ca8751d9c4031d3744e1eefb0a03e91` (commit `bef2a3b`).
