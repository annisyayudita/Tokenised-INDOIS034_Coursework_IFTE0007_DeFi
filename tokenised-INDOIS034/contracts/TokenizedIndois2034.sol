// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TokenizedIndois2034
 * @notice Coursework proof-of-concept:
 *         a fungible token representing fractional ownership
 *         in an off-chain holding of Indonesia's 5.20% Global Sukuk (Sharia/Islamic Bond) due 2 July 2034 (INDOIS034).
 *
 *         DEMO NOTE:
 *         - The real underlying sukuk pays in USD and distributes semi-annually.
 *         - For Sepolia testing, this contract accepts ETH deposits as MOCK profit/redemption funding.
 *         - This is a demonstration of on-chain distribution and redemption mechanics of INDOIS34.
 */
contract TokenizedIndois2034 is ERC20, AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 private constant MAGNITUDE = 2**128;

    // Product metadata
    string public constant UNDERLYING_NAME =
        "Indonesia Global Sukuk 5.20% due 2 July 2034";
    string public constant UNDERLYING_ISIN =
        "USY68613AB73";
    uint256 public constant COUPON_RATE_BPS = 520; // 5.20%
    uint256 public constant FACE_VALUE_PER_TOKEN_USD18 = 100e18; // 1 token = USD 100 face value exposure
    uint256 public constant COUPON_INTERVAL_SECONDS = 182 days; // simplified semi-annual clock

    uint256 public immutable maturityTimestamp;

    // Whitelist / compliance
    mapping(address => bool) public isWhitelisted;

    // Profit distribution state (ETH used as mock payout on Sepolia)
    uint256 public magnifiedProfitPerShare;
    mapping(address => int256) private magnifiedProfitCorrections;
    mapping(address => uint256) public withdrawnProfits;

    struct DistributionRound {
        uint256 amountWei;
        uint256 timestamp;
        string memo;
    }

    uint256 public distributionRoundCount;
    mapping(uint256 => DistributionRound) private _distributionRounds;

    // Accrual display only
    uint256 public lastCouponTimestamp;

    // Redemption state (ETH used as mock principal payout on Sepolia)
    uint256 public redemptionRateWeiPerToken;

    event WhitelistUpdated(address indexed account, bool approved);
    event TokensMinted(address indexed to, uint256 amount);
    event DistributionDeposited(
        uint256 indexed roundId,
        uint256 amountWei,
        string memo
    );
    event ProfitClaimed(address indexed account, uint256 amountWei);
    event RedemptionRateSet(uint256 weiPerToken);
    event RedemptionPoolFunded(address indexed from, uint256 amountWei);
    event Redeemed(
        address indexed account,
        uint256 tokenAmount,
        uint256 payoutWei
    );
    event CouponClockUpdated(uint256 newTimestamp);

    error NotWhitelisted(address account);
    error InvalidAmount();
    error RedemptionNotAvailable();
    error TransfersPaused();

    constructor(uint256 _maturityTimestamp, address admin)
        ERC20("Tokenized INDOis 2034 Certificate", "tINDOIS34")
    {
        require(admin != address(0), "admin is zero");
        require(_maturityTimestamp > block.timestamp, "maturity must be future");

        maturityTimestamp = _maturityTimestamp;
        lastCouponTimestamp = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DISTRIBUTOR_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        isWhitelisted[admin] = true;
        emit WhitelistUpdated(admin, true);
    }

    // ---------------------------------
    // ERC-20 display settings
    // ---------------------------------

    /// @notice 0 decimals to make demo/testing easier:
    ///         1 token = 1 whole claim unit = USD 100 face value exposure.
    function decimals() public pure override returns (uint8) {
        return 0;
    }

    // ---------------------------------
    // Admin / compliance
    // ---------------------------------

    function setWhitelist(address account, bool approved)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (account == address(0)) revert InvalidAmount();
        isWhitelisted[account] = approved;
        emit WhitelistUpdated(account, approved);
    }

    function batchSetWhitelist(address[] calldata accounts, bool approved)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 len = accounts.length;
        for (uint256 i = 0; i < len; i++) {
            address account = accounts[i];
            if (account == address(0)) continue;
            isWhitelisted[account] = approved;
            emit WhitelistUpdated(account, approved);
        }
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function mint(address to, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (!isWhitelisted[to]) revert NotWhitelisted(to);
        if (amount == 0) revert InvalidAmount();

        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    function setCouponClock(uint256 newTimestamp)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newTimestamp <= block.timestamp, "future timestamp not allowed");
        lastCouponTimestamp = newTimestamp;
        emit CouponClockUpdated(newTimestamp);
    }

    // ---------------------------------
    // Profit distribution
    // ---------------------------------

    /**
     * @notice Deposit profit in ETH for token holders.
     * @dev In the real product, profit would come from the off-chain sukuk distribution.
     *      Here, ETH is only used to demonstrate on-chain payout mechanics.
     */
    function depositDistribution(string calldata memo)
        external
        payable
        onlyRole(DISTRIBUTOR_ROLE)
        whenNotPaused
    {
        if (msg.value == 0) revert InvalidAmount();
        uint256 supply = totalSupply();
        require(supply > 0, "no tokens outstanding");

        magnifiedProfitPerShare += (msg.value * MAGNITUDE) / supply;

        distributionRoundCount += 1;
        _distributionRounds[distributionRoundCount] = DistributionRound({
            amountWei: msg.value,
            timestamp: block.timestamp,
            memo: memo
        });

        // reset accrual clock after a coupon/profit event
        lastCouponTimestamp = block.timestamp;

        emit DistributionDeposited(
            distributionRoundCount,
            msg.value,
            memo
        );
    }

    function getDistributionRound(uint256 roundId)
        external
        view
        returns (
            uint256 amountWei,
            uint256 timestamp,
            string memory memo
        )
    {
        DistributionRound storage r = _distributionRounds[roundId];
        return (r.amountWei, r.timestamp, r.memo);
    }

    function claimDistribution() external nonReentrant whenNotPaused {
        uint256 amount = _withdrawProfitIfAny(msg.sender);
        require(amount > 0, "nothing to claim");
    }

    function withdrawableProfitOf(address account) public view returns (uint256) {
        uint256 accumulative = accumulativeProfitOf(account);
        uint256 alreadyWithdrawn = withdrawnProfits[account];
        if (accumulative <= alreadyWithdrawn) {
            return 0;
        }
        return accumulative - alreadyWithdrawn;
    }

    function accumulativeProfitOf(address account)
        public
        view
        returns (uint256)
    {
        int256 magnified = int256(magnifiedProfitPerShare * balanceOf(account))
            + magnifiedProfitCorrections[account];

        if (magnified < 0) {
            return 0;
        }

        return uint256(magnified) / MAGNITUDE;
    }

    function _withdrawProfitIfAny(address account)
        internal
        returns (uint256)
    {
        uint256 withdrawable = withdrawableProfitOf(account);
        if (withdrawable == 0) {
            return 0;
        }

        withdrawnProfits[account] += withdrawable;

        (bool success, ) = payable(account).call{value: withdrawable}("");
        require(success, "ETH transfer failed");

        emit ProfitClaimed(account, withdrawable);
        return withdrawable;
    }

    // ---------------------------------
    // Informational accrual display only
    // ---------------------------------

    /**
     * @notice Informational accrued profit per 1 token since the last coupon clock reset.
     * @dev Returns an 18-decimal USD figure.
     *      Example: 1.25e18 means approx USD 1.25 accrued per token.
     */
    function accruedProfitPerTokenUSD18() external view returns (uint256) {
        uint256 elapsed = block.timestamp > lastCouponTimestamp
            ? block.timestamp - lastCouponTimestamp
            : 0;

        if (elapsed > COUPON_INTERVAL_SECONDS) {
            elapsed = COUPON_INTERVAL_SECONDS;
        }

        uint256 annualProfitPerTokenUSD18 =
            (FACE_VALUE_PER_TOKEN_USD18 * COUPON_RATE_BPS) / BPS_DENOMINATOR;

        return (annualProfitPerTokenUSD18 * elapsed) / 365 days;
    }

    /**
     * @notice Approximate expected semi-annual profit per token in 18-decimal USD terms.
     */
    function expectedSemiAnnualProfitPerTokenUSD18()
        external
        pure
        returns (uint256)
    {
        uint256 annualProfitPerTokenUSD18 =
            (FACE_VALUE_PER_TOKEN_USD18 * COUPON_RATE_BPS) / BPS_DENOMINATOR;

        return annualProfitPerTokenUSD18 / 2;
    }

    // ---------------------------------
    // Redemption
    // ---------------------------------

    /**
     * @notice Set the mock ETH redemption amount for 1 token.
     * @dev Redemption would reflect off-chain principal settlement.
     */
    function setRedemptionRateWeiPerToken(uint256 weiPerToken)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (weiPerToken == 0) revert InvalidAmount();
        redemptionRateWeiPerToken = weiPerToken;
        emit RedemptionRateSet(weiPerToken);
    }

    /**
     * @notice Fund the contract with ETH for mock principal redemption.
     */
    function fundRedemptionPool()
        external
        payable
        onlyRole(DISTRIBUTOR_ROLE)
    {
        if (msg.value == 0) revert InvalidAmount();
        emit RedemptionPoolFunded(msg.sender, msg.value);
    }

    /**
     * @notice Redeem tokens after maturity for mock ETH principal payout.
     * @dev Automatically claims any unclaimed profit first.
     */
    function redeemAtMaturity(uint256 tokenAmount)
        external
        nonReentrant
        whenNotPaused
    {
        if (block.timestamp < maturityTimestamp) revert RedemptionNotAvailable();
        if (redemptionRateWeiPerToken == 0) revert RedemptionNotAvailable();
        if (tokenAmount == 0) revert InvalidAmount();
        require(balanceOf(msg.sender) >= tokenAmount, "insufficient tokens");

        // claim any pending profit first
        _withdrawProfitIfAny(msg.sender);

        uint256 payoutWei = tokenAmount * redemptionRateWeiPerToken;
        require(address(this).balance >= payoutWei, "insufficient redemption pool");

        _burn(msg.sender, tokenAmount);

        (bool success, ) = payable(msg.sender).call{value: payoutWei}("");
        require(success, "ETH transfer failed");

        emit Redeemed(msg.sender, tokenAmount, payoutWei);
    }

    // ---------------------------------
    // Transfer restrictions + coupon correction logic
    // ---------------------------------

    function _update(address from, address to, uint256 value)
        internal
        override
    {
        if (from != address(0) && to != address(0) && paused()) {
            revert TransfersPaused();
        }

        if (from != address(0) && !isWhitelisted[from]) {
            revert NotWhitelisted(from);
        }

        if (to != address(0) && !isWhitelisted[to]) {
            revert NotWhitelisted(to);
        }

        super._update(from, to, value);

        int256 magCorrection = int256(magnifiedProfitPerShare * value);

        if (from == address(0)) {
            // mint
            magnifiedProfitCorrections[to] -= magCorrection;
        } else if (to == address(0)) {
            // burn
            magnifiedProfitCorrections[from] += magCorrection;
        } else {
            // transfer
            magnifiedProfitCorrections[from] += magCorrection;
            magnifiedProfitCorrections[to] -= magCorrection;
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
