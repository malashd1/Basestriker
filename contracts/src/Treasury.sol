// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Treasury — receives shop revenue and runs buy-back-and-burn.
/// @notice Owner is intended to be a Safe multisig with 7-day timelock.
contract Treasury is Ownable2Step {
    using SafeERC20 for IERC20;

    event Buyback(uint256 amountInEth, uint256 amountInUsdc, uint256 strkBurned);
    event RewardsFunded(address indexed rewardsPool, uint256 amount);
    event Withdraw(address indexed to, address indexed token, uint256 amount);

    IERC20 public immutable strk;

    constructor(address owner_, IERC20 strk_) Ownable(owner_) { strk = strk_; }

    /// @notice Forward STRK to a rewards distributor (owner-gated).
    function fundRewards(address pool, uint256 amount) external onlyOwner {
        strk.safeTransfer(pool, amount);
        emit RewardsFunded(pool, amount);
    }

    /// @notice Owner-only withdraw — used for audited grants, payroll, etc.
    function withdraw(address to, address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            (bool ok, ) = to.call{value: amount}("");
            require(ok, "eth xfer");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
        emit Withdraw(to, token, amount);
    }

    /// @notice BBB hook — keeper calls with off-chain Aerodrome swap calldata.
    /// @dev We delegate to a router via low-level call; this is the simplest pattern
    ///      and lets the keeper choose the best route. STRK received here is burned.
    function executeBuyback(
        address router,
        bytes calldata routerCalldata,
        uint256 ethBudget,
        uint256 usdcBudget,
        IERC20 usdc
    ) external onlyOwner {
        uint256 strkBefore = strk.balanceOf(address(this));
        if (usdcBudget > 0) usdc.forceApprove(router, usdcBudget);
        (bool ok, ) = router.call{value: ethBudget}(routerCalldata);
        require(ok, "router fail");
        uint256 received = strk.balanceOf(address(this)) - strkBefore;
        // burn the STRK we just bought
        (bool ok2, ) = address(strk).call(abi.encodeWithSignature("burn(uint256)", received));
        require(ok2, "burn fail");
        emit Buyback(ethBudget, usdcBudget, received);
    }

    receive() external payable {}
}
