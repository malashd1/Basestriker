// USDC payment helper — used by the shop and the settings ship/weapon catalogue.
//
// Flow:
//   1. If PaymentRouter is configured for the current network → route through
//      the contract. The contract pulls USDC via `transferFrom` and emits a
//      typed `ItemPaid(buyer, sku, qty, amount)` event that indexers (Talent
//      Protocol, The Graph, Basescan) can attribute to the buyer + item.
//      Adds one approve() tx on first purchase per allowance (cached).
//   2. If PaymentRouter is NOT set (legacy / Sepolia without deploy yet) →
//      fall back to a plain `USDC.transfer(treasury, amount)`. Same result
//      financially, no event semantic on-chain.
//
// Behaviour matrix (mirrors cosmic-seeker/skr.ts on the Solana side):
//   - No wallet              → returns { kind: 'no-wallet' }
//   - Treasury / USDC unset  → returns { kind: 'no-config' }
//   - Wrong chain            → walletClient.switchChain first; if it fails
//                              (user declines), the writeContract surfaces
//                              the exact reason in its error.
//   - Buyer has < amount     → wallet throws; caller surfaces error
//   - Happy path             → returns { kind: 'tx', hash }
import { parseUnits, keccak256, toBytes } from 'viem';
import { walletClient, walletAddress, currentNetwork, publicClient } from './wallet';
import { NETWORKS } from './config';
const USDC_ABI = [
    {
        type: 'function',
        name: 'transfer',
        stateMutability: 'nonpayable',
        inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }],
        outputs: [{ name: '', type: 'bool' }],
    },
    {
        type: 'function',
        name: 'approve',
        stateMutability: 'nonpayable',
        inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }],
        outputs: [{ name: '', type: 'bool' }],
    },
    {
        type: 'function',
        name: 'allowance',
        stateMutability: 'view',
        inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }],
        outputs: [{ name: '', type: 'uint256' }],
    },
    {
        type: 'function',
        name: 'balanceOf',
        stateMutability: 'view',
        inputs: [{ name: 'owner', type: 'address' }],
        outputs: [{ name: '', type: 'uint256' }],
    },
    {
        type: 'function',
        name: 'decimals',
        stateMutability: 'view',
        inputs: [],
        outputs: [{ name: '', type: 'uint8' }],
    },
];
const PAYMENT_ROUTER_ABI = [
    {
        type: 'function',
        name: 'payForItem',
        stateMutability: 'nonpayable',
        inputs: [
            { name: 'sku', type: 'bytes32' },
            { name: 'qty', type: 'uint32' },
            { name: 'amount', type: 'uint256' },
        ],
        outputs: [],
    },
];
const ZERO = '0x0000000000000000000000000000000000000000';
/**
 * Hash an arbitrary shop-item ID (string like `"extra-life"`) into the
 * 32-byte SKU the router expects. Deterministic, off-chain — no RPC.
 */
export function skuHash(itemId) {
    return keccak256(toBytes(itemId));
}
/**
 * Best-effort chain switch — viem throws a confusing error otherwise. We
 * swallow user-rejection here; the subsequent writeContract surfaces a
 * clearer message if the chain still doesn't match.
 */
async function ensureChain() {
    const wc = walletClient();
    if (!wc)
        return;
    const cfg = NETWORKS[currentNetwork()];
    try {
        const current = await wc.getChainId();
        if (current !== cfg.chain.id) {
            await wc.switchChain({ id: cfg.chain.id });
        }
    }
    catch (e) {
        console.warn('[pay] chain switch declined / failed', e);
    }
}
/**
 * Pre-flight check + balance comparison so MetaMask's confusing revert
 * preview ("ERC20: transfer amount exceeds balance") never reaches the
 * player. We throw a friendly error that the shop's try/catch surfaces.
 */
async function assertEnoughUsdc(amount, priceUsd, qty) {
    const me = walletAddress();
    if (!me)
        return;
    const cfg = NETWORKS[currentNetwork()];
    try {
        const pc = publicClient();
        const balance = (await pc.readContract({
            address: cfg.contracts.USDC,
            abi: USDC_ABI,
            functionName: 'balanceOf',
            args: [me],
        }));
        if (balance < amount) {
            const have = Number(balance) / 1_000_000;
            const need = priceUsd * qty;
            throw new Error(`Need ${need} USDC, you have ${have.toFixed(2)}.`);
        }
    }
    catch (e) {
        // Re-throw insufficient-balance; swallow other RPC errors so the
        // real on-chain call still gets a chance.
        if (String(e?.message ?? '').startsWith('Need '))
            throw e;
        console.warn('[pay] balance pre-check failed (continuing anyway)', e);
    }
}
/**
 * Ensure the router has at least `amount` USDC allowance from the buyer.
 * If not, prompts one approve() transaction (granted the max value so
 * future purchases don't re-prompt). Returns when allowance is sufficient.
 */
