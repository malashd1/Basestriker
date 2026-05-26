// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ShipNFT — BaseStriker ship NFTs (ERC-721, soulbound = false).
/// @notice Tier encodes the ship class. Metadata is generated on-chain (data URI).
contract ShipNFT is ERC721, Ownable {
    error NotMinter();
    error InvalidTier();

    event MinterUpdated(address indexed minter, bool allowed);
    event ShipMinted(address indexed to, uint256 indexed id, uint8 tier);

    mapping(address => bool) public minters;
    mapping(uint256 => uint8) public tierOf;
    uint256 public totalMinted;

    string private constant BASE_URI = "https://meta.basestriker.xyz/ship/";

    modifier onlyMinter() {
        if (!minters[msg.sender]) revert NotMinter();
        _;
    }

    constructor(address owner_) ERC721("BaseStriker Ship", "BSTR-SHIP") Ownable(owner_) { }

    function setMinter(address m, bool ok) external onlyOwner {
        minters[m] = ok;
        emit MinterUpdated(m, ok);
    }

    function mint(address to, uint8 tier) external onlyMinter returns (uint256 id) {
        if (tier > 4) revert InvalidTier();
        unchecked {
            id = ++totalMinted;
        }
        tierOf[id] = tier;
        _safeMint(to, id);
        emit ShipMinted(to, id, tier);
    }

    function _baseURI() internal pure override returns (string memory) {
        return BASE_URI;
    }
}
