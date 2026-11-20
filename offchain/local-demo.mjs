// Deploy and exercise an isolated local chain. Never sends to a public network.
import { ethers } from "ethers";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import vm from "node:vm";
import assert from "node:assert/strict";
import { defaultParams } from "./lib.mjs";

const root=resolve(dirname(fileURLToPath(import.meta.url)),"..");
const rpc=process.env.RPC || "http://127.0.0.1:8548";
if(!["localhost","127.0.0.1","[::1]"].includes(new URL(rpc).hostname)) throw Error("Local loopback RPC required");
const provider=new ethers.JsonRpcProvider(rpc,undefined,{cacheTimeout:-1});
provider.pollingInterval=100;
assert.equal((await provider.getNetwork()).chainId,31337n,"Local chain 31337 required");
const admin=await provider.getSigner(0),owner=await provider.getSigner(1),keeper=await provider.getSigner(2);
const contracts={};
async function deploy(name,source,args=[]) {
  const a=JSON.parse(readFileSync(resolve(root,"out",source,name+".json")));
  const c=await new ethers.ContractFactory(a.abi,a.bytecode.object,admin).deploy(...args);
  await c.waitForDeployment(); contracts[name]=await c.getAddress(); return c;
}
const usdc=await deploy("MockUSDC","Mocks.sol");
const oracle=await deploy("MockOracle","Mocks.sol",[2000n*10n**8n]);
const perp=await deploy("MockPerp","Mocks.sol",[usdc.target,oracle.target]);
const vault=await deploy("MockPerpNeuroVault","MockPerpNeuroVault.sol",[await owner.getAddress(),oracle.target,usdc.target,perp.target]);
await (await usdc.mint(perp.target,1000000n*10n**6n)).wait();
await (await usdc.mint(vault.target,1000n*10n**6n)).wait();
const p=defaultParams();
await (await vault.connect(owner).signParams(p)).wait();
const opened=await (await vault.connect(owner).openPosition(true,5000n*10n**18n,1000n*10n**6n)).wait();
const start=await provider.getBlock(opened.blockNumber);
await assert.rejects(()=>vault.connect(keeper).withdraw.staticCall(usdc.target,1n));
await assert.rejects(()=>vault.connect(keeper).signParams.staticCall(p));

// Execute the actual dashboard model outside the browser as a pure math unit.
const html=readFileSync(resolve(root,"frontend/index.html"),"utf8");
const model=html.slice(html.indexOf("class Vault {"),html.indexOf("// ---------------------------------------------------------------- shared view state"));
const BrowserVault=vm.runInNewContext("const BPS=10000n,WAD=10n**18n;"+model+";Vault");
const bp={...p,tau:p.tau.map(BigInt),trailBps:p.trailBps.map(BigInt),memoryWindow:BigInt(p.memoryWindow),minMoveBps:BigInt(p.minMoveBps)};
const browserSim=new BrowserVault(bp,2000n*10n**18n,BigInt(start.timestamp));
const rows=[];
for(const [price,dt] of [[2010,60],[2020,60],[2030,60],[2080,60],[2110,60],[2105,60],[2150,60],[2140,60],[2130,60],[2200,60],[2100,60],[2100,2000],[1800,60]]) {
  await provider.send("evm_increaseTime",[dt]);
  await (await oracle.setPrice(BigInt(price)*10n**8n)).wait();
  const receipt=await (await vault.connect(keeper).poke({gasLimit:800000})).wait();
  const block=await provider.getBlock(receipt.blockNumber);
  browserSim.step(BigInt(price)*10n**18n,BigInt(block.timestamp));
  const pos=await vault.position(),potentials=await vault.getPotentials(),regime=await vault.regime();
  assert.equal(pos.stopPrice,browserSim.stop,"browser stop differs from contract");
  assert.equal(Number(regime),browserSim.regime,"browser regime differs");
  assert.equal(pos.active,browserSim.active,"browser active differs");
  assert.deepEqual([...potentials].map(String),[...browserSim.v].map(String),"browser potentials differ");
  rows.push({price,time:block.timestamp,stop:String(pos.stopPrice),active:pos.active,regime:Number(regime),potentials:[...potentials].map(String),transactionHash:receipt.hash});
}
const python=spawnSync(process.env.PYTHON || "python",["-c",`
import sys,json
sys.path.insert(0,'sim')
from snn_sim import NeuroVaultSim,DEFAULT_PARAMS
d=json.load(sys.stdin)
s=NeuroVaultSim(DEFAULT_PARAMS,2000*10**18,d['start'])
for r in d['rows']:
 s.step(r['price']*10**18,r['time'])
 assert str(s.stop)==r['stop']
 assert s.regime==r['regime']
 assert s.active==r['active']
 assert list(map(str,s.v))==r['potentials']
print('Python/Solidity/browser exact-state parity passed for all supplied ticks.')
`],{cwd:root,input:JSON.stringify({start:start.timestamp,rows}),encoding:"utf8"});
if(python.status!==0) throw Error(python.stderr);
console.log(python.stdout.trim());
const settled=await usdc.balanceOf(vault.target);
assert(settled>0n);
await (await vault.connect(owner).withdraw(usdc.target,settled)).wait();
assert.equal(await usdc.balanceOf(await owner.getAddress()),settled);

// Leave a fresh live position for visual QA.
await (await oracle.setPrice(2000n*10n**8n)).wait();
await (await usdc.mint(vault.target,1000n*10n**6n)).wait();
await (await vault.connect(owner).signParams(p)).wait();
const fresh=await (await vault.connect(owner).openPosition(true,5000n*10n**18n,1000n*10n**6n)).wait();
await provider.send("evm_increaseTime",[60]);
await (await oracle.setPrice(2010n*10n**8n)).wait();
await (await vault.connect(keeper).poke({gasLimit:800000})).wait();
mkdirSync(resolve(root,"deployments"),{recursive:true});
writeFileSync(resolve(root,"deployments/local.json"),JSON.stringify({chainId:31337,rpc,owner:await owner.getAddress(),...contracts,fromBlock:fresh.blockNumber},null,2));
mkdirSync(resolve(root,"evidence"),{recursive:true});
writeFileSync(resolve(root,"evidence/local-integration.json"),JSON.stringify({network:"isolated local Anvil, not Arc Testnet",chainId:31337,solidity:"0.8.24",ticks:rows.length,checks:["four-contract deployment","owner configuration and open","non-owner actions rejected","permissionless poke","exact browser/Solidity/Python state parity","stop settlement","owner withdrawal"],rows},null,2));
console.log("PASS local lifecycle, access control and model parity. Local-only addresses in deployments/local.json.");
console.log("Live preview: http://127.0.0.1:8089/index.html?"+new URLSearchParams({mode:"live",rpc,vault:vault.target,from:String(fresh.blockNumber)}));
provider.destroy();
