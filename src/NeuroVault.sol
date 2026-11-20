// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";

/// @title NeuroVault
/// @notice Keyless, neuromorphic risk management for cold-wallet perp traders.
///
/// The owner authorizes setup (several transactions in this prototype), signs the
/// spiking-neuron parameters, and opens a position. After that, the vault runs on
/// its own: anyone may call `poke()`, which feeds the latest oracle return into a
/// small layer of leaky integrate-and-fire (LIF) neurons. Spikes select a volatility
/// regime, the regime selects a trailing-stop width, and the stop is ratcheted.
///
/// Safety invariants (enforced in code, not by trust):
///   1. Only the owner can withdraw, and funds can only go to the owner.
///   2. Only the owner can open/close positions or change parameters.
///   3. The stop can only TIGHTEN (move toward price). Nothing can loosen it.
///   4. `poke()` has no discretionary inputs: price comes from the oracle,
///      behaviour comes from owner-signed parameters.
///
/// Venue-specific logic (GMX v2, mock perp, ...) lives in child contracts that
/// implement the `_venue*` hooks.
abstract contract NeuroVault {
    using SafeERC20 for IERC20;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant BPS = 10_000;
    uint256 public constant MAX_NEURONS = 8;
    uint256 public constant MAX_TRAIL_BPS = 5_000; // 50%: hard sanity cap

    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    /// @notice Owner-signed configuration of the spiking layer and the ratchet.
    /// Neurons are ordered by increasing threshold: neuron i firing means the market
    /// has entered volatility band i. trailBps has N+1 entries: index 0 is the calm
    /// regime (no recent spikes), index i+1 is "neuron i is the highest recent spike".
    struct Params {
        uint32[] tau; // leak time constant per neuron, seconds
        uint256[] weight; // input weight per neuron, WAD
        uint256[] theta; // firing threshold per neuron, WAD
        uint16[] trailBps; // trailing distance per regime, bps (len N+1)
        uint32 memoryWindow; // seconds a spike keeps its regime active
        uint16 minMoveBps; // min stop improvement before a venue update (anti-spam)
        uint32 minPokeInterval; // seconds between pokes
        uint32 maxOracleAge; // reject stale oracle data, seconds
    }

    struct Position {
        bool active;
        bool isLong;
        uint256 sizeUsd; // WAD
        uint256 collateral; // collateral token units
        uint256 entryPrice; // WAD
        uint256 extremePrice; // high-water mark (long) / low-water mark (short), WAD
        uint256 stopPrice; // current stop, WAD
    }

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    address public immutable owner;
    IAggregatorV3 public immutable oracle;
    IERC20 public immutable collateralToken;
    uint8 internal immutable oracleDecimals;

    Params internal params;
    bytes32 public paramsHash;

    Position public position;

    uint256[] public potential; // membrane potential per neuron, WAD
    uint256[] public lastSpikeAt; // timestamp of last spike per neuron
    uint256 public lastPrice; // WAD
    uint256 public lastUpdateAt;
    uint256 public lastPokeAt;
    uint256 public regime; // current regime index into trailBps

    // ---------------------------------------------------------------------
    // Events / errors
    // ---------------------------------------------------------------------

    event ParamsSigned(bytes32 indexed paramsHash, uint256 neurons);
    event PositionOpened(bool isLong, uint256 sizeUsd, uint256 collateral, uint256 entryPrice, uint256 stopPrice);
    event PositionClosed(uint256 price, bool byStop);
    event Spike(uint256 indexed neuron, uint256 price, uint256 inputReturn, uint256 timestamp);
    event RegimeChanged(uint256 oldRegime, uint256 newRegime, uint16 trailBps);
    event StopTightened(uint256 oldStop, uint256 newStop, uint256 price, uint256 regime);
    event Poked(address indexed caller, uint256 price, uint256 inputReturn, uint256[] potentials);
    event Withdrawn(address indexed token, uint256 amount);

    error NotOwner();
    error BadParams();
    error PositionActive();
    error NoPosition();
    error TooSoon();
    error StaleOracle();
    error BadOraclePrice();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address owner_, IAggregatorV3 oracle_, IERC20 collateralToken_) {
        require(owner_ != address(0), "zero owner");
        owner = owner_;
        oracle = oracle_;
        collateralToken = collateralToken_;
        oracleDecimals = oracle_.decimals();
        require(oracleDecimals <= 18, "oracle decimals");
    }

    // ---------------------------------------------------------------------
    // Owner (cold wallet) actions
    // ---------------------------------------------------------------------

    /// @notice Sign the spiking layer + ratchet configuration. Resets neuron state.
    function signParams(Params calldata p) external onlyOwner {
        _validate(p);
        params = p;
        paramsHash = keccak256(abi.encode(p));

        uint256 n = p.tau.length;
        delete potential;
        delete lastSpikeAt;
        for (uint256 i; i < n; ++i) {
            potential.push(0);
            lastSpikeAt.push(0);
        }
        regime = 0;
        lastPrice = 0;
        lastUpdateAt = 0;
        emit ParamsSigned(paramsHash, n);
    }

    /// @notice Open a position on the venue. Initial stop uses the current regime's trail.
    function openPosition(bool isLong, uint256 sizeUsd, uint256 collateral) external payable onlyOwner {
        if (position.active) revert PositionActive();
        if (params.trailBps.length == 0) revert BadParams();

        uint256 price = _readOracle();
        uint16 trail = params.trailBps[regime];
        uint256 stop = isLong ? (price * (BPS - trail)) / BPS : (price * (BPS + trail)) / BPS;

        position = Position({
            active: true,
            isLong: isLong,
            sizeUsd: sizeUsd,
            collateral: collateral,
            entryPrice: price,
            extremePrice: price,
            stopPrice: stop
        });

        if (lastPrice == 0) {
            lastPrice = price;
            lastUpdateAt = block.timestamp;
        }

        _venueOpen(isLong, sizeUsd, collateral, stop);
        emit PositionOpened(isLong, sizeUsd, collateral, price, stop);
    }

    /// @notice Owner closes the position manually.
    function closePosition() external payable onlyOwner {
        if (!position.active) revert NoPosition();
        position.active = false;
        _venueClose();
        emit PositionClosed(_readOracle(), false);
    }

    /// @notice Withdraw ERC20 funds. Destination is hard-coded to the owner.
    function withdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner, amount);
        emit Withdrawn(token, amount);
    }

    /// @notice Withdraw native ETH (execution-fee float). Destination is the owner.
    function withdrawEth(uint256 amount) external onlyOwner {
        (bool ok,) = owner.call{value: amount}("");
        require(ok, "eth transfer failed");
        emit Withdrawn(address(0), amount);
    }

    receive() external payable {}

    // ---------------------------------------------------------------------
    // Permissionless automation
    // ---------------------------------------------------------------------

    /// @notice Advance the spiking layer with the latest oracle price and ratchet the stop.
    /// Callable by anyone. Call timing affects sampling, but cannot redirect funds or loosen stops.
    function poke() public virtual {
        if (params.tau.length == 0) revert BadParams();
        if (lastPokeAt != 0 && block.timestamp < lastPokeAt + params.minPokeInterval) revert TooSoon();
        lastPokeAt = block.timestamp;

        uint256 price = _readOracle();
        uint256 x = _step(price);
        emit Poked(msg.sender, price, x, potential);

        if (position.active) _ratchet(price);
    }

    // ---------------------------------------------------------------------
    // Spiking layer
    // ---------------------------------------------------------------------

    /// @dev One LIF update. Input is the absolute return since the last update.
    /// Leak uses the rational decay v * tau / (tau + dt): monotone, cheap, and
    /// correct for irregular sampling (pokes are not evenly spaced).
    function _step(uint256 price) internal returns (uint256 x) {
        if (lastPrice == 0) {
            lastPrice = price;
            lastUpdateAt = block.timestamp;
            return 0;
        }

        uint256 dt = block.timestamp - lastUpdateAt;
        x = price > lastPrice ? ((price - lastPrice) * WAD) / lastPrice : ((lastPrice - price) * WAD) / lastPrice;

        uint256 n = params.tau.length;
        uint256 newRegime = 0;
        for (uint256 i; i < n; ++i) {
            uint256 tau = params.tau[i];
            uint256 v = (potential[i] * tau) / (tau + dt);
            v += (params.weight[i] * x) / WAD;
            if (v >= params.theta[i]) {
                v = 0; // reset after firing
                lastSpikeAt[i] = block.timestamp;
                emit Spike(i, price, x, block.timestamp);
            }
            potential[i] = v;
            if (lastSpikeAt[i] != 0 && block.timestamp - lastSpikeAt[i] <= params.memoryWindow) {
                newRegime = i + 1; // highest recently-firing band wins
            }
        }

        if (newRegime != regime) {
            emit RegimeChanged(regime, newRegime, params.trailBps[newRegime]);
            regime = newRegime;
        }

        lastPrice = price;
        lastUpdateAt = block.timestamp;
    }

    // ---------------------------------------------------------------------
    // Ratchet
    // ---------------------------------------------------------------------

    function _ratchet(uint256 price) internal {
        Position storage pos = position;

        // Stop already crossed: let the venue settle it.
        if (pos.isLong ? price <= pos.stopPrice : price >= pos.stopPrice) {
            pos.active = false;
            _onStopHit(price);
            emit PositionClosed(price, true);
            return;
        }

        uint16 trail = params.trailBps[regime];
        uint256 candidate;
        if (pos.isLong) {
            if (price > pos.extremePrice) pos.extremePrice = price;
            candidate = (pos.extremePrice * (BPS - trail)) / BPS;
            if (candidate <= pos.stopPrice) return; // never loosen
            if ((candidate - pos.stopPrice) * BPS < uint256(params.minMoveBps) * pos.stopPrice) return;
        } else {
            if (price < pos.extremePrice) pos.extremePrice = price;
            candidate = (pos.extremePrice * (BPS + trail)) / BPS;
            if (candidate >= pos.stopPrice) return; // never loosen
            if ((pos.stopPrice - candidate) * BPS < uint256(params.minMoveBps) * pos.stopPrice) return;
        }

        uint256 old = pos.stopPrice;
        pos.stopPrice = candidate;
        _venueUpdateStop(candidate);
        emit StopTightened(old, candidate, price, regime);
        // A decaying regime can tighten against an old extreme past the current
        // price. Settle now instead of leaving an already-crossed mock stop open.
        if (pos.isLong ? price <= candidate : price >= candidate) {
            pos.active = false;
            _onStopHit(price);
            emit PositionClosed(price, true);
        }
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _readOracle() internal view returns (uint256) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = oracle.latestRoundData();
        if (answer <= 0) revert BadOraclePrice();
        if (updatedAt == 0 || updatedAt > block.timestamp || answeredInRound < roundId) revert StaleOracle();
        if (params.maxOracleAge != 0 && block.timestamp - updatedAt > params.maxOracleAge) revert StaleOracle();
        return uint256(answer) * (10 ** (18 - oracleDecimals));
    }

    function _validate(Params calldata p) internal pure {
        uint256 n = p.tau.length;
        if (n == 0 || n > MAX_NEURONS) revert BadParams();
        if (p.weight.length != n || p.theta.length != n || p.trailBps.length != n + 1) revert BadParams();
        for (uint256 i; i < n; ++i) {
            if (p.tau[i] == 0 || p.theta[i] == 0) revert BadParams();
            if (i > 0 && p.theta[i] < p.theta[i - 1]) revert BadParams(); // ordered bands
        }
        for (uint256 i; i <= n; ++i) {
            if (p.trailBps[i] == 0 || p.trailBps[i] > MAX_TRAIL_BPS) revert BadParams();
        }
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function getParams() external view returns (Params memory) {
        return params;
    }

    function getPotentials() external view returns (uint256[] memory) {
        return potential;
    }

    function getLastSpikes() external view returns (uint256[] memory) {
        return lastSpikeAt;
    }

    function currentTrailBps() external view returns (uint16) {
        return params.trailBps.length == 0 ? 0 : params.trailBps[regime];
    }

    // ---------------------------------------------------------------------
    // Venue hooks
    // ---------------------------------------------------------------------

    function _venueOpen(bool isLong, uint256 sizeUsd, uint256 collateral, uint256 stopPrice) internal virtual;

    function _venueUpdateStop(uint256 stopPrice) internal virtual;

    function _venueClose() internal virtual;

    /// @dev Called when poke() observes the stop crossed. Venues with native
    /// keeper-executed stops (GMX) can leave this empty.
    function _onStopHit(uint256 price) internal virtual;
}
