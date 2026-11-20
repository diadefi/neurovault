// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {NeuroVault} from "./NeuroVault.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {MockPerp} from "./mocks/Mocks.sol";

/// @notice NeuroVault wired to the MockPerp venue.
contract MockPerpNeuroVault is NeuroVault {
    using SafeERC20 for IERC20;

    MockPerp public immutable perp;

    constructor(address owner_, IAggregatorV3 oracle_, IERC20 usdc_, MockPerp perp_)
        NeuroVault(owner_, oracle_, usdc_)
    {
        perp = perp_;
    }

    /// @notice Reconcile a stop settled directly by a venue keeper, even after price rebounds.
    /// No new price read is needed: the venue records the actual settlement price.
    function syncPosition() public {
        (bool venueOpen,,,,,) = perp.positions(address(this));
        if (position.active && !venueOpen) {
            position.active = false;
            emit PositionClosed(perp.lastExitPrice(address(this)), true);
        }
    }

    function poke() public override {
        syncPosition();
        super.poke();
    }

    function _venueOpen(bool isLong, uint256 sizeUsd, uint256 collateral, uint256 stopPrice) internal override {
        collateralToken.forceApprove(address(perp), collateral);
        perp.open(isLong, sizeUsd, collateral, stopPrice);
    }

    function _venueUpdateStop(uint256 stopPrice) internal override {
        perp.setStop(stopPrice);
    }

    function _venueClose() internal override {
        perp.close();
    }

    function _onStopHit(uint256) internal override {
        perp.close();
    }
}
