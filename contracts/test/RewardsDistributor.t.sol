// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { RewardsDistributor } from "../src/RewardsDistributor.sol";
import { StrikerToken } from "../src/StrikerToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RewardsDistributorTest is Test {
    StrikerToken strk;
    RewardsDistributor rewards;
    address owner = address(0xA11CE);
    address player = address(0xB0B);
    uint256 signerPk;
    address signer;

    bytes32 constant CLAIM_TYPEHASH = keccak256(
        "Claim(address player,uint16 levelId,uint64 score,uint256 amount,uint64 nonce,uint64 expiry)"
    );

    function setUp() public {
        signerPk = 0xA11CEDEF;
        signer = vm.addr(signerPk);
        strk = new StrikerToken(owner);
        rewards = new RewardsDistributor(owner, IERC20(address(strk)), signer, 2_000 ether);
        vm.prank(owner);
        strk.transfer(address(rewards), 1_000_000 ether);
    }

    function _sign(address p, uint16 lvl, uint64 sc, uint256 amt, uint64 nonce, uint64 expiry)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(CLAIM_TYPEHASH, p, lvl, sc, amt, nonce, expiry));
        bytes32 domainSeparator = _domain();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _domain() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("BaseStrikerRewards")),
                keccak256(bytes("1")),
                block.chainid,
                address(rewards)
            )
        );
    }

    function testClaimHappyPath() public {
        uint64 expiry = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(player, 5, 12345, 100 ether, 1, expiry);
        vm.prank(player);
        rewards.claim(5, 12345, 100 ether, 1, expiry, sig);
        assertEq(strk.balanceOf(player), 100 ether);
    }

    function testRevertOnReplay() public {
        uint64 expiry = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(player, 5, 12345, 100 ether, 1, expiry);
        vm.prank(player);
        rewards.claim(5, 12345, 100 ether, 1, expiry, sig);
        vm.expectRevert(RewardsDistributor.NonceUsed.selector);
        vm.prank(player);
        rewards.claim(5, 12345, 100 ether, 1, expiry, sig);
    }

    function testRevertOnExpired() public {
        uint64 expiry = uint64(block.timestamp - 1);
        bytes memory sig = _sign(player, 5, 12345, 100 ether, 1, expiry);
        vm.expectRevert(RewardsDistributor.Expired.selector);
        vm.prank(player);
        rewards.claim(5, 12345, 100 ether, 1, expiry, sig);
    }

    function testRevertOnCapExceeded() public {
        uint64 expiry = uint64(block.timestamp + 1 hours);
        bytes memory sig1 = _sign(player, 5, 12345, 1500 ether, 1, expiry);
        vm.prank(player);
        rewards.claim(5, 12345, 1500 ether, 1, expiry, sig1);
        bytes memory sig2 = _sign(player, 6, 22222, 800 ether, 2, expiry);
        vm.expectRevert(RewardsDistributor.CapReached.selector);
        vm.prank(player);
        rewards.claim(6, 22222, 800 ether, 2, expiry, sig2);
    }
}
