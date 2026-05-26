// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title RewardsDistributor — pays $STRK to players who present a backend-signed score.
/// @notice Daily per-wallet cap; nonce-based replay protection; halving-aware via dailyCap.
contract RewardsDistributor is EIP712, Ownable2Step {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    error BadSig();
    error Expired();
    error CapReached();
    error NonceUsed();
    error PausedErr();

    event Claimed(address indexed player, uint16 levelId, uint256 amount);
    event SignerUpdated(address indexed signer);
    event DailyCapUpdated(uint256 cap);
    event Paused(bool paused);

    IERC20  public immutable strk;
    address public signer;
    uint256 public dailyCap;
    bool    public paused;

    mapping(address => mapping(uint256 => uint256)) public claimedOnEpoch; // player => epoch => amount
    mapping(uint64  => bool) public nonceUsed;

    bytes32 private constant CLAIM_TYPEHASH =
        keccak256("Claim(address player,uint16 levelId,uint64 score,uint256 amount,uint64 nonce,uint64 expiry)");

    constructor(address owner_, IERC20 strk_, address signer_, uint256 dailyCap_)
        EIP712("BaseStrikerRewards", "1")
        Ownable(owner_)
    {
        strk = strk_;
        signer = signer_;
        dailyCap = dailyCap_;
        emit SignerUpdated(signer_);
        emit DailyCapUpdated(dailyCap_);
    }

    function setSigner(address s) external onlyOwner { signer = s; emit SignerUpdated(s); }
    function setDailyCap(uint256 c) external onlyOwner { dailyCap = c; emit DailyCapUpdated(c); }
    function setPaused(bool p) external onlyOwner { paused = p; emit Paused(p); }

    function claimedToday(address p) external view returns (uint256) {
        return claimedOnEpoch[p][_epoch()];
    }

    function claim(
        uint16 levelId,
        uint64 score,
        uint256 amount,
        uint64 nonce,
        uint64 expiry,
        bytes calldata sig
    ) external {
        if (paused) revert PausedErr();
        if (block.timestamp > expiry) revert Expired();
        if (nonceUsed[nonce]) revert NonceUsed();

        bytes32 structHash = keccak256(abi.encode(CLAIM_TYPEHASH, msg.sender, levelId, score, amount, nonce, expiry));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recovered = digest.recover(sig);
        if (recovered != signer) revert BadSig();

        uint256 epoch = _epoch();
        uint256 newTotal = claimedOnEpoch[msg.sender][epoch] + amount;
        if (newTotal > dailyCap) revert CapReached();
        claimedOnEpoch[msg.sender][epoch] = newTotal;
        nonceUsed[nonce] = true;

        strk.safeTransfer(msg.sender, amount);
        emit Claimed(msg.sender, levelId, amount);
    }

    /// @notice Owner can withdraw STRK back to treasury (e.g. epoch reset, migration).
    function withdraw(address to, uint256 amount) external onlyOwner {
        strk.safeTransfer(to, amount);
    }

    function _epoch() internal view returns (uint256) {
        return block.timestamp / 1 days;
    }
}
