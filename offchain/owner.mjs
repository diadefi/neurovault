#!/usr/bin/env node
// Owner (cold wallet) transactions with a pluggable signer.
//
// Foundry can only drive Ledger/Trezor. This tool builds each owner transaction as an
// UNSIGNED EIP-1559 transaction, hands it to a signer, checks the signature recovers to
// the owner, then broadcasts. Swap the signer without touching anything else:
//
//   SIGNER=software   OWNER_KEY=0x...      software stand-in (throwaway testnet key)
//   SIGNER=manual     OWNER=0x...          air-gapped: prints the hash, you paste r,s,v
//   SIGNER=shoreline  OWNER=0x... PORT=... Shoreline-1 over serial (transport TODO)
//
// Commands (RPC and VAULT env required):
//   fund-eth  <ether>                      send ETH float for GMX execution fees
//   set-fees  <execFeeEther> [topUpEther] [slippageBps]     (GMX vault only)
//   sign-params                            sign the default spiking-layer params
//   open      <long|short> <sizeUsd> <collateralWei>
//   close
//   withdraw  <token> <amountWei>
//   withdraw-eth <amountWei>
// Flags: --dry  build + print the unsigned tx, do not sign or send.
import { ethers } from "ethers";
import { writeFileSync } from "node:fs";
import { createInterface } from "node:readline/promises";
import { abi, defaultParams, requireEnv, parseManualSignature } from "./lib.mjs";

const argv = process.argv.slice(2);
const dry = argv.includes("--dry");
const [cmd, ...rest] = argv.filter((a) => a !== "--dry");

const provider = new ethers.JsonRpcProvider(requireEnv("RPC"));
const vaultAddr = requireEnv("VAULT");
const iface = new ethers.Interface(abi("GmxNeuroVault"));

// ----------------------------------------------------------------- signers

const signers = {
  software: () => {
    const key = new ethers.SigningKey(requireEnv("OWNER_KEY"));
    return {
      address: ethers.computeAddress(key.publicKey),
      // Signs the 32-byte EIP-1559 signing hash, exactly what a hardware wallet does.
      sign: async (tx) => key.sign(tx.unsignedHash),
    };
  },

  manual: () => ({
    address: ethers.getAddress(requireEnv("OWNER")),
    sign: async (tx) => {
      console.log("\nSign this EIP-1559 transaction on the device.");
      console.log("unsigned tx (RLP):", tx.unsignedSerialized);
      console.log("signing hash     :", tx.unsignedHash);
      const rl = createInterface({ input: process.stdin, output: process.stdout });
      const answer = (await rl.question("paste 65-byte signature (0x r||s||v) or r,s,yParity: ")).trim();
      rl.close();
      return parseManualSignature(answer, ethers);
    },
  }),

  shoreline: () => ({
    address: ethers.getAddress(requireEnv("OWNER")),
    sign: async (tx) => {
      // TODO(Shoreline-1): open PORT, send tx.unsignedSerialized (or tx.unsignedHash,
      // whichever the firmware expects), wait for the user to confirm on-device, read
      // back (r, s, yParity) and return ethers.Signature.from({ r, s, yParity }).
      throw new Error(
        "Shoreline-1 serial transport not wired yet. Use SIGNER=manual to sign with the device by copy-paste."
      );
    },
  }),
};

// ----------------------------------------------------------------- commands

function build() {
  const ether = (x) => ethers.parseEther(String(x));
  switch (cmd) {
    case "fund-eth":
      return { to: vaultAddr, data: "0x", value: ether(rest[0]) };
    case "set-fees":
      return {
        to: vaultAddr,
        data: iface.encodeFunctionData("setGmxFees", [ether(rest[0]), ether(rest[1] ?? 0), Number(rest[2] ?? 100)]),
      };
    case "sign-params":
      return { to: vaultAddr, data: iface.encodeFunctionData("signParams", [defaultParams()]) };
    case "open": {
      if (!["long", "short"].includes(rest[0])) throw new Error("side must be long or short");
      const isLong = rest[0] !== "short";
      const sizeUsd = ethers.parseUnits(String(rest[1]), 18);
      return { to: vaultAddr, data: iface.encodeFunctionData("openPosition", [isLong, sizeUsd, BigInt(rest[2])]) };
    }
    case "close":
      return { to: vaultAddr, data: iface.encodeFunctionData("closePosition", []) };
    case "withdraw":
      return { to: vaultAddr, data: iface.encodeFunctionData("withdraw", [rest[0], BigInt(rest[1])]) };
    case "withdraw-eth":
      return { to: vaultAddr, data: iface.encodeFunctionData("withdrawEth", [BigInt(rest[0])]) };
    default:
      console.error("unknown command; see header of offchain/owner.mjs");
      process.exit(1);
  }
}

async function main() {
  const mode = process.env.SIGNER ?? "software";
  if (!signers[mode]) throw new Error(`unknown SIGNER ${mode}`);
  const signer = signers[mode]();
  const req = build();
  const owner = signer.address;

  const onchainOwner = await new ethers.Contract(vaultAddr, iface, provider).owner();
  if (ethers.getAddress(onchainOwner) !== owner) {
    throw new Error(`signer ${owner} is not the vault owner ${onchainOwner}`);
  }

  const [nonce, net, fee] = await Promise.all([
    provider.getTransactionCount(owner, "pending"),
    provider.getNetwork(),
    provider.getFeeData(),
  ]);
  const gas = await provider.estimateGas({ ...req, from: owner });

  const tx = ethers.Transaction.from({
    type: 2,
    chainId: net.chainId,
    nonce,
    to: req.to,
    data: req.data,
    value: req.value ?? 0n,
    gasLimit: (gas * 13n) / 10n,
    maxFeePerGas: fee.maxFeePerGas,
    maxPriorityFeePerGas: fee.maxPriorityFeePerGas ?? 0n,
  });

  const record = {
    cmd,
    owner,
    chainId: net.chainId.toString(),
    nonce,
    to: tx.to,
    value: tx.value.toString(),
    data: tx.data,
    unsignedSerialized: tx.unsignedSerialized,
    unsignedHash: tx.unsignedHash,
  };
  writeFileSync("pending-tx.json", JSON.stringify(record, null, 2));
  console.log(`built ${cmd}: nonce ${nonce}, chain ${net.chainId}, gas ${tx.gasLimit}; wrote pending-tx.json`);
  if (dry) return;

  tx.signature = await signer.sign(tx);
  if (ethers.getAddress(tx.from) !== owner) {
    throw new Error(`signature recovers to ${tx.from}, expected ${owner}; not broadcasting`);
  }

  const sent = await provider.broadcastTransaction(tx.serialized);
  console.log("sent", sent.hash);
  const r = await sent.wait();
  console.log(`mined in block ${r.blockNumber}, status ${r.status}`);
}

main().catch((e) => {
  console.error(e.shortMessage ?? e.message);
  process.exit(1);
});
