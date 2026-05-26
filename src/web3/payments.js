// USDC payment helper — used by the shop and the settings ship/weapon
// catalogue.
//
// BaseStriker doesn't have its own token or contracts. Players pay for
// upgrades by sending USDC directly from their wallet to the treasury
// wallet via the standard ERC-20 `transfer` function. That's it.
//
// Behaviour matrix (mirrors cosmic-seeker/skr.ts on the Solana side):
//   - No wallet              → returns { kind: 'no-wallet' }
//   - Treasury / USDC unset  → returns { kind: 'no-config' }
//   - Wrong chain            → walletClient.switchChain first; if that
//                              fails (user declines), returns 'no-config'
//   - Buyer has < amount     → wallet throws; caller surfaces error
//   - Happy path             → returns { kind: 'tx', hash }
import { parseUnits } from 'viem';
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
const ZERO = '0x0000000000000000000000000000000000000000';
/**
 * Send `priceUsd × qty` USDC from the connected wallet to the treasury.
 *
 * `priceUsd` is a dollar amount (1 = one USDC, 0.5 = fifty cents). We
 * convert to 6-decimal base units before calling `transfer`.
 */
export async function payUsdc(priceUsd, qty) {
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
    // Make sure the wallet is on the right chain before signing — viem will
    // throw a confusing "chain mismatch" otherwise. Best-effort switch; if
    // the wallet declines, the actual writeContract call will surface the
    // exact reason to the user.
    try {
        const current = await wc.getChainId();
        if (current !== cfg.chain.id) {
            await wc.switchChain({ id: cfg.chain.id });
        }
    }
    catch (e) {
        console.warn('[pay] chain switch declined / failed', e);
    }
    // Pre-flight balance check — MetaMask's revert preview ("ERC20: transfer
    // amount exceeds balance") is confusing for non-crypto players. We catch
    // the same condition client-side and throw a friendlier message that the
    // shop's try/catch surfaces in the BUY button.
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
        // Re-throw insufficient-balance; swallow other RPC errors (network blip,
        // RPC down) so the real `transfer` still gets a chance.
        if (String(e?.message ?? '').startsWith('Need '))
            throw e;
        console.warn('[pay] balance pre-check failed (continuing anyway)', e);
    }
    const hash = await wc.writeContract({
        address: cfg.contracts.USDC,
        abi: USDC_ABI,
        functionName: 'transfer',
        args: [cfg.contracts.Treasury, amount],
        account: me,
        chain: cfg.chain,
    });
    // Don't block the UI on the receipt — the wallet already submitted the
    // tx and the user has the hash. The optional `waitForTransactionReceipt`
    // is a nice-to-have but adds 1–15 s of "Confirming…" the player doesn't
    // really need on a games-shop checkout.
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
