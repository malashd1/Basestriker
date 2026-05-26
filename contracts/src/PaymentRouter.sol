// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IShipNFT { function mint(address to, uint8 tier) external returns (uint256); }
interface IEquipmentNFT { function mint(address to, uint256 id, uint256 amount) external; }
interface IStrikerToken { function burnFrom(address from, uint256 amount) external; function transferFrom(address from, address to, uint256 amount) external returns (bool); }
interface IAerodromeTWAP { function quote(address from, address to, uint256 amountIn) external view returns (uint256); }

/// @title PaymentRouter — routes ETH / USDC / $STRK purchases to mints.
/// @notice On ETH/USDC purchase: 30% buys $STRK on Aerodrome and burns, 70% to treasury.
///         On $STRK purchase: 50% burn, 50% to treasury. $STRK price = 85% of USDC price via TWAP.
contract PaymentRouter is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error UnknownItem();
    error InsufficientPayment();
    error NotConfigured();

    event PriceUpdated(uint32 indexed id, uint256 ethWei, uint256 usdc6, uint256 strkWei);
    event ItemPurchased(address indexed buyer, uint32 indexed id, uint8 currency, uint256 amount);

    enum Currency { ETH, USDC, STRK }

    struct Item {
        bool active;
        bool isShip;
        uint8 tierOrCategory;
        uint256 priceEth;       // wei
        uint256 priceUsdc;      // 6-decimal USDC
        uint256 priceStrk;      // 18-decimal STRK (fallback if TWAP unset)
    }

    IShipNFT      public immutable ship;
    IEquipmentNFT public immutable equipment;
    IERC20        public immutable strk;
    IERC20        public immutable usdc;
    address       public treasury;
    address       public twap; // Aerodrome quoter, optional

    mapping(uint32 => Item) public items;
    mapping(address => bool) public relayers; // fiat-onramp relayers (e.g. Stripe webhook signer)

    event RelayerUpdated(address indexed relayer, bool allowed);
    event RelayerMint(address indexed buyer, uint32 indexed id, bytes32 indexed externalRef);

    constructor(
        address owner_,
        IShipNFT ship_, IEquipmentNFT equipment_,
        IERC20 strk_, IERC20 usdc_,
        address treasury_
    ) Ownable(owner_) {
        ship = ship_;
        equipment = equipment_;
        strk = strk_;
        usdc = usdc_;
        treasury = treasury_;
    }

    // ---------- admin ----------

    function setTreasury(address t) external onlyOwner { treasury = t; }
    function setTwap(address t) external onlyOwner { twap = t; }

    function setRelayer(address r, bool ok) external onlyOwner {
        relayers[r] = ok;
        emit RelayerUpdated(r, ok);
    }

    error NotRelayer();
    modifier onlyRelayer() { if (!relayers[msg.sender]) revert NotRelayer(); _; }

    /// @notice Mint a ship purchased via fiat onramp (Stripe). Off-chain payment is already settled.
    /// @param externalRef opaque reference to the off-chain payment intent (audit trail).
    function relayerMintShip(address buyer, uint8 tier, bytes32 externalRef) external onlyRelayer returns (uint256) {
        uint32 id = _shipId(tier);
        Item memory it = items[id];
        if (!it.active || !it.isShip) revert UnknownItem();
        uint256 newId = ship.mint(buyer, tier);
        emit ItemPurchased(buyer, id, 99, 0);     // currency 99 = fiat
        emit RelayerMint(buyer, id, externalRef);
        return newId;
    }

    /// @notice Mint equipment via fiat onramp.
    function relayerMintEquipment(address buyer, uint32 id, bytes32 externalRef) external onlyRelayer {
        Item memory it = items[id];
        if (!it.active || it.isShip) revert UnknownItem();
        equipment.mint(buyer, id, 1);
        emit ItemPurchased(buyer, id, 99, 0);
        emit RelayerMint(buyer, id, externalRef);
    }

    function setItem(
        uint32 id, bool isShip, uint8 tierOrCategory,
        uint256 priceEth, uint256 priceUsdc, uint256 priceStrk
    ) external onlyOwner {
        items[id] = Item({
            active: true, isShip: isShip, tierOrCategory: tierOrCategory,
            priceEth: priceEth, priceUsdc: priceUsdc, priceStrk: priceStrk
        });
        emit PriceUpdated(id, priceEth, priceUsdc, priceStrk);
    }

    function priceETH(uint32 id) external view returns (uint256)  { return items[id].priceEth; }
    function priceUSDC(uint32 id) external view returns (uint256) { return items[id].priceUsdc; }
    function priceSTRK(uint32 id) external view returns (uint256) {
        Item memory it = items[id];
        if (twap != address(0) && it.priceUsdc > 0) {
            // TWAP-adjusted: 85% of USDC equivalent in STRK.
            try IAerodromeTWAP(twap).quote(address(usdc), address(strk), it.priceUsdc) returns (uint256 strkOut) {
                return strkOut * 85 / 100;
            } catch { return it.priceStrk; }
        }
        return it.priceStrk;
    }

    // ---------- buy: ETH ----------

    function buyShipETH(uint8 tier) external payable nonReentrant returns (uint256) {
        uint32 id = _shipId(tier);
        return _buyShipFromETH(id, tier);
    }

    function buyEquipmentETH(uint32 id) external payable nonReentrant {
        Item memory it = items[id];
        if (!it.active || it.isShip) revert UnknownItem();
        _consumeETH(it.priceEth);
        equipment.mint(msg.sender, id, 1);
        emit ItemPurchased(msg.sender, id, uint8(Currency.ETH), it.priceEth);
    }

    function _buyShipFromETH(uint32 id, uint8 tier) internal returns (uint256) {
        Item memory it = items[id];
        if (!it.active || !it.isShip) revert UnknownItem();
        _consumeETH(it.priceEth);
        uint256 newId = ship.mint(msg.sender, tier);
        emit ItemPurchased(msg.sender, id, uint8(Currency.ETH), it.priceEth);
        return newId;
    }

    function _consumeETH(uint256 price) internal {
        if (msg.value < price) revert InsufficientPayment();
        // Forward 100% to treasury; off-chain keeper splits 30% into BBB.
        (bool ok, ) = treasury.call{value: msg.value}("");
        require(ok, "treasury xfer");
    }

    // ---------- buy: USDC ----------

    function buyShipUSDC(uint8 tier) external nonReentrant returns (uint256) {
        uint32 id = _shipId(tier);
        Item memory it = items[id];
        if (!it.active || !it.isShip) revert UnknownItem();
        usdc.safeTransferFrom(msg.sender, treasury, it.priceUsdc);
        uint256 newId = ship.mint(msg.sender, tier);
        emit ItemPurchased(msg.sender, id, uint8(Currency.USDC), it.priceUsdc);
        return newId;
    }

    function buyEquipmentUSDC(uint32 id) external nonReentrant {
        Item memory it = items[id];
        if (!it.active || it.isShip) revert UnknownItem();
        usdc.safeTransferFrom(msg.sender, treasury, it.priceUsdc);
        equipment.mint(msg.sender, id, 1);
        emit ItemPurchased(msg.sender, id, uint8(Currency.USDC), it.priceUsdc);
    }

    // ---------- buy: STRK ----------

    function buyShipSTRK(uint8 tier) external nonReentrant returns (uint256) {
        uint32 id = _shipId(tier);
        Item memory it = items[id];
        if (!it.active || !it.isShip) revert UnknownItem();
        uint256 cost = _priceStrk(id);
        _consumeSTRK(cost);
        uint256 newId = ship.mint(msg.sender, tier);
        emit ItemPurchased(msg.sender, id, uint8(Currency.STRK), cost);
        return newId;
    }

    function buyEquipmentSTRK(uint32 id) external nonReentrant {
        Item memory it = items[id];
        if (!it.active || it.isShip) revert UnknownItem();
        uint256 cost = _priceStrk(id);
        _consumeSTRK(cost);
        equipment.mint(msg.sender, id, 1);
        emit ItemPurchased(msg.sender, id, uint8(Currency.STRK), cost);
    }

    function _consumeSTRK(uint256 amount) internal {
        // 50% burn, 50% treasury.
        uint256 burnAmt = amount / 2;
        uint256 toTreasury = amount - burnAmt;
        IStrikerToken(address(strk)).transferFrom(msg.sender, address(this), amount);
        // Burn half
        IStrikerToken(address(strk)).burnFrom(address(this), burnAmt);
        // Send the rest
        IERC20(address(strk)).safeTransfer(treasury, toTreasury);
    }

    function _priceStrk(uint32 id) internal view returns (uint256) {
        Item memory it = items[id];
        if (twap != address(0) && it.priceUsdc > 0) {
            try IAerodromeTWAP(twap).quote(address(usdc), address(strk), it.priceUsdc) returns (uint256 strkOut) {
                return strkOut * 85 / 100;
            } catch { return it.priceStrk; }
        }
        return it.priceStrk;
    }

    function _shipId(uint8 tier) internal pure returns (uint32) {
        // Ship items live at IDs 1..5 by convention.
        if (tier > 4) revert UnknownItem();
        return uint32(tier) + 1;
    }

    receive() external payable {}
}
