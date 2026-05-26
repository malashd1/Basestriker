// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { Treasury } from "../src/Treasury.sol";
import { StrikerToken } from "../src/StrikerToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TreasuryTest is Test {
    Treasury treasury;
    StrikerToken strk;
    address owner = address(0xA11CE);
    address pool = address(0xB0B);

    function setUp() public {
        strk = new StrikerToken(owner); // mints full supply to owner
        treasury = new Treasury(owner, IERC20(address(strk)));
        // Move full supply to treasury for tests.
        vm.prank(owner);
        strk.transfer(address(treasury), strk.totalSupply());
    }

    function testFundRewards() public {
        uint256 amt = 400_000_000 ether;
        vm.prank(owner);
        treasury.fundRewards(pool, amt);
        assertEq(strk.balanceOf(pool), amt);
    }

    function testOnlyOwnerCanFund() public {
        vm.expectRevert();
        treasury.fundRewards(pool, 1 ether);
    }

    function testWithdrawERC20() public {
        vm.prank(owner);
        treasury.withdraw(pool, address(strk), 100 ether);
        assertEq(strk.balanceOf(pool), 100 ether);
    }

    function testWithdrawETH() public {
        vm.deal(address(treasury), 5 ether);
        uint256 before = pool.balance;
        vm.prank(owner);
        treasury.withdraw(payable(pool), address(0), 5 ether);
        assertEq(pool.balance - before, 5 ether);
    }

    function testReceiveETH() public {
        (bool ok, ) = address(treasury).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(treasury).balance, 1 ether);
    }

    function testOwnershipTransferTwoStep() public {
        address newOwner = address(0xCAFE);
        vm.prank(owner);
        treasury.transferOwnership(newOwner);
        // pending owner has to accept
        assertEq(treasury.pendingOwner(), newOwner);
        // old owner is still in charge until accept
        vm.prank(owner);
        treasury.fundRewards(pool, 1 ether);
        // accept
        vm.prank(newOwner);
        treasury.acceptOwnership();
        assertEq(treasury.owner(), newOwner);
        // old owner can no longer call
        vm.expectRevert();
        vm.prank(owner);
        treasury.fundRewards(pool, 1 ether);
    }
}
