// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title StrikerToken ($STRK) — BaseStriker rewards token.
/// @notice Fixed supply (1B). Only authorised minters from rewards pool can transfer in.
///         No new supply minted after deploy — pool is pre-funded.
contract StrikerToken is ERC20, ERC20Burnable, ERC20Permit {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;

    constructor(address treasury) ERC20("BaseStriker", "STRK") ERC20Permit("BaseStriker") {
        _mint(treasury, TOTAL_SUPPLY);
    }
}
