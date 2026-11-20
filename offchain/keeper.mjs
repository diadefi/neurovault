#!/usr/bin/env node
// NeuroVault keeper. Calls the permissionless poke() whenever the cooldown allows.
// The keeper key needs gas money only: it has no power over the vault.
//
//   RPC=... VAULT=0x... KEEPER_KEY=0x... node offchain/keeper.mjs
//
// Demo mode (MockOracle deployments only): replay a synthetic price path with a
// volatility burst, setting the mock oracle before each poke.
//
//   ... ORACLE=0x... ORACLE_ADMIN_KEY=0x... node offchain/keeper.mjs --replay [--fast]
//
// --fast is for a local anvil node: it fast-forwards chain time instead of waiting.
import { ethers } from "ethers";
import { abi, syntheticPath, to8, requireEnv } from "./lib.mjs";

const args = new Set(process.argv.slice(2));
const replay = args.has("--replay");
const fast = args.has("--fast");
const steps = Number(process.env.STEPS ?? 720);

const provider = new ethers.JsonRpcProvider(requireEnv("RPC"));
const keeperWallet = new ethers.Wallet(requireEnv("KEEPER_KEY"), provider);
const keeper = new ethers.NonceManager(keeperWallet);
const vault = new ethers.Contract(requireEnv("VAULT"), abi("GmxNeuroVault"), keeper);

let oracle;
if (replay) {
  const admin = new ethers.NonceManager(new ethers.Wallet(requireEnv("ORACLE_ADMIN_KEY"), provider));
  oracle = new ethers.Contract(requireEnv("ORACLE"), abi("MockOracle"), admin);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const fmt = (wad) => Number(ethers.formatUnits(wad, 18)).toFixed(2);

async function advance(seconds) {
  await provider.send("evm_increaseTime", [seconds]);
  await provider.send("evm_mine", []);
}

function describe(receipt) {
  const out = [];
  for (const log of receipt.logs) {
    let ev;
    try {
      ev = vault.interface.parseLog(log);
    } catch {
      continue;
    }
    if (!ev) continue;
    if (ev.name === "Spike") out.push(`SPIKE neuron ${ev.args.neuron}`);
    if (ev.name === "RegimeChanged") out.push(`regime ${ev.args.oldRegime}->${ev.args.newRegime} (trail ${ev.args.trailBps} bps)`);
    if (ev.name === "StopTightened") out.push(`stop ${fmt(ev.args.oldStop)} -> ${fmt(ev.args.newStop)}`);
    if (ev.name === "PositionClosed") out.push(`POSITION CLOSED at ${fmt(ev.args.price)} (byStop=${ev.args.byStop})`);
  }
  return out.join(" | ");
}

async function pokeOnce(tag) {
  try {
    // Explicit limit: poke cost depends on block.timestamp (leak, regime, stop update),
    // so an estimate taken one block earlier can come in short.
    const tx = await vault.poke({ gasLimit: 800_000 });
    const r = await tx.wait();
    const price = await vault.lastPrice();
    console.log(`${new Date().toISOString()} ${tag} poke ok  price=${fmt(price)}  gas=${r.gasUsed}  ${describe(r)}`);
  } catch (e) {
    const data = e.data ?? e.info?.error?.data;
    let reason = e.revert?.name;
    if (!reason && data) { try { reason = vault.interface.parseError(data)?.name; } catch {} }
    reason = reason ?? e.shortMessage ?? e.message;
    console.log(`${new Date().toISOString()} ${tag} poke skipped: ${reason}`);
    keeper.reset();
  }
}

async function main() {
  const chain = (await provider.getNetwork()).chainId;
  if (fast && chain !== 31337n) throw new Error("--fast is restricted to local Anvil chain 31337");
  if (!Number.isSafeInteger(steps) || steps < 1) throw new Error("STEPS must be a positive integer");
  const params = await vault.getParams();
  const interval = Number(params.minPokeInterval) + 2;
  console.log(`keeper ${keeperWallet.address} -> vault ${vault.target}; interval ${interval}s; replay=${replay} fast=${fast}`);

  if (replay) {
    const path = syntheticPath({ n: steps });
    for (let i = 0; i < path.length; i++) {
      if (fast) await advance(interval);
      await (await oracle.setPrice(to8(path[i]))).wait();
      await pokeOnce(`[${i + 1}/${path.length}]`);
      if (!fast) await sleep(interval * 1000);
      const pos = await vault.position();
      if (!pos.active && i > 0) {
        console.log("position closed; replay finished");
        break;
      }
    }
    return;
  }

  for (;;) {
    await pokeOnce("");
    await sleep(interval * 1000);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
