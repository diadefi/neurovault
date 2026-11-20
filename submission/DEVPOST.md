# NeuroVault — Devpost draft

Team/member names supplied: **Darshan and Sebastian**. Select **DeFi and Onchain Applications**, **Best use of Arc**, and **no bounties**. Both members must attend the in-person closing ceremony to qualify under the supplied brief.

## Short description

On-chain spiking neurons adapt a perpetual position's stop without giving a keeper the owner's key. A testnet risk-automation prototype on Arc, with USDC-paid gas and owner-only withdrawals.

## What did you build?

NeuroVault combines a Solidity vault, a three-neuron leaky integrate-and-fire layer, a mock perpetual venue, a Python simulator, a permissionless keeper, a wallet-signing workflow, and a dashboard with browser replay and live on-chain views. Our target deployment is the mock suite on Arc Testnet. Replace this status sentence with confirmed deployment evidence before submission.

## What problem does it solve?

Keeping a trading key offline makes repeated discretionary adjustments inconvenient. Delegating broad authority to an online bot introduces another key that can be compromised. NeuroVault constrains automation in contract code: a caller can advance the owner's chosen policy, but cannot redirect proceeds or loosen an established stop.

## How does it work?

After owner-approved setup, anyone calls `poke()`. The contract reads the oracle and integrates absolute returns into three small spiking neurons. Recent spikes choose target trailing distances from 2% to 8%. A monotone ratchet prevents a wider regime from lowering an existing long stop (or raising an existing short stop). The mock venue settles crossed stops back to the vault, and only the owner may withdraw to itself. Call timing affects sampling, so the system is deterministic for an observed call/price sequence, not independent of callers' timing.

## What makes it unique?

The compact neuron layer, state transitions, and stop ratchet execute on-chain and are inspectable through events. Automation is permissionless while withdrawal authority stays with the owner. Arc provides the EVM execution environment and native USDC transaction fees. We demonstrate the difference between a variable target trail and a stop that never loosens.

## What would you build next?

Audit and harden the contracts; integrate a production oracle and reliable keeper incentives; validate on historical data; complete real hardware signing; reconcile the experimental GMX adapter's asynchronous lifecycle. Later, explore market-wide risk limits for thin assets such as copper and palladium. Those markets and controls are roadmap work, not the hackathon build.

## Technologies

Solidity 0.8.24, Foundry, OpenZeppelin 5.1.0, Arc Testnet, MetaMask, ethers.js, Node.js, Python, matplotlib, HTML/SVG/JavaScript. Circle faucet supplies test USDC for network gas. The trading collateral is a separate mintable mock token. No CCTP, Gemini, QuickNode Streams, ElevenLabs, Grok, or Solana integration is claimed.

## Honest limitations

Multiple setup signatures; no literal one-signature setup. Mock oracle controlled by the deployer; no real perp liquidity or liquidation engine. Shoreline-1 remains a transport stub. GMX has local order-construction tests only. No audit, price prediction, formal proof, or demonstrated general performance advantage. Keepers may use gas-paying online keys, but no owner key is needed for `poke()`.

## Required links to finish

- Public GitHub repository: https://github.com/diadefi/neurovault
- Working dashboard: https://diadefi.github.io/neurovault/
- Four Arc contract addresses: from verified deployment manifest.
- Accessible 2–3 minute YouTube/Google Drive video: still to record and upload.
- Submission deadline in supplied brief: November 20, 2026, noon CST.

Do not submit pending addresses, local Anvil addresses as Arc evidence, or a claim that the video exists before it is uploaded.
