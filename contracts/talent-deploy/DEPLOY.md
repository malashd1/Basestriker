# Deploy guide — BaseStriker on-chain contracts

Three single-file Solidity contracts to deploy on **Base mainnet** (chain ID `8453`). Once deployed and verified on Basescan, plug each address into the Talent Protocol "Smart contracts to track" slots.

| File | What it does | Approx gas (Base) |
|---|---|---|
| `BaseStrikerPaymentRouter.sol` | Routes every USDC shop payment with a typed `ItemPaid` event | ~0.6M gas (~$0.20) |
| `BaseStrikerLeaderboardCheckpoint.sol` | Append-only log of weekly top-100 root hashes | ~0.4M gas (~$0.13) |
| `BaseStrikerBadge.sol` | Soulbound NFT for weekly top-100 players (ERC-721 + ERC-5192) | ~1.0M gas (~$0.33) |

Total cost: **~$0.65 in ETH at current Base gas**. Make sure the deployer wallet has at least **0.001 ETH** on Base.

---

## Prep (5 min)

1. **Wallet on Base mainnet** with ~0.001 ETH for gas. Bridge from Ethereum mainnet via [bridge.base.org](https://bridge.base.org) if empty.
2. **Treasury wallet address** ready: `0xe569A1f798D14809A076ea1c11cb13d698DFcE64` (current basestriker treasury).
3. **Signer wallet address** ready: `0x4aD73779955087673e089B29812e6c1451B8E17b` (backend signer, the one that signs `claim` messages).
4. Open https://remix.ethereum.org and create a new file for each `.sol`. Paste the file contents in.
5. Compile each with **Solidity 0.8.20** (Settings → Compiler → 0.8.20+commit).

---

## 1. BaseStrikerPaymentRouter

**Deploy parameters:**

| Param | Value |
|---|---|
| `_usdc` | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (USDC on Base mainnet) |
| `_treasury` | `0xe569A1f798D14809A076ea1c11cb13d698DFcE64` |

**Steps:**
1. In Remix → Deploy & Run tab → Environment: **Injected Provider - MetaMask** (Base mainnet).
2. Contract dropdown → `BaseStrikerPaymentRouter`.
3. Expand the `Deploy` button, paste the two parameters above.
4. Hit **Deploy** → confirm in MetaMask.
5. Copy the deployed contract address.

**Verify on Basescan:**
1. Go to `https://basescan.org/address/<contractAddress>#code`
2. Click "Verify and Publish"
3. Compiler type: **Solidity (Single file)**
4. Compiler version: **v0.8.20+commit.a1b79de6**
5. Open Source License Type: **MIT**
6. Paste contract code, leave constructor args empty (Basescan auto-detects)
7. Submit → wait ~30s → verified ✓

---

## 2. BaseStrikerLeaderboardCheckpoint

**Deploy parameters:**

| Param | Value |
|---|---|
| `_writer` | `0x4aD73779955087673e089B29812e6c1451B8E17b` (backend signer) |

**Steps:** Identical to PaymentRouter (deploy + verify on Basescan).

**Post-deploy:** The backend needs to call `postCheckpoint(weekId, rowCount, root)` once a week. The implementation is a single backend cron job; not required for Talent verification — the contract itself counts as deployed.

---

## 3. BaseStrikerBadge

**Deploy parameters:**

| Param | Value |
|---|---|
| `_signer` | `0x4aD73779955087673e089B29812e6c1451B8E17b` (backend signer) |
| `_treasury` | `0xe569A1f798D14809A076ea1c11cb13d698DFcE64` |
| `_mintFee` | `100000000000000` (0.0001 ETH in wei — covers Basescan indexing footprint) |

**Steps:** Same flow — deploy via Remix, verify on Basescan with the constructor args.

**Post-deploy:** Players mint after the backend issues a signed payload. Mint flow lives in the `basestriker-badge` repo (frontend integration pending).

---

## After all three are deployed

Put the addresses into the Talent Protocol **"Smart contracts to track"** form:

| Slot | Address (paste after deploy) | Chain |
|---|---|---|
| 1 | `<PaymentRouter address>` | Base mainnet |
| 2 | `<LeaderboardCheckpoint address>` | Base mainnet |
| 3 | `<BaseStrikerBadge address>` | Base mainnet |
| 4 | `0xe569A1f798D14809A076ea1c11cb13d698DFcE64` (treasury EOA) | Base mainnet |
| 5 | `0x4aD73779955087673e089B29812e6c1451B8E17b` (signer EOA) | Base mainnet |

Talent will index:
- **Verified contracts deployed** (3) → +40 % weight in Builder Score
- **Wallet activity** (2 EOAs) → contributes to "consistent on-chain presence" metric
- **`ItemPaid` events** from PaymentRouter → trackable shop revenue stream

---

## Next steps after Talent listing

1. **Switch frontend USDC payments** to call `PaymentRouter.payForItem(sku, qty, amount)` instead of plain `USDC.transfer(treasury, amount)`. This routes new traffic through the contract — every shop purchase becomes a tracked event. Code change: ~10 lines in `src/web3/payments.ts`.
2. **Start posting weekly checkpoints** to LeaderboardCheckpoint. Add a Sunday-midnight cron in the backend that snapshots top-100, computes the root, signs + sends one tx.
3. **Wire up Badge mint UI** — gate at the `/badge` page on `basestriker.xyz`, backend issues the ECDSA payload, frontend calls `BaseStrikerBadge.mint(...)`.

Each of these is a small follow-up that compounds Talent's "ongoing activity" signal.
