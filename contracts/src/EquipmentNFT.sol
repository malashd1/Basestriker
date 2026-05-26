// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title EquipmentNFT — weapons, shields, utilities, cosmetics.
/// @notice ID layout: top 8 bits = category, next 8 = rarity, lower 16 = item id.
///         category: 0=weapon,1=shield,2=utility,3=cosmetic.
contract EquipmentNFT is ERC1155, Ownable {
    error NotMinter();
    event MinterUpdated(address indexed minter, bool allowed);
    event EquipmentMinted(address indexed to, uint256 indexed id, uint256 amount);

    mapping(address => bool) public minters;

    modifier onlyMinter() {
        if (!minters[msg.sender]) revert NotMinter();
        _;
    }

    constructor(address owner_)
        ERC1155("https://meta.basestriker.xyz/equipment/{id}.json")
        Ownable(owner_)
    { }

    function setMinter(address m, bool ok) external onlyOwner {
        minters[m] = ok;
        emit MinterUpdated(m, ok);
    }

    function mint(address to, uint256 id, uint256 amount) external onlyMinter {
        _mint(to, id, amount, "");
        emit EquipmentMinted(to, id, amount);
    }

    function setURI(string memory newUri) external onlyOwner {
        _setURI(newUri);
    }

    function category(uint256 id) public pure returns (uint8) {
        return uint8(id >> 24);
    }

    function rarity(uint256 id) public pure returns (uint8) {
        return uint8(id >> 16);
    }

    function itemId(uint256 id) public pure returns (uint16) {
        return uint16(id);
    }
}
