// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAggregatorV3} from "../interfaces/IAggregatorV3.sol";

/// @notice Test USDC (6 decimals), freely mintable. Testnet / demo only.
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Settable Chainlink-style price feed (8 decimals). Demo only.
contract MockOracle is IAggregatorV3 {
    int256 public answer;
    uint256 public updatedAt;
    uint80 public roundId;
    address public immutable admin;

    constructor(int256 initial) {
        admin = msg.sender;
        _set(initial);
    }

    function setPrice(int256 p) external {
        require(msg.sender == admin, "admin");
        _set(p);
    }

    function _set(int256 p) internal {
        answer = p;
        updatedAt = block.timestamp;
        roundId++;
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, updatedAt, updatedAt, roundId);
    }
}

/// @notice Minimal perp venue with oracle-settled PnL and keeper-executable stops.
/// Fallback venue for when a production perp testnet is unavailable.
contract MockPerp {
    using SafeERC20 for IERC20;

    struct Pos {
        bool open;
        bool isLong;
        uint256 sizeUsd; // WAD
        uint256 collateral; // token units (6dp)
        uint256 entry; // WAD
        uint256 stop; // WAD
    }

    IERC20 public immutable usdc;
    IAggregatorV3 public immutable oracle;
    mapping(address => Pos) public positions;
    mapping(address => uint256) public lastExitPrice;

    event Opened(address indexed account, bool isLong, uint256 sizeUsd, uint256 collateral, uint256 entry, uint256 stop);
    event StopUpdated(address indexed account, uint256 stop);
    event Closed(address indexed account, uint256 price, int256 pnlUsd, uint256 payout, bool byKeeper);

    constructor(IERC20 usdc_, IAggregatorV3 oracle_) {
        usdc = usdc_;
        oracle = oracle_;
    }

    function price() public view returns (uint256) {
        (, int256 a,,,) = oracle.latestRoundData();
        require(a > 0, "bad price");
        return uint256(a) * 1e10; // 8dp -> 18dp
    }

    function open(bool isLong, uint256 sizeUsd, uint256 collateral, uint256 stop) external {
        require(!positions[msg.sender].open, "open");
        usdc.safeTransferFrom(msg.sender, address(this), collateral);
        uint256 p = price();
        positions[msg.sender] = Pos(true, isLong, sizeUsd, collateral, p, stop);
        emit Opened(msg.sender, isLong, sizeUsd, collateral, p, stop);
    }

    function setStop(uint256 stop) external {
        require(positions[msg.sender].open, "none");
        positions[msg.sender].stop = stop;
        emit StopUpdated(msg.sender, stop);
    }

    function close() external {
        _settle(msg.sender, false);
    }

    /// @notice Keeper path: anyone may execute a crossed stop.
    function executeStop(address account) external {
        Pos memory p = positions[account];
        require(p.open, "none");
        uint256 px = price();
        require(p.isLong ? px <= p.stop : px >= p.stop, "not crossed");
        _settle(account, true);
    }

    function pnl(address account) public view returns (int256) {
        Pos memory p = positions[account];
        if (!p.open) return 0;
        int256 px = int256(price());
        int256 e = int256(p.entry);
        int256 d = p.isLong ? px - e : e - px;
        return (int256(p.sizeUsd) * d) / e;
    }

    function _settle(address account, bool byKeeper) internal {
        Pos memory p = positions[account];
        require(p.open, "none");
        int256 pnlUsd = pnl(account);
        int256 payout = int256(p.collateral) + pnlUsd / 1e12; // WAD USD -> 6dp
        if (payout < 0) payout = 0;
        lastExitPrice[account] = price();
        delete positions[account];
        if (payout > 0) usdc.safeTransfer(account, uint256(payout));
        emit Closed(account, price(), pnlUsd, uint256(payout), byKeeper);
    }
}
