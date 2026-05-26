// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title BaseStrikerBadgeV2 — Soulbound NFT for weekly Top-10 players, with
///        dynamic per-token tokenURI based on (weekId, rank) stored on-chain.
///
/// v1 (0xd1C53618…) required the owner to call `setTokenURI(tokenId, url)`
/// after every mint to make the badge show artwork in wallets. v2 stores
/// `weekId` + `rank` per token and derives the tokenURI automatically:
///
///   tokenURI(N)  →  `${baseURI}/${weekId}/${rank}`
///                 → https://basestriker.xyz/api/badge/meta/1/3
///                 → returns ERC-721 JSON pointing at the PNG
///
/// Backend serves `/api/badge/meta/:weekId/:rank` (JSON) and the PNG lives
/// at `https://basestriker.xyz/badges/week-N-rank-M.png` (static).
///
/// Tier visuals: 1=GOLD, 2=SILVER, 3=BRONZE, 4-10=TOP-10 (cyan).
contract BaseStrikerBadgeV2 {
    string public constant name = "BaseStriker Weekly Top 10 Badge";
    string public constant symbol = "BSTRK10";

    /// Hard cap — only ranks 1..10. Backend signatures with rank > MAX_RANK
    /// are rejected on-chain regardless of signer.
    uint32 public constant MAX_RANK = 10;

    // ── Ownership / config ───────────────────────────────────────────────
    address public owner;
    address public signer;
    address public treasury;
    uint256 public mintFee;

    /// Prefix prepended to every tokenURI. Owner can rotate (e.g., point
    /// at IPFS instead of HTTPS) without redeploying.
    string public baseURI;

    // ── ERC-721 minimal state ────────────────────────────────────────────
    uint256 public totalSupply;
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;

    /// Per-token attributes — drive dynamic tokenURI + indexer queries.
    mapping(uint256 => uint64) public tokenWeekId;
    mapping(uint256 => uint32) public tokenRank;

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
    event BaseURIUpdated(string previous, string next);

    // ── Errors ───────────────────────────────────────────────────────────
    error NotOwner();
    error ZeroAddress();
    error FeeMismatch();
    error AlreadyMinted();
    error BadSignature();
    error NonTransferable();
    error RankOutOfRange();
    error NotMinted();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _signer, address _treasury, uint256 _mintFee, string memory _baseURI) {
        if (_signer == address(0) || _treasury == address(0)) revert ZeroAddress();
        owner = msg.sender;
        signer = _signer;
        treasury = _treasury;
        mintFee = _mintFee;
        baseURI = _baseURI;
        emit OwnerTransferred(address(0), msg.sender);
        emit SignerUpdated(address(0), _signer);
        emit TreasuryUpdated(address(0), _treasury);
        emit MintFeeUpdated(0, _mintFee);
        emit BaseURIUpdated("", _baseURI);
    }

    // ── Mint ─────────────────────────────────────────────────────────────

    /// Mint a Top-10 badge. Backend signs `keccak256(player, weekId, rank,
    /// chainId, address(this))` with `signer`; player presents the sig +
    /// pays `mintFee` (wei).
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
        tokenWeekId[tokenId] = weekId;
        tokenRank[tokenId] = rank;

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

    /// Dynamic tokenURI — composes `baseURI/<weekId>/<rank>`. Backend at
    /// that URL returns ERC-721 JSON with the tier-appropriate PNG.
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (_owners[tokenId] == address(0)) revert NotMinted();
        return string(
            abi.encodePacked(
                baseURI, "/", _u64ToString(tokenWeekId[tokenId]), "/", _u32ToString(tokenRank[tokenId])
            )
        );
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        // ERC-721 (0x80ac58cd) + ERC-165 (0x01ffc9a7) + ERC-5192 (soulbound, 0xb45a3c0e)
        return interfaceId == 0x80ac58cd || interfaceId == 0x01ffc9a7 || interfaceId == 0xb45a3c0e;
    }

    /// ERC-5192: tokens are always locked.
    function locked(uint256) external pure returns (bool) {
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

    function setBaseURI(string calldata next) external onlyOwner {
        emit BaseURIUpdated(baseURI, next);
        baseURI = next;
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

    function _u64ToString(uint64 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint64 tmp = v;
        uint256 len;
        while (tmp != 0) {
            len++;
            tmp /= 10;
        }
        bytes memory b = new bytes(len);
        while (v != 0) {
            len--;
            b[len] = bytes1(uint8(48 + v % 10));
            v /= 10;
        }
        return string(b);
    }

    function _u32ToString(uint32 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint32 tmp = v;
        uint256 len;
        while (tmp != 0) {
            len++;
            tmp /= 10;
        }
        bytes memory b = new bytes(len);
        while (v != 0) {
            len--;
            b[len] = bytes1(uint8(48 + v % 10));
            v /= 10;
        }
        return string(b);
    }
}
