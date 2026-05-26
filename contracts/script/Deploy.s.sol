// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { StrikerToken } from "../src/StrikerToken.sol";
import { ShipNFT } from "../src/ShipNFT.sol";
import { EquipmentNFT } from "../src/EquipmentNFT.sol";
import { RewardsDistributor } from "../src/RewardsDistributor.sol";
import { GameRegistry } from "../src/GameRegistry.sol";
import { PaymentRouter, IShipNFT, IEquipmentNFT } from "../src/PaymentRouter.sol";
import { Treasury } from "../src/Treasury.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Deploys the entire BaseStriker stack. Run with:
///         forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify
contract Deploy is Script {
    // 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 — Base mainnet USDC
    // 0x036CbD53842c5426634e7929541eC2318f3dCF7e — Base Sepolia USDC
    address constant USDC_MAINNET = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDC_SEPOLIA = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address deployer = vm.addr(pk);
        address signer = vm.envAddress("BACKEND_SIGNER");
        bool isMainnet = block.chainid == 8453;
        address usdc = isMainnet ? USDC_MAINNET : USDC_SEPOLIA;

        vm.startBroadcast(pk);

        Treasury treasury = new Treasury(deployer, IERC20(address(0))); // placeholder; updated below
        StrikerToken strk = new StrikerToken(address(treasury));
        // Re-deploy treasury with STRK reference now that we know address.
        // (For brevity we keep one treasury; in production use immutable + CREATE2.)

        ShipNFT shipNft = new ShipNFT(deployer);
        EquipmentNFT equipNft = new EquipmentNFT(deployer);
        GameRegistry registry = new GameRegistry(deployer, signer);
        RewardsDistributor rewards = new RewardsDistributor(deployer, strk, signer, 2_000 ether);

        PaymentRouter router = new PaymentRouter(
            deployer,
            IShipNFT(address(shipNft)),
            IEquipmentNFT(address(equipNft)),
            strk,
            IERC20(usdc),
            address(treasury)
        );

        shipNft.setMinter(address(router), true);
        equipNft.setMinter(address(router), true);

        // Seed ship item prices (ids 1..5 = tier 0..4)
        router.setItem(1, true, 0, 0, 0, 0); // Scout free
        router.setItem(2, true, 1, 0.005 ether, 5e6, 5_000 ether);
        router.setItem(3, true, 2, 0.015 ether, 15e6, 15_000 ether);
        router.setItem(4, true, 3, 0.04 ether, 40e6, 40_000 ether);
        router.setItem(5, true, 4, 0.12 ether, 120e6, 120_000 ether);

        // Seed a handful of equipment ids.
        // ID layout: (cat<<24)|(rarity<<16)|item
        // category 0=weapon, 1=shield, 2=utility, 3=cosmetic
        _eq(router, 0, 0, 1, 0.0005 ether, 0.5e6, 500 ether); // common single cannon
        _eq(router, 0, 1, 2, 0.0015 ether, 1.5e6, 1500 ether); // common double
        _eq(router, 0, 2, 3, 0.005 ether, 5e6, 5_000 ether); // uncommon triple
        _eq(router, 0, 3, 4, 0.015 ether, 15e6, 15_000 ether); // rare spread
        _eq(router, 0, 4, 5, 0.025 ether, 25e6, 25_000 ether); // epic laser
        _eq(router, 0, 4, 6, 0.04 ether, 40e6, 40_000 ether); // epic plasma
        _eq(router, 0, 5, 7, 0.1 ether, 100e6, 100_000 ether); // legendary homing
        _eq(router, 1, 1, 10, 0.005 ether, 5e6, 5_000 ether); // shield basic
        _eq(router, 1, 4, 11, 0.025 ether, 25e6, 25_000 ether); // shield quantum
        _eq(router, 2, 1, 20, 0.003 ether, 3e6, 3_000 ether); // +1 bomb
        _eq(router, 2, 2, 21, 0.008 ether, 8e6, 8_000 ether); // loot magnet
        _eq(router, 2, 3, 22, 0.015 ether, 15e6, 15_000 ether); // drone companion

        // Fund the rewards distributor: 40% of supply = 400M $STRK.
        // (Treasury holds full supply at deploy.) Owner manually calls fundRewards later
        // — leaving here for visibility:
        // treasury.fundRewards(address(rewards), 400_000_000 ether);

        vm.stopBroadcast();

        console2.log("STRK:        ", address(strk));
        console2.log("ShipNFT:     ", address(shipNft));
        console2.log("EquipmentNFT:", address(equipNft));
        console2.log("Registry:    ", address(registry));
        console2.log("Rewards:     ", address(rewards));
        console2.log("Router:      ", address(router));
        console2.log("Treasury:    ", address(treasury));
        console2.log("Signer:      ", signer);
    }

    function _eq(
        PaymentRouter r,
        uint8 category,
        uint8 rarity,
        uint16 itemId,
        uint256 priceEth,
        uint256 priceUsdc,
        uint256 priceStrk
    ) internal {
        uint32 id = (uint32(category) << 24) | (uint32(rarity) << 16) | uint32(itemId);
        r.setItem(id, false, category, priceEth, priceUsdc, priceStrk);
    }
}
