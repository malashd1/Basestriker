// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal Balancer V2 / Fjord LBP factory interface.
///         Fjord on Base uses Balancer V2's LiquidityBootstrappingPool factory.
///         https://docs.fjord.foundation
interface ILBPFactory {
    function create(
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        uint256[] memory weights, // 18-dec, sum to 1e18
        uint256 swapFeePercentage, // 1e16 = 1%
        address owner,
        bool swapEnabledOnStart
    ) external returns (address);
}

interface ILBP {
    function getPoolId() external view returns (bytes32);
    function updateWeightsGradually(uint256 startTime, uint256 endTime, uint256[] memory endWeights) external;
    function setSwapEnabled(bool swapEnabled) external;
}

interface IBalancerVault {
    enum JoinKind {
        INIT,
        EXACT_TOKENS_IN_FOR_BPT_OUT,
        TOKEN_IN_FOR_EXACT_BPT_OUT,
        ALL_TOKENS_IN_FOR_EXACT_BPT_OUT
    }

    struct JoinPoolRequest {
        IERC20[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    function joinPool(bytes32 poolId, address sender, address recipient, JoinPoolRequest memory request)
        external
        payable;
}

/// @notice Deploys a STRK/USDC Liquidity Bootstrapping Pool on Base via Fjord/Balancer V2.
/// @dev    Run with:
///         forge script script/DeployLBP.s.sol --rpc-url base --broadcast --verify -vv
///
/// Required env:
///   - DEPLOYER_PK            deployer EOA (or use --ledger / --account)
///   - STRK_ADDRESS           deployed StrikerToken
///   - USDC_ADDRESS           Base native USDC (0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)
///   - LBP_FACTORY            Fjord LBP factory on Base
///   - BALANCER_VAULT         Balancer V2 Vault on Base
///   - LBP_OWNER              multisig that will own the LBP (Safe)
///   - STRK_SEED_AMOUNT       18-dec amount of STRK to seed (e.g. 50_000_000 ether)
///   - USDC_SEED_AMOUNT       6-dec amount of USDC to seed (e.g. 50_000 * 1e6)
///   - START_TIMESTAMP        unix seconds — pool sale window start
///   - END_TIMESTAMP          unix seconds — sale window end (recommended 48h)
contract DeployLBP is Script {
    uint256 constant FEE_1_PERCENT = 1e16;

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        IERC20 strk = IERC20(vm.envAddress("STRK_ADDRESS"));
        IERC20 usdc = IERC20(vm.envAddress("USDC_ADDRESS"));
        ILBPFactory factory = ILBPFactory(vm.envAddress("LBP_FACTORY"));
        IBalancerVault vault = IBalancerVault(vm.envAddress("BALANCER_VAULT"));
        address owner = vm.envAddress("LBP_OWNER");
        uint256 strkAmount = vm.envUint("STRK_SEED_AMOUNT");
        uint256 usdcAmount = vm.envUint("USDC_SEED_AMOUNT");
        uint256 startTs = vm.envUint("START_TIMESTAMP");
        uint256 endTs = vm.envUint("END_TIMESTAMP");

        require(endTs > startTs, "bad time range");
        require(strkAmount > 0 && usdcAmount > 0, "zero seed");

        vm.startBroadcast(pk);

        // Token order must be sorted ascending by address for Balancer pools.
        IERC20[] memory tokens = new IERC20[](2);
        uint256[] memory startWeights = new uint256[](2);
        uint256[] memory endWeights = new uint256[](2);

        bool strkFirst = address(strk) < address(usdc);
        tokens[0] = strkFirst ? strk : usdc;
        tokens[1] = strkFirst ? usdc : strk;

        // 90 / 10 in favor of STRK at start → 50 / 50 at end.
        // This produces a downward price-discovery curve as buyers absorb the imbalance.
        if (strkFirst) {
            startWeights[0] = 0.9e18;
            startWeights[1] = 0.1e18;
            endWeights[0] = 0.5e18;
            endWeights[1] = 0.5e18;
        } else {
            startWeights[0] = 0.1e18;
            startWeights[1] = 0.9e18;
            endWeights[0] = 0.5e18;
            endWeights[1] = 0.5e18;
        }

        address pool = factory.create(
            "BaseStriker LBP",
            "BSK-LBP",
            tokens,
            startWeights,
            FEE_1_PERCENT,
            owner,
            false // swap disabled at create; enable at startTimestamp
        );
        bytes32 poolId = ILBP(pool).getPoolId();
        console2.log("LBP pool deployed:", pool);
        console2.logBytes32(poolId);

        // Approve and deposit initial liquidity (INIT join).
        strk.approve(address(vault), strkAmount);
        usdc.approve(address(vault), usdcAmount);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = strkFirst ? strkAmount : usdcAmount;
        amountsIn[1] = strkFirst ? usdcAmount : strkAmount;

        IBalancerVault.JoinPoolRequest memory req = IBalancerVault.JoinPoolRequest({
            assets: tokens,
            maxAmountsIn: amountsIn,
            userData: abi.encode(IBalancerVault.JoinKind.INIT, amountsIn),
            fromInternalBalance: false
        });
        vault.joinPool(poolId, msg.sender, owner, req);

        // Schedule the weight glide. Pool is still paused — owner enables swap at startTs.
        ILBP(pool).updateWeightsGradually(startTs, endTs, endWeights);

        vm.stopBroadcast();

        console2.log("=== Next steps (manual) ===");
        console2.log("1. Multisig accepts LBP ownership.");
        console2.log("2. At START_TIMESTAMP, multisig calls pool.setSwapEnabled(true).");
        console2.log("3. After END_TIMESTAMP, multisig calls pool.setSwapEnabled(false).");
        console2.log("4. Withdraw remaining liquidity via vault.exitPool, route proceeds:");
        console2.log("   - 50% to Aerodrome STRK/USDC LP (24mo locked)");
        console2.log("   - 30% to Treasury");
        console2.log("   - 20% to buy back STRK and burn");
    }
}
