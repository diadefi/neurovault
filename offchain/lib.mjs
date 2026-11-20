// Shared helpers for the keeper and the owner-transaction tool.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
export const abi = (name) => JSON.parse(readFileSync(join(here, "abi", `${name}.json`), "utf8"));

export const WAD = 10n ** 18n;

/** Raw EIP-1559 hash signatures, not personal_sign / prefixed message signatures. */
export function parseManualSignature(answer, ethers) {
  if (!answer.includes(",")) return ethers.Signature.from(answer);
  const fields = answer.split(",").map(x => x.trim());
  if (fields.length !== 3) throw new Error("Expected r,s,yParity (0/1) or r,s,v (27/28)");
  const [r, s, raw] = fields;
  const v = Number(raw);
  if (!raw || ![0, 1, 27, 28].includes(v)) throw new Error("Recovery value must be 0, 1, 27, or 28");
  return ethers.Signature.from({r, s, yParity: v >= 27 ? v - 27 : v});
}

/** Default spiking layer: 3 bands (1%, 2%, 4% integrated |return|), trails 2/3.5/5/8%. */
export function defaultParams() {
  return {
    tau: [600, 600, 600],
    weight: [WAD, WAD, WAD],
    theta: [WAD / 100n, (2n * WAD) / 100n, (4n * WAD) / 100n],
    trailBps: [200, 350, 500, 800],
    memoryWindow: 1800,
    minMoveBps: 10,
    minPokeInterval: 60,
    maxOracleAge: 86400,
  };
}

/** Seeded regime-switching price path: calm drift, a volatility burst, calm again. */
export function syntheticPath({ n = 720, p0 = 2000, seed = 6, burstStart = 240, burstLen = 90 } = {}) {
  let s = seed >>> 0;
  const rand = () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const gauss = () => Math.sqrt(-2 * Math.log(rand() || 1e-12)) * Math.cos(2 * Math.PI * rand());
  const out = [];
  let p = p0;
  for (let k = 0; k < n; k++) {
    const burst = k >= burstStart && k < burstStart + burstLen;
    const sigma = burst ? 0.0035 : 0.0003;
    const drift = burst ? 0 : 0.00008;
    p *= Math.exp(drift + sigma * gauss());
    out.push(p);
  }
  return out;
}

/** USD float -> Chainlink 8-decimal answer. */
export const to8 = (usd) => BigInt(Math.round(usd * 1e8));

export function requireEnv(name) {
  const v = process.env[name];
  if (!v) {
    console.error(`missing env ${name}`);
    process.exit(1);
  }
  return v;
}
