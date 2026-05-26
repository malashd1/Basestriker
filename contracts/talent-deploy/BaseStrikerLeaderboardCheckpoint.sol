// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title BaseStrikerLeaderboardCheckpoint
///
/// Append-only on-chain log of weekly leaderboard checkpoints. Every Monday
/// the backend computes `keccak256(packed top-100 rows)` and posts it here.
/// Any reader can replay the off-chain top-100 list and check it hashes to
/// the on-chain checkpoint — gives the leaderboard cryptographic integrity
/// without writing all 100 rows to chain.
///
/// Why this exists:
///   - Players can verify rankings weren't fabricated retroactively.
///   - Talent Protocol's Builder Score gives weight to verified deployed
///     contracts AND to ongoing contract activity (a checkpoint every
///     week is a steady on-chain pulse).
///   - 1 tx per week ⇒ ~$0.01/year in gas on Base. Effectively free.
///
/// Only `writer` can post checkpoints (the backend's signer wallet).
/// `owner` can rotate the writer (multisig in prod).
contract BaseStrikerLeaderboardCheckpoint {
    address public owner;
    address public writer;

    struct Checkpoint {
        uint64 weekId; // ISO-week index (e.g. weeks since Unix epoch / 7d)
        uint64 rowCount; // number of leaderboard rows hashed in
        uint128 timestamp; // when the writer posted it
        bytes32 root; // keccak256(packed rows) — see backend/src/shared/replay.ts
    }

    /// Monotonically increasing index. `checkpoints[i]` is the i-th checkpoint
    /// ever posted (in posting order, not strictly week order — backups OK).
    Checkpoint[] public checkpoints;

    /// Fast lookup: weekId → last checkpoint index posted for that week.
    /// If a week is re-posted (e.g. backend bug-fix), only the latest entry is
    /// authoritative; older entries stay in the array for audit.
    mapping(uint64 => uint256) public latestForWeek;

    event CheckpointPosted(
        uint64 indexed weekId, uint64 rowCount, bytes32 indexed root, uint256 index, uint256 timestamp
    );
    event WriterUpdated(address indexed previous, address indexed next);
    event OwnerTransferred(address indexed previous, address indexed next);

    error NotOwner();
    error NotWriter();
    error ZeroAddress();
    error ZeroRoot();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }
    modifier onlyWriter() {
        if (msg.sender != writer) revert NotWriter();
        _;
    }

    constructor(address _writer) {
        if (_writer == address(0)) revert ZeroAddress();
        owner = msg.sender;
        writer = _writer;
        emit OwnerTransferred(address(0), msg.sender);
        emit WriterUpdated(address(0), _writer);
    }

    /// Backend posts the weekly top-100 root.
    ///
    /// `root` is intended to be:
    ///   keccak256(abi.encodePacked(
    ///       weekId,
    ///       for each row in top100:
    ///         row.player (address, 20 bytes),
    ///         row.score  (uint64, 8 bytes),
    ///         row.level  (uint16, 2 bytes),
    ///         row.points (uint64, 8 bytes)
    ///   ))
    ///
    /// `rowCount` is informational — exact number of rows hashed (≤ 100).
    function postCheckpoint(uint64 weekId, uint64 rowCount, bytes32 root) external onlyWriter {
        if (root == bytes32(0)) revert ZeroRoot();
        checkpoints.push(
            Checkpoint({
                weekId: weekId, rowCount: rowCount, timestamp: uint128(block.timestamp), root: root
            })
        );
        uint256 idx = checkpoints.length - 1;
        latestForWeek[weekId] = idx;
        emit CheckpointPosted(weekId, rowCount, root, idx, block.timestamp);
    }

    /// Number of checkpoints ever posted.
    function checkpointCount() external view returns (uint256) {
        return checkpoints.length;
    }

    function setWriter(address next) external onlyOwner {
        if (next == address(0)) revert ZeroAddress();
        emit WriterUpdated(writer, next);
        writer = next;
    }

    function transferOwnership(address next) external onlyOwner {
        if (next == address(0)) revert ZeroAddress();
        emit OwnerTransferred(owner, next);
        owner = next;
    }
}
