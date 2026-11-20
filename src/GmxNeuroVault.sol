// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {NeuroVault} from "./NeuroVault.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {IGmxExchangeRouter, GmxOrder} from "./interfaces/IGmxExchangeRouter.sol";

/// @title GmxNeuroVault
/// @notice NeuroVault wired to GMX v2. The vault contract is the GMX account: it owns
/// the position and its StopLossDecrease order. GMX keepers execute the stop; the
/// vault's spiking layer only ever tightens that order's trigger price.
///
/// GMX units: USD values have 30 decimals; a token price is USD-per-unit scaled so
/// that price * amount = 30-decimal USD, i.e. usdPerToken * 10^(30 - tokenDecimals).
contract GmxNeuroVault is NeuroVault {
    using SafeERC20 for IERC20;

    IGmxExchangeRouter public immutable exchangeRouter;
    address public immutable gmxRouter; // token approvals go to Router (plugin transfers)
    address public immutable orderVault;
    address public immutable market; // GM market, e.g. ETH/USD [WETH-USDC.SG]
    uint8 public immutable indexTokenDecimals;

    bytes32 public stopOrderKey;
    bytes32 public increaseOrderKey;

    uint256 public executionFee; // ETH per created order, paid from the vault's ETH float
    uint256 public updateTopUp; // optional ETH top-up sent with each stop update
    uint16 public slippageBps = 100; // acceptable-price slippage for market orders

    event GmxOrderCreated(bytes32 indexed key, uint8 orderType, uint256 triggerPrice);
    event GmxStopUpdated(bytes32 indexed key, uint256 triggerPrice);

    constructor(
        address owner_,
        IAggregatorV3 oracle_,
        IERC20 collateral_,
        IGmxExchangeRouter exchangeRouter_,
        address gmxRouter_,
        address orderVault_,
        address market_,
        uint8 indexTokenDecimals_
    ) NeuroVault(owner_, oracle_, collateral_) {
        exchangeRouter = exchangeRouter_;
        gmxRouter = gmxRouter_;
        orderVault = orderVault_;
        market = market_;
        indexTokenDecimals = indexTokenDecimals_;
    }

    // ------------------------------------------------------------------ owner config

    function setGmxFees(uint256 executionFee_, uint256 updateTopUp_, uint16 slippageBps_) external onlyOwner {
        require(slippageBps_ <= 1_000, "slippage");
        executionFee = executionFee_;
        updateTopUp = updateTopUp_;
        slippageBps = slippageBps_;
    }

    // ------------------------------------------------------------------ unit helpers

    function _usd30(uint256 wadUsd) internal pure returns (uint256) {
        return wadUsd * 1e12;
    }

    /// @dev WAD USD-per-token -> GMX 30-decimal per-unit price.
    function _gmxPrice(uint256 wadPrice) internal view returns (uint256) {
        return (wadPrice * 1e12) / (10 ** indexTokenDecimals);
    }

    function _baseAddresses() internal view returns (GmxOrder.Addresses memory a) {
        a.receiver = address(this); // proceeds return to the vault, never elsewhere
        a.cancellationReceiver = address(this);
        a.market = market;
        a.initialCollateralToken = address(collateralToken);
        a.swapPath = new address[](0);
    }

    function _order(uint8 orderType, bool isLong, uint256 sizeUsd, uint256 collateral, uint256 trigger, uint256 acceptable)
        internal
        view
        returns (GmxOrder.CreateOrderParams memory p)
    {
        p.addresses = _baseAddresses();
        p.numbers.sizeDeltaUsd = _usd30(sizeUsd);
        p.numbers.initialCollateralDeltaAmount = collateral;
        p.numbers.triggerPrice = trigger;
        p.numbers.acceptablePrice = acceptable;
        p.numbers.executionFee = executionFee;
        p.orderType = orderType;
        p.decreasePositionSwapType = GmxOrder.NO_SWAP;
        p.isLong = isLong;
        p.autoCancel = orderType == GmxOrder.STOP_LOSS_DECREASE;
        p.dataList = new bytes32[](0);
    }

    function _submit(bytes[] memory calls, uint256 value) internal returns (bytes32 key) {
        bytes[] memory results = exchangeRouter.multicall{value: value}(calls);
        key = abi.decode(results[results.length - 1], (bytes32));
    }

    // ------------------------------------------------------------------ venue hooks

    function _venueOpen(bool isLong, uint256 sizeUsd, uint256 collateral, uint256 stopPrice) internal override {
        uint256 px = _readOracle();
        uint256 slip = slippageBps;

        // 1) Market increase: send fee + collateral to the OrderVault, then createOrder.
        collateralToken.forceApprove(gmxRouter, collateral);
        uint256 incAcceptable = isLong ? _gmxPrice((px * (BPS + slip)) / BPS) : _gmxPrice((px * (BPS - slip)) / BPS);
        bytes[] memory inc = new bytes[](3);
        inc[0] = abi.encodeCall(IGmxExchangeRouter.sendWnt, (orderVault, executionFee));
        inc[1] = abi.encodeCall(IGmxExchangeRouter.sendTokens, (address(collateralToken), orderVault, collateral));
        inc[2] = abi.encodeCall(
            IGmxExchangeRouter.createOrder,
            (_order(GmxOrder.MARKET_INCREASE, isLong, sizeUsd, collateral, 0, incAcceptable))
        );
        increaseOrderKey = _submit(inc, executionFee);
        emit GmxOrderCreated(increaseOrderKey, GmxOrder.MARKET_INCREASE, 0);

        // 2) Stop-loss decrease for the full size. Keepers execute it when price crosses.
        //    Acceptable price is unbounded so the stop is never skipped on slippage.
        uint256 trigger = _gmxPrice(stopPrice);
        uint256 slAcceptable = isLong ? 0 : type(uint256).max;
        bytes[] memory sl = new bytes[](2);
        sl[0] = abi.encodeCall(IGmxExchangeRouter.sendWnt, (orderVault, executionFee));
        sl[1] = abi.encodeCall(
            IGmxExchangeRouter.createOrder,
            (_order(GmxOrder.STOP_LOSS_DECREASE, isLong, sizeUsd, 0, trigger, slAcceptable))
        );
        stopOrderKey = _submit(sl, executionFee);
        emit GmxOrderCreated(stopOrderKey, GmxOrder.STOP_LOSS_DECREASE, trigger);
    }

    function _venueUpdateStop(uint256 stopPrice) internal override {
        Position memory pos = position;
        uint256 trigger = _gmxPrice(stopPrice);
        uint256 slAcceptable = pos.isLong ? 0 : type(uint256).max;

        bytes[] memory calls = new bytes[](updateTopUp > 0 ? 2 : 1);
        uint256 i;
        if (updateTopUp > 0) calls[i++] = abi.encodeCall(IGmxExchangeRouter.sendWnt, (orderVault, updateTopUp));
        calls[i] = abi.encodeCall(
            IGmxExchangeRouter.updateOrder, (stopOrderKey, _usd30(pos.sizeUsd), slAcceptable, trigger, 0, 0, true)
        );
        exchangeRouter.multicall{value: updateTopUp}(calls);
        emit GmxStopUpdated(stopOrderKey, trigger);
    }

    function _venueClose() internal override {
        Position memory pos = position;
        uint256 px = _readOracle();
        uint256 slip = slippageBps;
        uint256 acceptable = pos.isLong ? _gmxPrice((px * (BPS - slip)) / BPS) : _gmxPrice((px * (BPS + slip)) / BPS);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(IGmxExchangeRouter.sendWnt, (orderVault, executionFee));
        calls[1] = abi.encodeCall(
            IGmxExchangeRouter.createOrder,
            (_order(GmxOrder.MARKET_DECREASE, pos.isLong, pos.sizeUsd, 0, 0, acceptable))
        );
        bytes32 key = _submit(calls, executionFee);
        emit GmxOrderCreated(key, GmxOrder.MARKET_DECREASE, 0);
        // The stop order has autoCancel=true: GMX cancels it once the position is closed.
    }

    /// @dev GMX keepers execute the StopLossDecrease order natively; nothing to do here.
    function _onStopHit(uint256) internal override {}
}
