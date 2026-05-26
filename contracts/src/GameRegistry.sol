// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title GameRegistry — stores per-player progression and best scores.
/// @notice Score submission requires backend-signed attestation.
contract GameRegistry is EIP712, Ownable2Step {
    using ECDSA for bytes32;

    error BadSig();
    error Expired();
    error NonceUsed();

    event ScoreSubmitted(address indexed player, uint16 levelId, uint64 score);
    event LevelCleared(address indexed player, uint16 levelId);
    event SignerUpdated(address indexed signer);

    address public signer;

    mapping(address => uint16) public highestLevelCleared;
    mapping(address => mapping(uint16 => uint64)) public bestScore;
    mapping(uint64 => bool) public nonceUsed;

    bytes32 private constant SCORE_TYPEHASH =
        keccak256("Score(address player,uint16 levelId,uint64 score,uint64 nonce,uint64 expiry)");

    constructor(address owner_, address signer_)
        EIP712("BaseStrikerRegistry", "1")
        Ownable(owner_)
    {
        signer = signer_;
        emit SignerUpdated(signer_);
    }

    function setSigner(address s) external onlyOwner { signer = s; emit SignerUpdated(s); }

    function submitScore(
        uint16 levelId,
        uint64 score,
        uint64 nonce,
        uint64 expiry,
        bytes calldata sig
    ) external {
        if (block.timestamp > expiry) revert Expired();
        if (nonceUsed[nonce]) revert NonceUsed();
        bytes32 structHash = keccak256(abi.encode(SCORE_TYPEHASH, msg.sender, levelId, score, nonce, expiry));
        bytes32 digest = _hashTypedDataV4(structHash);
        if (digest.recover(sig) != signer) revert BadSig();
        nonceUsed[nonce] = true;

        if (score > bestScore[msg.sender][levelId]) {
            bestScore[msg.sender][levelId] = score;
        }
        if (levelId > highestLevelCleared[msg.sender]) {
            highestLevelCleared[msg.sender] = levelId;
            emit LevelCleared(msg.sender, levelId);
        }
        emit ScoreSubmitted(msg.sender, levelId, score);
    }
}
