// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title BaseStrikerPaymentRouter — minimal USDC router for in-game purchases.
///
/// Players approve(this, amount) USDC once, then call `payForItem(itemSku, qty)`.
/// The contract pulls USDC from the buyer, forwards the full amount to the
/// configured treasury, and emits `ItemPaid(buyer, sku, qty, amount)` so any
/// on-chain indexer (Basescan / Talent Protocol / The Graph) can attribute the
/// purchase to the buyer + the item.
///
/// Why this exists:
///   - direct `USDC.transfer(treasury)` works but produces no semantic event.
///     Indexers only see "Buyer sent X USDC to Treasury" — no item context.
///   - This router emits a typed event with the SKU so leaderboards and
///     anti-cheat can prove which on-chain purchase corresponds to which
///     in-game boost.
///   - Side-benefit: this is a deployed verified contract on Base, which counts
///     toward Talent Protocol's "Base contracts deployed" Builder Score metric.
///
/// USDC on Base mainnet: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 (6 decimals).
/// Treasury (deploy parameter): the wallet that receives shop revenue.
interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
}

contract BaseStrikerPaymentRouter {
    /// USDC on Base mainnet. Immutable — set once at construction.
    IERC20 public immutable usdc;

    /// Owner / governor. Can rotate the treasury and pause new payments.
    address public owner;

    /// Where USDC flows on every `payForItem` call.
    address public treasury;

    /// Kill-switch — when true, `payForItem` reverts. Owner-controlled.
    bool public paused;

    /// Running total of USDC routed since deploy (informational).
    uint256 public totalRouted;

    /// One event per purchase. `sku` is an opaque 32-byte shop item ID
    /// (the frontend / backend agree on the mapping). `qty` is the number
    /// of items bought in this call; `amount` is the USDC base units actually
    /// pulled. Buyer is `msg.sender`.
    event ItemPaid(address indexed buyer, bytes32 indexed sku, uint32 qty, uint256 amount, uint256 timestamp);

    event TreasuryUpdated(address indexed previous, address indexed next);
    event Paused(bool paused);
    event OwnerTransferred(address indexed previous, address indexed next);

    error NotOwner();
    error ZeroAddress();
    error PaymentPaused();
    error TransferFailed();
    error ZeroAmount();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @param _usdc     The USDC token (Base mainnet: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913).
    /// @param _treasury The wallet that receives every shop USDC payment.
    constructor(address _usdc, address _treasury) {
        if (_usdc == address(0) || _treasury == address(0)) revert ZeroAddress();
        usdc = IERC20(_usdc);
        treasury = _treasury;
        owner = msg.sender;
        emit TreasuryUpdated(address(0), _treasury);
        emit OwnerTransferred(address(0), msg.sender);
    }

    /// Buyer flow:
    ///   1. `USDC.approve(router, amount)` (one-time per allowance)
    ///   2. `router.payForItem(skuHash, qty, amount)`
    ///
    /// `amount` is the FULL USDC base-unit amount (6-decimal). The router
    /// pulls it from the buyer and forwards 100% to the treasury — no fees
    /// retained here.
    function payForItem(bytes32 sku, uint32 qty, uint256 amount) external {
        if (paused) revert PaymentPaused();
        if (amount == 0) revert ZeroAmount();
        bool ok = usdc.transferFrom(msg.sender, treasury, amount);
        if (!ok) revert TransferFailed();
        totalRouted += amount;
        emit ItemPaid(msg.sender, sku, qty, amount, block.timestamp);
    }

    /// Owner-only: rotate the treasury (e.g., move to a Safe multisig).
    function setTreasury(address next) external onlyOwner {
        if (next == address(0)) revert ZeroAddress();
        emit TreasuryUpdated(treasury, next);
        treasury = next;
    }

    /// Owner-only: pause new payments. Existing approvals stay live but
    /// `payForItem` reverts until `setPaused(false)`.
    function setPaused(bool p) external onlyOwner {
        paused = p;
        emit Paused(p);
    }

    /// Owner-only: transfer ownership (intended for a Safe multisig).
    function transferOwnership(address next) external onlyOwner {
        if (next == address(0)) revert ZeroAddress();
        emit OwnerTransferred(owner, next);
        owner = next;
    }
}
