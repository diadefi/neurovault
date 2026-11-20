// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal GMX v2 (Synthetics) ExchangeRouter interface, matching the
/// Arbitrum Sepolia deployment ABI (gmx-io/gmx-synthetics, deployments/arbitrumSepolia).
library GmxOrder {
    // Order.OrderType
    uint8 internal constant MARKET_INCREASE = 2;
    uint8 internal constant MARKET_DECREASE = 4;
    uint8 internal constant STOP_LOSS_DECREASE = 6;
    // Order.DecreasePositionSwapType
    uint8 internal constant NO_SWAP = 0;

    struct Addresses {
        address receiver;
        address cancellationReceiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address initialCollateralToken;
        address[] swapPath;
    }

    struct Numbers {
        uint256 sizeDeltaUsd;
        uint256 initialCollateralDeltaAmount;
        uint256 triggerPrice;
        uint256 acceptablePrice;
        uint256 executionFee;
        uint256 callbackGasLimit;
        uint256 minOutputAmount;
        uint256 validFromTime;
    }

    struct CreateOrderParams {
        Addresses addresses;
        Numbers numbers;
        uint8 orderType;
        uint8 decreasePositionSwapType;
        bool isLong;
        bool shouldUnwrapNativeToken;
        bool autoCancel;
        bytes32 referralCode;
        bytes32[] dataList;
    }
}

interface IGmxExchangeRouter {
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);

    function sendWnt(address receiver, uint256 amount) external payable;

    function sendTokens(address token, address receiver, uint256 amount) external payable;

    function createOrder(GmxOrder.CreateOrderParams calldata params) external payable returns (bytes32);

    function updateOrder(
        bytes32 key,
        uint256 sizeDeltaUsd,
        uint256 acceptablePrice,
        uint256 triggerPrice,
        uint256 minOutputAmount,
        uint256 validFromTime,
        bool autoCancel
    ) external payable;

    function cancelOrder(bytes32 key) external payable;
}
