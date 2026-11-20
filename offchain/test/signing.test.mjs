import test from "node:test";
import assert from "node:assert/strict";
import { ethers } from "ethers";
import { parseManualSignature } from "../lib.mjs";

test("manual signature round-trips both parity and legacy recovery formats", () => {
  const wallet = ethers.Wallet.createRandom();
  for (let i = 0; i < 20; i++) {
    const hash = ethers.id("NeuroVault signing regression " + i);
    const sig = wallet.signingKey.sign(hash);
    for (const v of [sig.yParity, sig.v]) {
      const parsed = parseManualSignature(`${sig.r},${sig.s},${v}`, ethers);
      assert.equal(ethers.recoverAddress(hash, parsed), wallet.address);
    }
    assert.equal(parseManualSignature(sig.serialized, ethers).serialized, sig.serialized);
    assert.throws(() => parseManualSignature(`${sig.r},${sig.s},29`, ethers));
  }
});
