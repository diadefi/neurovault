// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GmxNeuroVault} from "../src/GmxNeuroVault.sol";
import {MockPerpNeuroVault} from "../src/MockPerpNeuroVault.sol";
import {MockUSDC, MockOracle, MockPerp} from "../src/mocks/Mocks.sol";
import {IAggregatorV3} from "../src/interfaces/IAggregatorV3.sol";
import {IGmxExchangeRouter} from "../src/interfaces/IGmxExchangeRouter.sol";

/// Deploy against GMX v2 on Arbitrum Sepolia.
///   OWNER=<hardware wallet address> GMX_MARKET=<ETH/USD market token> \
///   forge script script/Deploy.s.sol:DeployGmx --rpc-url $ARB_SEPOLIA_RPC --broadcast --private-key $DEPLOYER_KEY
/// The deployer key only pays gas. Ownership is immutable and goes to OWNER (the cold wallet).
contract DeployGmx is Script {
    // gmx-io/gmx-synthetics deployments/arbitrumSepolia
    address constant EXCHANGE_ROUTER = 0xEd50B2A1eF0C35DAaF08Da6486971180237909c3;
    address constant ROUTER = 0x72F13a44C8ba16a678CAD549F17bc9e06d2B8bD2;
    address constant ORDER_VAULT = 0x1b8AC606de71686fd2a1AEDEcb6E0EFba28909a2;
    // gmx-synthetics config/tokens.ts (arbitrumSepolia)
    address constant USDC_SG = 0x3253a335E7bFfB4790Aa4C25C4250d206E9b9773;
    address constant CHAINLINK_ETH_USD = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;

    function run() external {
        address owner = vm.envAddress("OWNER");
        address market = vm.envAddress("GMX_MARKET");
        address collateral = vm.envOr("COLLATERAL", USDC_SG);

        vm.startBroadcast();
        GmxNeuroVault vault = new GmxNeuroVault(
            owner,
            IAggregatorV3(CHAINLINK_ETH_USD),
            IERC20(collateral),
            IGmxExchangeRouter(EXCHANGE_ROUTER),
            ROUTER,
            ORDER_VAULT,
            market,
            18
        );
        vm.stopBroadcast();
        console2.log("GmxNeuroVault", address(vault));
    }
}

/// Self-contained fallback: mock USDC + settable oracle + mock perp + vault, on any EVM chain (e.g. Arc testnet).
///   OWNER=<hardware wallet address> forge script script/Deploy.s.sol:DeployMock --rpc-url $RPC --broadcast --private-key $DEPLOYER_KEY
contract DeployMock is Script {
    function run() external {
        address owner = vm.envAddress("OWNER");
        vm.startBroadcast();
        MockUSDC usdc = new MockUSDC();
        MockOracle oracle = new MockOracle(2000e8);
        MockPerp perp = new MockPerp(usdc, oracle);
        MockPerpNeuroVault vault = new MockPerpNeuroVault(owner, oracle, usdc, perp);
        usdc.mint(address(perp), 1_000_000e6);
        usdc.mint(address(vault), 1_000e6);
        vm.stopBroadcast();
        console2.log("MockUSDC", address(usdc));
        console2.log("MockOracle", address(oracle));
        console2.log("MockPerp", address(perp));
        console2.log("MockPerpNeuroVault", address(vault));
    }
}
