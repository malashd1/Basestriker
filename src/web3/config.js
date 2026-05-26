// Network and contract configuration for Base mainnet + Base Sepolia.
// Contract addresses are filled in after deployment (see contracts/script/Deploy.s.sol).
import { base, baseSepolia } from 'viem/chains';
const ZERO = '0x0000000000000000000000000000000000000000';
/**
 * BaseStriker treasury — receives every shop purchase. Same wallet on
 * mainnet + Sepolia so the operator only has to keep one private key.
 * Override per-network via VITE_TREASURY_ADDR / _ADDR_TEST if you want
 * separate cold/hot wallets.
 */
const TREASURY_DEFAULT = '0xe569A1f798D14809A076ea1c11cb13d698DFcE64';
/**
 * Live BaseStriker PaymentRouter on Base mainnet. Players approve USDC to
 * this address and call `payForItem(sku, qty, amount)`; the contract pulls
 * USDC and forwards it to TREASURY_DEFAULT, emitting `ItemPaid(buyer, sku,
 * qty, amount)` for indexers. Verified on Basescan.
 *
 * Source: contracts/talent-deploy/BaseStrikerPaymentRouter.sol
 * Owner: 0x2eCe7De4… (deployer)
 *
 * Override per-network via VITE_PAYMENT_ADDR / _ADDR_TEST.
 */
const PAYMENT_ROUTER_BASE = '0xc08bda33E32Da9255f21BB57afF78e6d1EAb6789';
export const NETWORKS = {
    base: {
        chain: base,
        rpcUrl: import.meta.env?.VITE_BASE_RPC || 'https://mainnet.base.org',
        contracts: {
            StrikerToken: import.meta.env?.VITE_STRK_ADDR || ZERO,
            ShipNFT: import.meta.env?.VITE_SHIP_ADDR || ZERO,
            EquipmentNFT: import.meta.env?.VITE_EQUIP_ADDR || ZERO,
            GameRegistry: import.meta.env?.VITE_REGISTRY_ADDR || ZERO,
            PaymentRouter: import.meta.env?.VITE_PAYMENT_ADDR || PAYMENT_ROUTER_BASE,
            RewardsDistributor: import.meta.env?.VITE_REWARDS_ADDR || ZERO,
            Treasury: import.meta.env?.VITE_TREASURY_ADDR || TREASURY_DEFAULT,
            USDC: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913', // Native USDC on Base
        },
        paymasterUrl: import.meta.env?.VITE_PAYMASTER_URL,
        backendUrl: import.meta.env?.VITE_BACKEND_URL || 'https://api.basestriker.xyz',
    },
    baseSepolia: {
        chain: baseSepolia,
        rpcUrl: import.meta.env?.VITE_BASE_SEPOLIA_RPC || 'https://sepolia.base.org',
        contracts: {
            StrikerToken: import.meta.env?.VITE_STRK_ADDR_TEST || ZERO,
            ShipNFT: import.meta.env?.VITE_SHIP_ADDR_TEST || ZERO,
            EquipmentNFT: import.meta.env?.VITE_EQUIP_ADDR_TEST || ZERO,
            GameRegistry: import.meta.env?.VITE_REGISTRY_ADDR_TEST || ZERO,
            PaymentRouter: import.meta.env?.VITE_PAYMENT_ADDR_TEST || ZERO,
            RewardsDistributor: import.meta.env?.VITE_REWARDS_ADDR_TEST || ZERO,
            Treasury: import.meta.env?.VITE_TREASURY_ADDR_TEST || TREASURY_DEFAULT,
            USDC: '0x036CbD53842c5426634e7929541eC2318f3dCF7e', // Base Sepolia USDC
        },
        paymasterUrl: import.meta.env?.VITE_PAYMASTER_URL_TEST,
        // Dev: prefer same host as the page (so `http://192.168.x.x:5173` resolves the
        // backend at `http://192.168.x.x:8787`). Falls back to localhost if `location`
        // is unavailable (SSR / unit test).
        backendUrl: import.meta.env?.VITE_BACKEND_URL_TEST
            || (typeof location !== 'undefined' ? `${location.protocol}//${location.hostname}:8787` : 'http://localhost:8787'),
    },
};
export const DEFAULT_NETWORK = import.meta.env?.VITE_DEFAULT_NETWORK || 'baseSepolia';
