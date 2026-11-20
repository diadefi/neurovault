"""Export ABI + creation bytecode from the current forge build for wallet deployment."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
names = {
    "MockUSDC": "Mocks.sol", "MockOracle": "Mocks.sol", "MockPerp": "Mocks.sol",
    "MockPerpNeuroVault": "MockPerpNeuroVault.sol", "GmxNeuroVault": "GmxNeuroVault.sol",
}
artifacts = {}
for name, source in names.items():
    built = json.loads((root / "out" / source / f"{name}.json").read_text())
    artifacts[name] = {"abi": built["abi"], "bytecode": built["bytecode"]["object"]}
    (root / "offchain" / "abi" / f"{name}.json").write_text(json.dumps(built["abi"], indent=2))
(root / "frontend" / "artifacts.js").write_text("window.NV_ARTIFACTS = " + json.dumps(artifacts) + ";\n")
(root / "frontend" / "abi.js").write_text("window.NV_ABI = " + json.dumps(artifacts["MockPerpNeuroVault"]["abi"]) + ";\n")
(root / "frontend" / "contracts.js").write_text("window.NV_CONTRACTS = " + json.dumps(artifacts) + ";\n")
print("Exported 5 current contract artifacts and dashboard ABI.")
