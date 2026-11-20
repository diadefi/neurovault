"use strict";
const OWNER = ethers.getAddress("0xd952691a2b11dbaadc4addbad59597772302fa02");
const CHAIN = 5042002n, RPC = "https://rpc.testnet.arc.io";
const KEY = "neurovault:5042002:" + OWNER;
const $ = id => document.getElementById(id);
const A = window.NV_ARTIFACTS;
let provider, signer, account, state = { chainId: Number(CHAIN), owner: OWNER, transactions: [] };
let phase = "Ready";
try { const saved = JSON.parse(localStorage.getItem(KEY)); if (saved) state = saved; } catch {}
$("intendedOwner").textContent = OWNER;
function say(s) { $("status").textContent = s; }
function setPhase(s) { phase = s; say(s); }
function note(s) { $("log").textContent = s + "\n" + $("log").textContent; }
function save() { localStorage.setItem(KEY, JSON.stringify(state)); render(); }
function render() {
  $("addresses").replaceChildren();
  for (const name of ["MockUSDC", "MockOracle", "MockPerp", "MockPerpNeuroVault"]) {
    if (!state[name]) continue;
    const p = document.createElement("p"), link = document.createElement("a");
    link.textContent = state[name]; link.href = "https://explorer.testnet.arc.io/address/" + state[name]; link.target = "_blank"; link.rel = "noopener";
    p.append(name + ": ", link); $("addresses").append(p);
  }
  if (state.MockPerpNeuroVault) {
    const q = new URLSearchParams({mode:"live",rpc:RPC,vault:state.MockPerpNeuroVault,from:String(state.fromBlock || 0)});
    $("liveLink").href = "index.html?" + q;
  }
}
async function connect() {
  if (!window.ethereum) throw Error("Open this page in the browser where MetaMask is installed.");
  await window.ethereum.request({method:"eth_requestAccounts"});
  try { await window.ethereum.request({method:"wallet_switchEthereumChain",params:[{chainId:"0x4cef52"}]}); }
  catch(e) {
    if (e.code !== 4902) throw e;
    await window.ethereum.request({method:"wallet_addEthereumChain",params:[{chainId:"0x4cef52",chainName:"Arc Testnet",nativeCurrency:{name:"USDC",symbol:"USDC",decimals:18},rpcUrls:[RPC],blockExplorerUrls:["https://explorer.testnet.arc.io"]}]});
  }
  provider = new ethers.BrowserProvider(window.ethereum);
  signer = await provider.getSigner(); account = await signer.getAddress();
  if ((await provider.getNetwork()).chainId !== CHAIN) throw Error("Select Arc Testnet in MetaMask.");
  const bal = await provider.getBalance(account);
  $("wallet").textContent = account + " · " + ethers.formatEther(bal) + " test USDC";
  say(bal === 0n ? "Connected. Get Arc Testnet test USDC before deploying." : "Connected to Arc Testnet.");
}
async function ready(ownerOnly = false) {
  if (!signer) await connect();
  const accounts = await window.ethereum.request({method:"eth_accounts"});
  if (!accounts.length || ethers.getAddress(accounts[0]) !== account) throw Error("Wallet account changed. Reconnect before continuing.");
  if (BigInt(await window.ethereum.request({method:"eth_chainId"})) !== CHAIN) throw Error("Switch back to Arc Testnet.");
  if (ownerOnly && account !== OWNER) throw Error("Select owner " + OWNER + " in MetaMask.");
}
function contract(name) {
  if (!state[name] || !ethers.isAddress(state[name])) throw Error("Deploy or import the mock contracts first.");
  return new ethers.Contract(state[name], A[name].abi, signer);
}
async function verifyDeployment() {
  const v = contract("MockPerpNeuroVault");
  if ((await v.owner()) !== OWNER || (await v.oracle()) !== ethers.getAddress(state.MockOracle) ||
      (await v.collateralToken()) !== ethers.getAddress(state.MockUSDC) || (await v.perp()) !== ethers.getAddress(state.MockPerp)) {
    throw Error("Deployment addresses do not match the vault's owner and contracts.");
  }
}
async function receipt(label, txPromise) {
  say(label + ": review in MetaMask…");
  const tx = await txPromise;
  note(label + " submitted: " + tx.hash);
  const r = await tx.wait();
  if (!r || r.status !== 1) throw Error(label + " did not succeed.");
  const feeUSDC = ethers.formatUnits(r.gasUsed * r.gasPrice,18);
  state.transactions.push({label,hash:tx.hash,block:r.blockNumber,feeUSDC}); save();
  note(label + " confirmed in block " + r.blockNumber + " · network fee " + feeUSDC + " test USDC"); return r;
}
async function deployOne(name, args) {
  if (state[name]) {
    if (await provider.getCode(state[name]) === "0x") throw Error(name + " saved address has no deployed code.");
    return;
  }
  // Save the predicted address and hash immediately after submission, so a reload
  // can resume a mined transaction without deploying the same component twice.
  const pending = state.pending;
  let r;
  if (pending && pending.name === name) {
    r = await provider.getTransactionReceipt(pending.hash);
    if (!r) throw Error("A deployment is still pending: " + pending.hash + ". Wait, then resume.");
    if (r.status !== 1) { delete state.pending; save(); throw Error("Previous deployment reverted. Resume to retry."); }
  } else {
    const factory = new ethers.ContractFactory(A[name].abi, A[name].bytecode, signer);
    setPhase("Deploy " + name + ": review in MetaMask…");
    const c = await factory.deploy(...args), tx = c.deploymentTransaction();
    state.pending = {name,hash:tx.hash,address:await c.getAddress()}; save();
    note("Deploy " + name + " submitted: " + tx.hash);
    r = await tx.wait();
    if (!r || r.status !== 1) throw Error(name + " deployment failed.");
  }
  state[name] = state.pending.address;
  state.transactions.push({label:"Deploy " + name,hash:state.pending.hash,block:r.blockNumber,feeUSDC:ethers.formatUnits(r.gasUsed*r.gasPrice,18)});
  if (name === "MockPerpNeuroVault") state.fromBlock = r.blockNumber;
  delete state.pending; save();
}
function params() {
  const w = 10n ** 18n;
  return {tau:[600,600,600],weight:[w,w,w],theta:[w/100n,w/50n,w/25n],trailBps:[200,350,500,800],memoryWindow:1800,minMoveBps:10,minPokeInterval:60,maxOracleAge:86400};
}
const actions = {
  connect,
  deploy: async () => {
    await ready();
    if (state.deployer && state.deployer !== account) throw Error("Reconnect original deployer " + state.deployer + " to resume.");
    state.deployer = account; save();
    await deployOne("MockUSDC", []);
    await deployOne("MockOracle", [2000n * 10n ** 8n]);
    await deployOne("MockPerp", [state.MockUSDC,state.MockOracle]);
    await deployOne("MockPerpNeuroVault", [OWNER,state.MockOracle,state.MockUSDC,state.MockPerp]);
    await verifyDeployment();
    const token = contract("MockUSDC");
    if (!state.liquidityFunded) {
      const balance = await token.balanceOf(state.MockPerp), target = 1000000n*10n**6n;
      if (balance < target) await receipt("Mint mock venue liquidity",token.mint(state.MockPerp,target-balance));
      state.liquidityFunded = true; save();
    }
    if (!state.vaultFunded) {
      const balance = await token.balanceOf(state.MockPerpNeuroVault), target = 1000n*10n**6n;
      if (balance < target) await receipt("Mint mock collateral",token.mint(state.MockPerpNeuroVault,target-balance));
      state.vaultFunded = true; save();
    }
    say("Deployment complete. Download addresses, then sign settings and open the demo long.");
  },
  params: async () => { await ready(true); await verifyDeployment(); await receipt("Sign neuron settings",contract("MockPerpNeuroVault").signParams(params())); },
  open: async () => { await ready(true); await verifyDeployment(); await receipt("Open demo long",contract("MockPerpNeuroVault").openPosition(true,5000n*10n**18n,1000n*10n**6n)); },
  close: async () => { await ready(true); await verifyDeployment(); await receipt("Close position",contract("MockPerpNeuroVault").closePosition()); },
  withdraw: async () => { await ready(true); await verifyDeployment(); const amount = await contract("MockUSDC").balanceOf(state.MockPerpNeuroVault); if(!amount) throw Error("No mUSDC is available in the vault."); await receipt("Withdraw mUSDC to owner",contract("MockPerpNeuroVault").withdraw(state.MockUSDC,amount)); },
  setPrice: async () => { await ready(); await verifyDeployment(); const oracle = contract("MockOracle"); if (await oracle.admin() !== account) throw Error("Select the mock oracle deployer account."); const p = ethers.parseUnits($("price").value,8); if(p<=0n) throw Error("Price must be positive."); await receipt("Set demo price",oracle.setPrice(p)); },
  poke: async () => { await ready(); await verifyDeployment(); await receipt("Permissionless poke",contract("MockPerpNeuroVault").poke({gasLimit:800000})); },
  sync: async () => { await ready(); await verifyDeployment(); await receipt("Sync settled position",contract("MockPerpNeuroVault").syncPosition()); },
  export: async () => {
    if (!state.MockPerpNeuroVault) throw Error("Deploy the vault first.");
    const blob = new Blob([JSON.stringify(state,null,2)],{type:"application/json"});
    const url = URL.createObjectURL(blob), a = document.createElement("a"); a.href=url; a.download="neurovault-arc-testnet.json"; a.click(); setTimeout(()=>URL.revokeObjectURL(url),1000);
  },
};
for (const [id,fn] of Object.entries(actions)) $(id).onclick = async () => {
  const buttons = [...document.querySelectorAll("button")]; buttons.forEach(b=>b.disabled=true);
  phase = $(id).textContent.trim();
  try { await fn(); if(!["connect","deploy"].includes(id)) say("Done. Transaction evidence is below."); }
  catch(e) { const msg=window.NV_walletError(e); say(msg); note(phase + "\nAction stopped: " + msg); }
  finally { buttons.forEach(b=>b.disabled=false); }
};
$("import").onchange = async e => {
  try {
    const file=e.target.files[0]; if(!file) return;
    const d=JSON.parse(await file.text());
    if(d.chainId !== Number(CHAIN) || ethers.getAddress(d.owner) !== OWNER) throw Error("Wrong chain or owner in deployment file.");
    for(const name of ["MockUSDC","MockOracle","MockPerp","MockPerpNeuroVault"]) if(!ethers.isAddress(d[name])) throw Error("Invalid address: "+name);
    if(!Number.isSafeInteger(d.fromBlock) || d.fromBlock<0) throw Error("Invalid deployment block.");
    state={...d,transactions:Array.isArray(d.transactions)?d.transactions:[]}; save(); say("Deployment restored. Contract relationships will be verified before actions.");
  } catch(e) { say(e.message); }
};
if(window.ethereum?.on) {
  for(const event of ["accountsChanged","chainChanged"]) window.ethereum.on(event,()=>{provider=null;signer=null;account=null;say("Wallet changed. Reconnect before continuing.");});
}
render();