async function ensureAllowance(router, amount) {
    const me = walletAddress();
    const wc = walletClient();
    if (!me || !wc)
        return;
    const cfg = NETWORKS[currentNetwork()];
    const pc = publicClient();
    const current = (await pc.readContract({
        address: cfg.contracts.USDC,
        abi: USDC_ABI,
        functionName: 'allowance',
        args: [me, router],
    }));
    if (current >= amount)
        return;
    // Grant a high allowance so subsequent purchases don't re-prompt. Using
    // `2**128 - 1` rather than uint256 max because some wallets warn loudly
    // on "infinite approval" — 2^128 is still ~3.4 × 10^32 USDC, effectively
    // unlimited for our use case, and reads as a finite number in MM.
    const HIGH_ALLOWANCE = (1n << 128n) - 1n;
    const approveHash = await wc.writeContract({
        address: cfg.contracts.USDC,
        abi: USDC_ABI,
        functionName: 'approve',
        args: [router, HIGH_ALLOWANCE],
        account: me,
        chain: cfg.chain,
    });
    // Wait for the approval to be mined so the next payForItem call doesn't
    // race the allowance update.
    await pc.waitForTransactionReceipt({ hash: approveHash });
}
/**
 * Send `priceUsd × qty` USDC. If a PaymentRouter is configured for the
 * current network, route through the contract; otherwise direct transfer.
 *
 * `priceUsd` is a dollar amount (1 = one USDC, 0.5 = fifty cents). We
 * convert to 6-decimal base units before submitting.
 *
 * `itemId` (default `"unknown"`) becomes the on-chain `sku` field —
 * passing the shop item's `id` lets indexers reconstruct what was bought.
 */
export async function payUsdc(priceUsd, qty, itemId = 'unknown') {
    const me = walletAddress();
    const wc = walletClient();
    if (!me || !wc)
        return { kind: 'no-wallet' };
    const cfg = NETWORKS[currentNetwork()];
    if (!cfg.contracts.USDC || cfg.contracts.USDC === ZERO)
        return { kind: 'no-config' };
    if (!cfg.contracts.Treasury || cfg.contracts.Treasury === ZERO)
        return { kind: 'no-config' };
    // USDC on Base + Base Sepolia is 6-decimal; parseUnits avoids float drift.
    const amount = parseUnits((priceUsd * qty).toFixed(6), 6);
    await ensureChain();
    await assertEnoughUsdc(amount, priceUsd, qty);
    const router = cfg.contracts.PaymentRouter;
    const routerLive = router && router !== ZERO;
    // ─── Path 1: PaymentRouter (mainnet, indexable on-chain event) ──────
    if (routerLive) {
        await ensureAllowance(router, amount);
        const hash = await wc.writeContract({
            address: router,
            abi: PAYMENT_ROUTER_ABI,
            functionName: 'payForItem',
            args: [skuHash(itemId), qty, amount],
            account: me,
            chain: cfg.chain,
        });
        return { kind: 'tx', hash };
    }
    // ─── Path 2: Legacy direct USDC.transfer (Sepolia / pre-router) ─────
    const hash = await wc.writeContract({
        address: cfg.contracts.USDC,
        abi: USDC_ABI,
        functionName: 'transfer',
        args: [cfg.contracts.Treasury, amount],
        account: me,
        chain: cfg.chain,
    });
    return { kind: 'tx', hash };
}
/**
 * Read the connected wallet's USDC balance (in USDC, not base units).
 * Returns `null` when there's no wallet or USDC isn't configured.
 */
export async function readUsdcBalance() {
    const me = walletAddress();
    if (!me)
        return null;
    const cfg = NETWORKS[currentNetwork()];
    if (!cfg.contracts.USDC || cfg.contracts.USDC === ZERO)
        return null;
    const pc = publicClient();
    const raw = await pc.readContract({
        address: cfg.contracts.USDC,
        abi: USDC_ABI,
        functionName: 'balanceOf',
        args: [me],
    });
    return Number(raw) / 1_000_000;
}
