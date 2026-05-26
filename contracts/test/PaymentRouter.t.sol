// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { PaymentRouter, IShipNFT, IEquipmentNFT } from "../src/PaymentRouter.sol";
import { ShipNFT } from "../src/ShipNFT.sol";
import { EquipmentNFT } from "../src/EquipmentNFT.sol";
import { StrikerToken } from "../src/StrikerToken.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract PaymentRouterTest is Test {
    PaymentRouter router;
    ShipNFT shipNft;
    EquipmentNFT equipNft;
    StrikerToken strk;
    MockUSDC usdc;

    address owner = address(0xA11CE);
    address treasury = address(0xBEEF);
    address buyer = address(0xB0B);

    function setUp() public {
        usdc = new MockUSDC();
        strk = new StrikerToken(owner);
        shipNft = new ShipNFT(owner);
        equipNft = new EquipmentNFT(owner);
        router = new PaymentRouter(
            owner,
            IShipNFT(address(shipNft)),
            IEquipmentNFT(address(equipNft)),
            IERC20(address(strk)),
            IERC20(address(usdc)),
            treasury
        );

        vm.startPrank(owner);
        shipNft.setMinter(address(router), true);
        equipNft.setMinter(address(router), true);
        // Seed prices for ship tier 1 (id 2)
        router.setItem(2, true, 1, 0.005 ether, 5e6, 5_000 ether);
        // Seed equipment id 0x00010001 (cat=0, rarity=1, item=1)
        uint32 equipId = (uint32(0) << 24) | (uint32(1) << 16) | uint32(1);
        router.setItem(equipId, false, 0, 0.0015 ether, 1.5e6, 1_500 ether);
        // Transfer STRK from treasury (the deployer here is owner since constructor minted to owner) to buyer
        strk.transfer(buyer, 100_000 ether);
        vm.stopPrank();

        vm.deal(buyer, 1 ether);
        usdc.mint(buyer, 1_000e6);
    }

    function testBuyShipETHMintsAndForwardsValue() public {
        uint256 treasuryBefore = treasury.balance;
        vm.prank(buyer);
        uint256 newId = router.buyShipETH{ value: 0.005 ether }(1);
        assertEq(shipNft.ownerOf(newId), buyer);
        assertEq(shipNft.tierOf(newId), 1);
        assertEq(treasury.balance - treasuryBefore, 0.005 ether);
    }

    function testBuyShipETHRevertsWithoutEnoughValue() public {
        vm.expectRevert(PaymentRouter.InsufficientPayment.selector);
        vm.prank(buyer);
        router.buyShipETH{ value: 0.001 ether }(1);
    }

    function testBuyShipUSDCTransfersAndMints() public {
        vm.prank(buyer);
        usdc.approve(address(router), 5e6);
        vm.prank(buyer);
        uint256 newId = router.buyShipUSDC(1);
        assertEq(shipNft.ownerOf(newId), buyer);
        assertEq(usdc.balanceOf(treasury), 5e6);
    }

    function testBuyShipSTRKBurnsHalfAndCreditsTreasury() public {
        uint256 cost = 5_000 ether;
        vm.prank(buyer);
        strk.approve(address(router), cost);
        uint256 totalBefore = strk.totalSupply();
        uint256 treasuryBefore = strk.balanceOf(treasury);
        vm.prank(buyer);
        router.buyShipSTRK(1);
        // 50% burned, 50% to treasury
        assertEq(strk.totalSupply(), totalBefore - cost / 2, "burn half");
        assertEq(strk.balanceOf(treasury) - treasuryBefore, cost - cost / 2, "treasury other half");
    }

    function testBuyEquipmentSTRKMintsToBuyer() public {
        uint32 id = (uint32(0) << 24) | (uint32(1) << 16) | uint32(1);
        vm.prank(buyer);
        strk.approve(address(router), 1_500 ether);
        vm.prank(buyer);
        router.buyEquipmentSTRK(id);
        assertEq(equipNft.balanceOf(buyer, id), 1);
    }

    function testRevertOnUnknownItem() public {
        vm.expectRevert(PaymentRouter.UnknownItem.selector);
        vm.prank(buyer);
        router.buyEquipmentETH{ value: 1 ether }(999_999);
    }

    function testOnlyOwnerCanSetItem() public {
        vm.expectRevert();
        router.setItem(99, true, 0, 0, 0, 0);
        vm.prank(owner);
        router.setItem(99, true, 0, 1, 2, 3);
        (bool active,,,,,) = router.items(99);
        assertTrue(active);
    }

    function testCannotBuyShipFromEquipmentEndpoint() public {
        // ship item id=2 is a ship; buying it through buyEquipmentETH should revert
        vm.expectRevert(PaymentRouter.UnknownItem.selector);
        vm.prank(buyer);
        router.buyEquipmentETH{ value: 0.005 ether }(2);
    }
}
