// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title BaseStrikerBadge — Soulbound (non-transferable) NFT for weekly Top-10 players.
///
/// Self-contained ERC-721 implementation (no OpenZeppelin import) so the file
/// drops straight into Remix and deploys without any setup.
///
/// Eligibility: rank 1-10 of the weekly leaderboard. Enforced on-chain via
/// `MAX_RANK`: even if the backend signs a higher rank by mistake, the mint
/// reverts. Only the actual top 10 of each week can ever hold this badge.
///
/// Mint flow:
///   1. Player finishes a week inside the BaseStriker Top 10.
///   2. Backend computes a signed authorisation: `keccak256(player, weekId, rank, chainId, this)`
///      signed by `signer`.
///   3. Player calls `mint(weekId, rank, signature)` paying `mintFee` (wei).
///   4. Badge is minted to the player's wallet, transfers permanently disabled.
///
/// On-chain, every mint produces a tx with the player as `msg.sender` —
/// indexable by Talent Protocol and any explorer.
contract BaseStrikerBadge {
    string public constant name = "BaseStriker Weekly Top 10 Badge";
    string public constant symbol = "BSTRK10";

    /// Hard cap — only ranks 1-10 can mint. Backend-issued signatures with
    /// `rank > MAX_RANK` are rejected on-chain regardless of signer.
    uint32 public constant MAX_RANK = 10;

    // ── Ownership / config ───────────────────────────────────────────────
    address public owner; // can rotate signer + treasury + fee
    address public signer; // backend ed25519/ECDSA EOA that authorises mints
    address public treasury; // receives mintFee
    uint256 public mintFee; // wei

    // ── ERC-721 minimal state ────────────────────────────────────────────
    uint256 public totalSupply;
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => string) private _tokenURIs;

    /// Replay-protect: (player, weekId, rank) → already minted.
    mapping(bytes32 => bool) public minted;

    // ── Events ───────────────────────────────────────────────────────────
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner_, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner_, address indexed operator, bool approved);

    event BadgeMinted(
        address indexed player, uint256 indexed tokenId, uint64 indexed weekId, uint32 rank, uint256 feePaid
    );
    event SignerUpdated(address indexed previous, address indexed next);
    event TreasuryUpdated(address indexed previous, address indexed next);
    event MintFeeUpdated(uint256 previous, uint256 next);
    event OwnerTransferred(address indexed previous, address indexed next);

    // ── Errors ───────────────────────────────────────────────────────────
    error NotOwner();
    error ZeroAddress();
    error FeeMismatch();
    error AlreadyMinted();
    error BadSignature();
    error NonTransferable();
    error RankOutOfRange();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _signer, address _treasury, uint256 _mintFee) {
        if (_signer == address(0) || _treasury == address(0)) revert ZeroAddress();
        owner = msg.sender;
        signer = _signer;
        treasury = _treasury;
        mintFee = _mintFee;
        emit OwnerTransferred(address(0), msg.sender);
        emit SignerUpdated(address(0), _signer);
        emit TreasuryUpdated(address(0), _treasury);
        emit MintFeeUpdated(0, _mintFee);
    }

    // ── Mint ─────────────────────────────────────────────────────────────

    /// Mint a badge. The player MUST present a signature from `signer` over
    /// the message `keccak256(abi.encodePacked(player, weekId, rank, block.chainid, address(this)))`.
    ///
    /// `sig` is a 65-byte ECDSA signature in (r, s, v) packed form.
    function mint(uint64 weekId, uint32 rank, bytes calldata sig) external payable {
        if (msg.value != mintFee) revert FeeMismatch();
        if (rank == 0 || rank > MAX_RANK) revert RankOutOfRange();

        bytes32 key = keccak256(abi.encode(msg.sender, weekId, rank));
        if (minted[key]) revert AlreadyMinted();

        bytes32 digest = keccak256(abi.encodePacked(msg.sender, weekId, rank, block.chainid, address(this)));
        bytes32 ethSigned = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        if (_recover(ethSigned, sig) != signer) revert BadSignature();

        minted[key] = true;
        uint256 tokenId = ++totalSupply;
        _owners[tokenId] = msg.sender;
        _balances[msg.sender] += 1;

        if (mintFee > 0) {
            (bool ok,) = treasury.call{ value: mintFee }("");
            require(ok, "fee fwd");
        }

        emit Transfer(address(0), msg.sender, tokenId);
        emit BadgeMinted(msg.sender, tokenId, weekId, rank, msg.value);
    }

    // ── Soulbound: ALL transfers reverted ────────────────────────────────

    function transferFrom(address, address, uint256) external pure {
        revert NonTransferable();
    }

    function safeTransferFrom(address, address, uint256) external pure {
        revert NonTransferable();
    }

    function safeTransferFrom(address, address, uint256, bytes calldata) external pure {
        revert NonTransferable();
    }

    function approve(address, uint256) external pure {
        revert NonTransferable();
    }

    function setApprovalForAll(address, bool) external pure {
        revert NonTransferable();
    }

    // ── ERC-721 read methods ─────────────────────────────────────────────

    function balanceOf(address o) external view returns (uint256) {
        if (o == address(0)) revert ZeroAddress();
        return _balances[o];
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address o = _owners[tokenId];
        if (o == address(0)) revert ZeroAddress();
        return o;
    }

    function getApproved(uint256) external pure returns (address) {
        return address(0);
    }

    function isApprovedForAll(address, address) external pure returns (bool) {
        return false;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        return _tokenURIs[tokenId];
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        // ERC-721 (0x80ac58cd) + ERC-165 (0x01ffc9a7) + ERC-5192 (soulbound, 0xb45a3c0e)
        return interfaceId == 0x80ac58cd || interfaceId == 0x01ffc9a7 || interfaceId == 0xb45a3c0e;
    }

    /// ERC-5192: tokens are always locked.
    function locked(
        uint256 /*tokenId*/
    )
        external
        pure
        returns (bool)
    {
        return true;
    }

    // ── Admin ────────────────────────────────────────────────────────────

    function setSigner(address next) external onlyOwner {
        if (next == address(0)) revert ZeroAddress();
        emit SignerUpdated(signer, next);
        signer = next;
    }

    function setTreasury(address next) external onlyOwner {
        if (next == address(0)) revert ZeroAddress();
        emit TreasuryUpdated(treasury, next);
        treasury = next;
    }

    function setMintFee(uint256 next) external onlyOwner {
        emit MintFeeUpdated(mintFee, next);
        mintFee = next;
    }

    function setTokenURI(uint256 tokenId, string calldata uri) external onlyOwner {
        _tokenURIs[tokenId] = uri;
    }

    function transferOwnership(address next) external onlyOwner {
        if (next == address(0)) revert ZeroAddress();
        emit OwnerTransferred(owner, next);
        owner = next;
    }

    // ── Internal ─────────────────────────────────────────────────────────

    function _recover(bytes32 digest, bytes calldata sig) internal pure returns (address) {
        if (sig.length != 65) return address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (v < 27) v += 27;
        if (v != 27 && v != 28) return address(0);
        return ecrecover(digest, v, r, s);
    }
}
