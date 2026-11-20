// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {NeuroVault} from "../src/NeuroVault.sol";
import {MockPerpNeuroVault} from "../src/MockPerpNeuroVault.sol";
import {MockUSDC, MockOracle, MockPerp} from "../src/mocks/Mocks.sol";

contract NeuroVaultTest is Test {
    MockUSDC usdc;
    MockOracle oracle;
    MockPerp perp;
    MockPerpNeuroVault vault;

    address cold = address(0xC01D);
    address attacker = address(0xBAD);

    function setUp() public {
        vm.warp(1_700_000_000);
        usdc = new MockUSDC();
        oracle = new MockOracle(2000e8);
        perp = new MockPerp(usdc, oracle);
        vault = new MockPerpNeuroVault(cold, oracle, usdc, perp);

        usdc.mint(address(perp), 1_000_000e6); // venue liquidity
        usdc.mint(address(vault), 1_000e6); // cold wallet funded the vault
    }

    // ------------------------------------------------------------------ helpers

    function _params() internal pure returns (NeuroVault.Params memory p) {
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
        p.maxOracleAge = 3600;
    }

    function _signAndOpenLong() internal {
        vm.startPrank(cold);
        vault.signParams(_params());
        vault.openPosition(true, 5_000e18, 1_000e6);
        vm.stopPrank();
    }

    function _priceAndPoke(int256 p) internal {
        vm.warp(block.timestamp + 60);
        oracle.setPrice(p);
        vm.prank(attacker); // pokes come from an untrusted caller on purpose
        vault.poke();
    }

    function _stop() internal view returns (uint256 s) {
        (,,,,,, s) = vault.position();
    }

    function _active() internal view returns (bool a) {
        (a,,,,,,) = vault.position();
    }

    // ------------------------------------------------------------------ access control

    function test_onlyOwnerCanSignOpenWithdraw() public {
        NeuroVault.Params memory p = _params();
        vm.startPrank(attacker);
        vm.expectRevert(NeuroVault.NotOwner.selector);
        vault.signParams(p);
        vm.expectRevert(NeuroVault.NotOwner.selector);
        vault.openPosition(true, 1e18, 1e6);
        vm.expectRevert(NeuroVault.NotOwner.selector);
        vault.withdraw(address(usdc), 1);
        vm.expectRevert(NeuroVault.NotOwner.selector);
        vault.closePosition();
        vm.stopPrank();
    }

    function test_withdrawAlwaysGoesToOwner() public {
        vm.prank(cold);
        vault.withdraw(address(usdc), 100e6);
        assertEq(usdc.balanceOf(cold), 100e6);
    }

    function test_externalStopSettlementSyncsAfterPriceRebound() public {
        _signAndOpenLong();
        oracle.setPrice(1950e8);
        vm.prank(attacker);
        perp.executeStop(address(vault));
        assertEq(usdc.balanceOf(address(vault)), 875e6);
        vm.warp(block.timestamp + 60);
        oracle.setPrice(2100e8);
        vm.prank(attacker);
        vault.poke();
        assertFalse(_active());
        assertEq(perp.lastExitPrice(address(vault)), 1950e18);
        vm.prank(cold);
        vault.openPosition(true, 1000e18, 500e6);
        assertTrue(_active());
    }

    function test_externalSettlementSyncDoesNotNeedFreshOracle() public {
        _signAndOpenLong();
        oracle.setPrice(1950e8);
        perp.executeStop(address(vault));
        vm.warp(block.timestamp + 4000);
        vm.prank(attacker);
        vault.syncPosition();
        assertFalse(_active());
        vm.prank(cold);
        vault.withdraw(address(usdc), 875e6);
        assertEq(usdc.balanceOf(cold), 875e6);
    }

    function test_syncCannotCloseAnOpenVenuePosition() public {
        _signAndOpenLong();
        vm.prank(attacker);
        vault.syncPosition();
        assertTrue(_active());
    }

    function test_withdrawEthOwnerOnlyAndOwnerDestination() public {
        vm.deal(address(vault), 1 ether);
        vm.prank(attacker);
        vm.expectRevert(NeuroVault.NotOwner.selector);
        vault.withdrawEth(1 ether);
        vm.prank(cold);
        vault.withdrawEth(1 ether);
        assertEq(cold.balance, 1 ether);
    }

    // ------------------------------------------------------------------ ratchet

    function test_initialStopUsesCalmTrail() public {
        _signAndOpenLong();
        assertEq(_stop(), 1960e18); // 2000 * (1 - 2%)
    }

    function test_stopTightensOnNewHigh() public {
        _signAndOpenLong();
        _priceAndPoke(2010e8);
        _priceAndPoke(2020e8);
        assertEq(vault.regime(), 0); // two 0.5% moves stay under neuron 0's threshold
        assertEq(_stop(), (2020e18 * 9800) / 10_000);
    }

    /// A steady climb integrates into a spike: the trail widens, so the stop holds
    /// instead of chasing price. Ratchet still never loosens.
    function test_steadyClimbIntegratesToSpike() public {
        _signAndOpenLong();
        _priceAndPoke(2010e8);
        _priceAndPoke(2020e8);
        uint256 s = _stop();
        _priceAndPoke(2030e8); // third 0.5% move: potential crosses 1% -> spike
        assertEq(vault.regime(), 1);
        assertEq(_stop(), s);
    }

    function test_stopNeverLoosens() public {
        _signAndOpenLong();
        _priceAndPoke(2020e8);
        _priceAndPoke(2040e8);
        uint256 s = _stop();
        _priceAndPoke(2030e8);
        _priceAndPoke(2020e8);
        assertEq(_stop(), s);
    }

    function test_stopHitClosesPositionAndReturnsFunds() public {
        _signAndOpenLong();
        uint256 before = usdc.balanceOf(address(vault));
        _priceAndPoke(1950e8); // below 1960 stop
        assertFalse(_active());
        assertGt(usdc.balanceOf(address(vault)), before); // collateral minus loss came back
    }

    // ------------------------------------------------------------------ spiking layer

    function test_calmMarketDoesNotSpike() public {
        _signAndOpenLong();
        for (uint256 i; i < 10; ++i) {
            _priceAndPoke(int256(2000e8 + (i % 2) * 1e8)); // ~0.05% wiggles
        }
        assertEq(vault.regime(), 0);
    }

    function test_volatilityBurstRaisesRegimeAndWidensTrail() public {
        _signAndOpenLong();
        _priceAndPoke(2030e8); // 1.5% -> neuron 0
        assertEq(vault.regime(), 1);
        _priceAndPoke(2080e8); // 2.5% -> neuron 1
        assertGe(vault.regime(), 2);
        assertGe(vault.currentTrailBps(), 500);
    }

    function test_widerTrailDoesNotLoosenExistingStop() public {
        _signAndOpenLong();
        _priceAndPoke(2010e8);
        uint256 s1 = _stop();
        _priceAndPoke(2080e8); // spike -> wider trail
        assertGe(_stop(), s1);
    }

    function test_regimeDecaysAfterMemoryWindow() public {
        _signAndOpenLong();
        _priceAndPoke(2030e8);
        assertEq(vault.regime(), 1);
        vm.warp(block.timestamp + 2000);
        _priceAndPoke(2030e8);
        assertEq(vault.regime(), 0);
    }

    function test_regimeDecaySettlesNewlyCrossedStopImmediately() public {
        _signAndOpenLong();
        _priceAndPoke(2080e8);
        _priceAndPoke(2000e8);
        assertTrue(_active());
        vm.warp(block.timestamp + 2000);
        _priceAndPoke(2000e8);
        assertEq(vault.regime(), 0);
        assertFalse(_active());
        assertEq(usdc.balanceOf(address(vault)), 1000e6);
    }

    function test_leakDrainsPotential() public {
        _signAndOpenLong();
        _priceAndPoke(2010e8); // 0.5% input, below threshold
        uint256 v = vault.potential(0);
        assertGt(v, 0);
        vm.warp(block.timestamp + 6000);
        _priceAndPoke(2010e8); // zero return
        assertLt(vault.potential(0), v / 5);
    }

    // ------------------------------------------------------------------ anti-spam / oracle

    function test_pokeCooldown() public {
        _signAndOpenLong();
        _priceAndPoke(2010e8);
        vm.expectRevert(NeuroVault.TooSoon.selector);
        vault.poke();
    }

    function test_minMoveSkipsDustUpdates() public {
        _signAndOpenLong();
        uint256 s = _stop();
        _priceAndPoke(2001e8); // 0.05% higher -> candidate improves < 10 bps
        assertEq(_stop(), s);
    }

    function test_staleOracleReverts() public {
        _signAndOpenLong();
        vm.warp(block.timestamp + 4000);
        vm.expectRevert(NeuroVault.StaleOracle.selector);
        vault.poke();
    }

    function test_futureOracleTimestampRevertsCleanly() public {
        _signAndOpenLong();
        vm.mockCall(address(oracle), abi.encodeWithSelector(oracle.latestRoundData.selector),
            abi.encode(uint80(1), int256(2000e8), block.timestamp, block.timestamp + 1, uint80(1)));
        vm.expectRevert(NeuroVault.StaleOracle.selector);
        vault.poke();
    }

    function test_incompleteOracleRoundReverts() public {
        _signAndOpenLong();
        vm.mockCall(address(oracle), abi.encodeWithSelector(oracle.latestRoundData.selector),
            abi.encode(uint80(2), int256(2000e8), block.timestamp, block.timestamp, uint80(1)));
        vm.expectRevert(NeuroVault.StaleOracle.selector);
        vault.poke();
    }

    function test_zeroOraclePriceReverts() public {
        _signAndOpenLong();
        oracle.setPrice(0);
        vm.expectRevert(NeuroVault.BadOraclePrice.selector);
        vault.poke();
    }

    function test_badParamsRevert() public {
        NeuroVault.Params memory p = _params();
        p.trailBps = new uint16[](3); // wrong length
        vm.prank(cold);
        vm.expectRevert(NeuroVault.BadParams.selector);
        vault.signParams(p);

        p = _params();
        p.theta[2] = 0.005e18; // unordered bands
        vm.prank(cold);
        vm.expectRevert(NeuroVault.BadParams.selector);
        vault.signParams(p);
    }

    // ------------------------------------------------------------------ short side

    function test_shortRatchet() public {
        vm.startPrank(cold);
        vault.signParams(_params());
        vault.openPosition(false, 5_000e18, 1_000e6);
        vm.stopPrank();
        assertEq(_stop(), 2040e18);
        _priceAndPoke(1990e8);
        _priceAndPoke(1980e8);
        uint256 s = _stop();
        assertLt(s, 2040e18);
        _priceAndPoke(1995e8);
        assertEq(_stop(), s);
    }

    // ------------------------------------------------------------------ invariant (fuzz)

    /// Random price paths: the long stop is monotonically non-decreasing while open.
    function testFuzz_longStopMonotone(uint256 seed) public {
        _signAndOpenLong();
        int256 p = 2000e8;
        uint256 prev = _stop();
        for (uint256 i; i < 40 && _active(); ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            int256 bps = int256(seed % 401) - 200; // -2%..+2%
            p = (p * (10_000 + bps)) / 10_000;
            _priceAndPoke(p);
            if (_active()) {
                uint256 s = _stop();
                assertGe(s, prev);
                prev = s;
            }
        }
    }

    function testFuzz_shortStopMonotone(uint256 seed) public {
        vm.startPrank(cold);
        vault.signParams(_params());
        vault.openPosition(false, 5_000e18, 1_000e6);
        vm.stopPrank();
        int256 price = 2000e8;
        uint256 prev = _stop();
        for (uint256 i; i < 40 && _active(); ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            price = price * (10_000 + int256(seed % 401) - 200) / 10_000;
            _priceAndPoke(price);
            if (_active()) {
                assertLe(_stop(), prev);
                prev = _stop();
            }
        }
    }
}
