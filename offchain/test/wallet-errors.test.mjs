import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
const context = vm.createContext({});
vm.runInContext(readFileSync(new URL("../../frontend/wallet-errors.js", import.meta.url), "utf8"), context);
const describe = context.NV_walletError;

test("wallet error exposes nested RPC cause rather than generic ethers wrapper", () => {
  const msg = describe({code:"UNKNOWN_ERROR",shortMessage:"could not coalesce error",payload:{method:"eth_estimateGas"},error:{code:-32603,message:"Internal JSON-RPC error.",data:{originalError:{code:-32000,message:"transaction underpriced"}}}});
  assert.match(msg,/transaction underpriced/);
  assert.match(msg,/eth_estimateGas/);
  assert.doesNotMatch(msg,/could not coalesce/);
});
test("pending wallet requests and declines get specific messages", () => {
  assert.match(describe({error:{code:-32002,message:"request pending"}}),/already has a pending request/);
  assert.match(describe({error:{code:4001,message:"User rejected"}}),/declined/);
});
test("wallet error handles cyclic causes and omits serialized request payload", () => {
  const error={message:'failure (error={"transaction":"PRIVATE-DATA"})'};error.cause=error;
  assert.equal(describe(error),"failure");
});
