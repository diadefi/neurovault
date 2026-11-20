// Usage: node offchain/record-deployment.mjs <downloaded-manifest.json>
// Read-only chain verification; writes public deployment evidence locally.
import { ethers } from "ethers";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve,dirname } from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";
const root=resolve(dirname(fileURLToPath(import.meta.url)),"..");
if(!process.argv[2]) throw Error("Pass the downloaded Arc deployment manifest path");
const input=JSON.parse(readFileSync(process.argv[2],"utf8"));
const rpc="https://rpc.testnet.arc.io", chain=5042002;
const owner=ethers.getAddress("0xd952691a2b11dbaadc4addbad59597772302fa02");
assert.equal(input.chainId,chain); assert.equal(ethers.getAddress(input.owner),owner);
const p=new ethers.JsonRpcProvider(rpc);
assert.equal((await p.getNetwork()).chainId,BigInt(chain));
const sources={MockUSDC:"Mocks.sol",MockOracle:"Mocks.sol",MockPerp:"Mocks.sol",MockPerpNeuroVault:"MockPerpNeuroVault.sol"};
const output={network:"Arc Testnet",chainId:chain,rpc,owner,verifiedAt:new Date().toISOString(),fromBlock:input.fromBlock,transactions:[]};
const contracts={};
for(const [name,src] of Object.entries(sources)) {
  const address=ethers.getAddress(input[name]), code=await p.getCode(address);
  assert.notEqual(code,"0x",name+" has no code");
  const built=JSON.parse(readFileSync(resolve(root,"out",src,name+".json")));
  const expected=Buffer.from(built.deployedBytecode.object.replace(/^0x/,""),"hex"),actual=Buffer.from(code.slice(2),"hex");
  for(const refs of Object.values(built.deployedBytecode.immutableReferences || {})) for(const {start,length} of refs) {
    expected.fill(0,start,start+length);actual.fill(0,start,start+length);
  }
  assert(expected.equals(actual),name+" runtime code differs from the current local build");
  contracts[name]=new ethers.Contract(address,built.abi,p);output[name]=address;
}
const v=contracts.MockPerpNeuroVault;
assert.equal(await v.owner(),owner);
assert.equal(await v.oracle(),output.MockOracle);
assert.equal(await v.collateralToken(),output.MockUSDC);
assert.equal(await v.perp(),output.MockPerp);
assert.equal(await contracts.MockPerp.usdc(),output.MockUSDC);
assert.equal(await contracts.MockPerp.oracle(),output.MockOracle);
assert.equal(await contracts.MockUSDC.decimals(),6n);
output.oracleAdmin=await contracts.MockOracle.admin();
assert(Number.isSafeInteger(output.fromBlock)&&output.fromBlock>0,"Missing deployment block");
for(const t of input.transactions || []) {
  const r=await p.getTransactionReceipt(t.hash);
  assert(r&&r.status===1,"Missing/reverted receipt "+t.hash);
  output.transactions.push({hash:r.hash,block:r.blockNumber,feeUSDC:ethers.formatUnits(r.gasUsed*r.gasPrice,18)});
}
output.paramsHash=await v.paramsHash();
const pos=await v.position();output.positionActive=pos.active;
mkdirSync(resolve(root,"deployments"),{recursive:true});
writeFileSync(resolve(root,"deployments/arc-testnet.json"),JSON.stringify(output,null,2));
writeFileSync(resolve(root,"frontend/deployment.json"),JSON.stringify(output,null,2));
const readme=resolve(root,"README.md");let md=readFileSync(readme,"utf8");
md=md.replace("Public-chain deployment is **pending funding and wallet signatures**.","Public mock contracts are deployed on **Arc Testnet**; see verified evidence in `deployments/arc-testnet.json`.");
for(const [name,address] of Object.entries(output)) if(sources[name]) {
  md=md.replace(new RegExp("(\\| "+name+"[^\\n]*\\| Arc Testnet \\| )Pending deployment"),`$1[${address}](https://explorer.testnet.arc.io/address/${address})`);
}
writeFileSync(readme,md);
console.log("Verified Arc chain, current-build runtime bytecode, contract relationships, owner and receipts. Wrote public evidence.");
console.log(JSON.stringify(output,null,2));p.destroy();
