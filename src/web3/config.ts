// Network and contract configuration for Base mainnet + Base Sepolia.
// Contract addresses are filled in after deployment (see contracts/script/Deploy.s.sol).

import { base, baseSepolia, type Chain } from 'viem/chains';

export type NetworkName = 'base' | 'baseSepolia';

export interface NetworkConfig {
  chain: Chain;
  rpcUrl: string;
  contracts: {
    StrikerToken: `0x${string}`;
    ShipNFT: `0x${string}`;
    EquipmentNFT: `0x${string}`;
    GameRegistry: `0x${string}`;
    PaymentRouter: `0x${string}`;
    RewardsDistributor: `0x${string}`;
    Treasury: `0x${string}`;
    USDC: `0x${string}`;
  };
  paymasterUrl?: string;
  backendUrl: string;
}

const ZERO = '0x0000000000000000000000000000000000000000' as const;

/**
 * BaseStriker treasury — receives every shop purchase. Same wallet on
 * mainnet + Sepolia so the operator only has to keep one private key.
 * Override per-network via VITE_TREASURY_ADDR / _ADDR_TEST if you want
 * separate cold/hot wallets.
 */
const TREASURY_DEFAULT = '0xe569A1f798D14809A076ea1c11cb13d698DFcE64' as const;

export const NETWORKS: Record<NetworkName, NetworkConfig> = {
  base: {
    chain: base,
    rpcUrl: import.meta.env?.VITE_BASE_RPC || 'https://mainnet.base.org',
    contracts: {
      StrikerToken:       (import.meta.env?.VITE_STRK_ADDR as `0x${string}`)         || ZERO,
      ShipNFT:            (import.meta.env?.VITE_SHIP_ADDR as `0x${string}`)         || ZERO,
      EquipmentNFT:       (import.meta.env?.VITE_EQUIP_ADDR as `0x${string}`)        || ZERO,
      GameRegistry:       (import.meta.env?.VITE_REGISTRY_ADDR as `0x${string}`)     || ZERO,
      PaymentRouter:      (import.meta.env?.VITE_PAYMENT_ADDR as `0x${string}`)      || ZERO,
      RewardsDistributor: (import.meta.env?.VITE_REWARDS_ADDR as `0x${string}`)      || ZERO,
      Treasury:           (import.meta.env?.VITE_TREASURY_ADDR as `0x${string}`)     || TREASURY_DEFAULT,
      USDC:               '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913', // Native USDC on Base
    },
    paymasterUrl: import.meta.env?.VITE_PAYMASTER_URL,
    backendUrl: import.meta.env?.VITE_BACKEND_URL || 'https://api.basestriker.xyz',
  } as NetworkConfig,
  baseSepolia: {
    chain: baseSepolia,
    rpcUrl: import.meta.env?.VITE_BASE_SEPOLIA_RPC || 'https://sepolia.base.org',
    contracts: {
      StrikerToken:       (import.meta.env?.VITE_STRK_ADDR_TEST as `0x${string}`)        || ZERO,
      ShipNFT:            (import.meta.env?.VITE_SHIP_ADDR_TEST as `0x${string}`)        || ZERO,
      EquipmentNFT:       (import.meta.env?.VITE_EQUIP_ADDR_TEST as `0x${string}`)       || ZERO,
      GameRegistry:       (import.meta.env?.VITE_REGISTRY_ADDR_TEST as `0x${string}`)    || ZERO,
      PaymentRouter:      (import.meta.env?.VITE_PAYMENT_ADDR_TEST as `0x${string}`)     || ZERO,
      RewardsDistributor: (import.meta.env?.VITE_REWARDS_ADDR_TEST as `0x${string}`)     || ZERO,
      Treasury:           (import.meta.env?.VITE_TREASURY_ADDR_TEST as `0x${string}`)    || TREASURY_DEFAULT,
      USDC:               '0x036CbD53842c5426634e7929541eC2318f3dCF7e', // Base Sepolia USDC
    },
    paymasterUrl: import.meta.env?.VITE_PAYMASTER_URL_TEST,
    // Dev: prefer same host as the page (so `http://192.168.x.x:5173` resolves the
    // backend at `http://192.168.x.x:8787`). Falls back to localhost if `location`
    // is unavailable (SSR / unit test).
    backendUrl: import.meta.env?.VITE_BACKEND_URL_TEST
      || (typeof location !== 'undefined' ? `${location.protocol}//${location.hostname}:8787` : 'http://localhost:8787'),
  } as NetworkConfig,
};

export const DEFAULT_NETWORK: NetworkName =
  (import.meta.env?.VITE_DEFAULT_NETWORK as NetworkName) || 'baseSepolia';
