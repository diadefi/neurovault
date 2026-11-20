// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NeuroVault} from "../src/NeuroVault.sol";
import {GmxNeuroVault} from "../src/GmxNeuroVault.sol";
import {IGmxExchangeRouter, GmxOrder} from "../src/interfaces/IGmxExchangeRouter.sol";
import {MockUSDC, MockOracle} from "../src/mocks/Mocks.sol";

/// @dev Records what the vault sends to GMX so we can check encoding and units.
contract RecordingExchangeRouter {
    struct Created {
        uint8 orderType;
        bool isLong;
        uint256 sizeDeltaUsd;
        uint256 collateral;
        uint256 trigger;
        uint256 acceptable;
        address receiver;
        bool autoCancel;
    }

    Created[] public created;
    bytes32 public lastUpdatedKey;
    uint256 public lastUpdatedTrigger;
    uint256 public wntReceived;
    IERC20 public immutable token;
    uint256 nonce;

    constructor(IERC20 t) {
        token = t;
    }

    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i; i < data.length; ++i) {
            (bool ok, bytes memory r) = address(this).delegatecall(data[i]);
            require(ok, "call failed");
            results[i] = r;
        }
    }

    function sendWnt(address, uint256 amount) external payable {
        wntReceived += amount;
    }

    function sendTokens(address t, address, uint256 amount) external payable {
        IERC20(t).transferFrom(msg.sender, address(this), amount);
    }

    function createOrder(GmxOrder.CreateOrderParams calldata p) external payable returns (bytes32 key) {
        created.push(
            Created(
                p.orderType,
                p.isLong,
                p.numbers.sizeDeltaUsd,
                p.numbers.initialCollateralDeltaAmount,
                p.numbers.triggerPrice,
                p.numbers.acceptablePrice,
                p.addresses.receiver,
                p.autoCancel
            )
        );
        key = keccak256(abi.encode(++nonce));
    }

    function updateOrder(bytes32 key, uint256, uint256, uint256 trigger, uint256, uint256, bool) external payable {
        lastUpdatedKey = key;
        lastUpdatedTrigger = trigger;
    }

    function count() external view returns (uint256) {
        return created.length;
    }
}

contract GmxNeuroVaultTest is Test {
    MockUSDC usdc;
    MockOracle oracle;
    RecordingExchangeRouter router;
    GmxNeuroVault vault;
    address cold = address(0xC01D);

    function setUp() public {
        vm.warp(1_700_000_000);
        usdc = new MockUSDC();
        oracle = new MockOracle(2000e8);
        router = new RecordingExchangeRouter(usdc);
        vault = new GmxNeuroVault(
            cold, oracle, usdc, IGmxExchangeRouter(address(router)), address(router), address(0x0A17), address(0x3A12), 18
        );
        usdc.mint(address(vault), 1_000e6);
        vm.deal(address(vault), 1 ether);

        NeuroVault.Params memory p;
        p.tau = new uint32[](1);
        p.weight = new uint256[](1);
        p.theta = new uint256[](1);
        p.trailBps = new uint16[](2);
        p.tau[0] = 600;
        p.weight[0] = 1e18;
        p.theta[0] = 0.01e18;
        (p.trailBps[0], p.trailBps[1]) = (200, 500);
        p.minPokeInterval = 60;
        p.maxOracleAge = 3600;
        p.minMoveBps = 10;

        vm.startPrank(cold);
        vault.signParams(p);
        vault.setGmxFees(0.001 ether, 0, 100);
        vault.openPosition(true, 5_000e18, 1_000e6);
        vm.stopPrank();
    }

    function test_openCreatesIncreaseThenStopWithGmxUnits() public view {
        assertEq(router.count(), 2);
        (uint8 t0, bool long0, uint256 size0, uint256 coll0,, uint256 acc0, address recv0,) = router.created(0);
        assertEq(t0, GmxOrder.MARKET_INCREASE);
        assertTrue(long0);
        assertEq(size0, 5_000e30); // 30-decimal USD
        assertEq(coll0, 1_000e6);
        assertEq(acc0, 2020e12); // 2000 * 1.01, per-wei price for 18-dec token: usd * 1e12
        assertEq(recv0, address(vault)); // proceeds only ever go back to the vault

        (uint8 t1,,,, uint256 trig1, uint256 acc1,, bool auto1) = router.created(1);
        assertEq(t1, GmxOrder.STOP_LOSS_DECREASE);
        assertEq(trig1, 1960e12); // 2% calm trail
        assertEq(acc1, 0); // stop is never skipped on slippage
        assertTrue(auto1);
        assertEq(router.wntReceived(), 0.002 ether);
        assertEq(usdc.balanceOf(address(router)), 1_000e6);
    }

    function test_pokeTightensGmxStopOrder() public {
        vm.warp(block.timestamp + 60);
        oracle.setPrice(2010e8);
        vault.poke();
        assertEq(router.lastUpdatedKey(), vault.stopOrderKey());
        assertEq(router.lastUpdatedTrigger(), (2010e12 * 9800) / 10_000);
    }

    function test_closeCreatesMarketDecrease() public {
        vm.prank(cold);
        vault.closePosition();
        (uint8 t2, bool long2, uint256 size2,,, uint256 acc2,,) = router.created(2);
        assertEq(t2, GmxOrder.MARKET_DECREASE);
        assertTrue(long2);
        assertEq(size2, 5_000e30);
        assertEq(acc2, 1980e12); // 2000 * 0.99 min acceptable for a long decrease
    }
}
