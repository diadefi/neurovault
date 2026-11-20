// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {NeuroVault} from "../src/NeuroVault.sol";
import {GmxNeuroVault} from "../src/GmxNeuroVault.sol";

/// Owner actions, meant to be signed by the hardware wallet:
///   VAULT=0x... forge script script/Operate.s.sol:SignAndOpen --rpc-url $RPC --broadcast --ledger --sender $OWNER
/// Optional env: IS_LONG (default true), SIZE_USD (default 50), COLLATERAL_AMOUNT (token units, required),
///               EXEC_FEE_WEI (default 0.003 ether; GMX refunds the excess to the vault).
contract SignAndOpen is Script {
    function defaultParams() internal pure returns (NeuroVault.Params memory p) {
        p.tau = new uint32[](3);
        p.weight = new uint256[](3);
        p.theta = new uint256[](3);
        p.trailBps = new uint16[](4);
        (p.tau[0], p.tau[1], p.tau[2]) = (600, 600, 600);
        (p.weight[0], p.weight[1], p.weight[2]) = (1e18, 1e18, 1e18);
        (p.theta[0], p.theta[1], p.theta[2]) = (0.01e18, 0.02e18, 0.04e18);
        (p.trailBps[0], p.trailBps[1], p.trailBps[2], p.trailBps[3]) = (200, 350, 500, 800);
        p.memoryWindow = 1800;
        p.minMoveBps = 10;
        p.minPokeInterval = 60;
        p.maxOracleAge = 86400; // testnet Chainlink feeds update slowly
    }

    function run() external {
        GmxNeuroVault vault = GmxNeuroVault(payable(vm.envAddress("VAULT")));
        bool isLong = vm.envOr("IS_LONG", true);
        uint256 sizeUsd = vm.envOr("SIZE_USD", uint256(50)) * 1e18;
        uint256 collateral = vm.envUint("COLLATERAL_AMOUNT");
        uint256 fee = vm.envOr("EXEC_FEE_WEI", uint256(0.003 ether));

        vm.startBroadcast();
        vault.signParams(defaultParams());
        vault.setGmxFees(fee, 0, 100);
        vault.openPosition(isLong, sizeUsd, collateral);
        vm.stopBroadcast();

        console2.log("paramsHash");
        console2.logBytes32(vault.paramsHash());
        console2.log("increaseOrderKey");
        console2.logBytes32(vault.increaseOrderKey());
        console2.log("stopOrderKey");
        console2.logBytes32(vault.stopOrderKey());
    }
}
