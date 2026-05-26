// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { GameRegistry } from "../src/GameRegistry.sol";

contract GameRegistryTest is Test {
    GameRegistry registry;
    address owner = address(0xA11CE);
    address player = address(0xB0B);
    address other = address(0xCAFE);
    uint256 signerPk;
    address signer;

    bytes32 constant SCORE_TYPEHASH =
        keccak256("Score(address player,uint16 levelId,uint64 score,uint64 nonce,uint64 expiry)");

    function setUp() public {
        signerPk = 0xBEEF;
        signer = vm.addr(signerPk);
        registry = new GameRegistry(owner, signer);
    }

    function _sign(address p, uint16 lvl, uint64 sc, uint64 nonce, uint64 expiry)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(SCORE_TYPEHASH, p, lvl, sc, nonce, expiry));
        bytes32 domain = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("BaseStrikerRegistry")),
                keccak256(bytes("1")),
                block.chainid,
                address(registry)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domain, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function testSubmitUpdatesHighestAndBest() public {
        uint64 exp = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(player, 5, 1234, 1, exp);
        vm.prank(player);
        registry.submitScore(5, 1234, 1, exp, sig);
        assertEq(registry.highestLevelCleared(player), 5);
        assertEq(registry.bestScore(player, 5), 1234);
    }

    function testBestScoreNonDecreasing() public {
        uint64 exp = uint64(block.timestamp + 1 hours);
        bytes memory s1 = _sign(player, 3, 500, 1, exp);
        vm.prank(player);
        registry.submitScore(3, 500, 1, exp, s1);
        bytes memory s2 = _sign(player, 3, 200, 2, exp);
        vm.prank(player);
        registry.submitScore(3, 200, 2, exp, s2);
        assertEq(registry.bestScore(player, 3), 500);
    }

    function testHighestOnlyAdvances() public {
        uint64 exp = uint64(block.timestamp + 1 hours);
        bytes memory s1 = _sign(player, 7, 1, 1, exp);
        vm.prank(player);
        registry.submitScore(7, 1, 1, exp, s1);
        bytes memory s2 = _sign(player, 3, 2, 2, exp);
        vm.prank(player);
        registry.submitScore(3, 2, 2, exp, s2);
        assertEq(registry.highestLevelCleared(player), 7);
    }

    function testRevertOnBadSig() public {
        uint64 exp = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(player, 5, 1234, 1, exp);
        vm.expectRevert(GameRegistry.BadSig.selector);
        vm.prank(other); // wrong sender — sig was bound to `player`
        registry.submitScore(5, 1234, 1, exp, sig);
    }

    function testRevertOnExpiredSig() public {
        uint64 exp = uint64(block.timestamp - 1);
        bytes memory sig = _sign(player, 5, 1234, 1, exp);
        vm.expectRevert(GameRegistry.Expired.selector);
        vm.prank(player);
        registry.submitScore(5, 1234, 1, exp, sig);
    }

    function testRevertOnNonceReuse() public {
        uint64 exp = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(player, 5, 1234, 1, exp);
        vm.prank(player);
        registry.submitScore(5, 1234, 1, exp, sig);
        vm.expectRevert(GameRegistry.NonceUsed.selector);
        vm.prank(player);
        registry.submitScore(5, 1234, 1, exp, sig);
    }

    function testOnlyOwnerCanRotateSigner() public {
        address newSigner = address(0xDEAD);
        vm.expectRevert();
        registry.setSigner(newSigner);
        vm.prank(owner);
        registry.setSigner(newSigner);
        assertEq(registry.signer(), newSigner);
    }
}
