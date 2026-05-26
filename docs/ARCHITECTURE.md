# Architecture

## System diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         Player Browser                          │
│  ┌───────────────┐   ┌──────────────────┐   ┌────────────────┐  │
│  │  Game (TS)    │   │  Wallet (wagmi)  │   │  Shop / UI     │  │
│  │  Canvas 480×640│  │  Smart Wallet    │   │                │  │
│  │  60Hz fixed   │   │  Injected EIP-1193│  │                │  │
│  └──────┬────────┘   └──────┬───────────┘   └──────┬─────────┘  │
└─────────┼───────────────────┼──────────────────────┼────────────┘
          │                   │                      │
          │ POST /run/verify  │ EIP-1193 sign/send   │ HTTP
          ▼                   ▼                      ▼
┌──────────────────────────────────────┐   ┌────────────────────────┐
│            Backend (Node)            │   │      Base mainnet      │
│  • Sanity-checks RunResult           │   │  StrikerToken (ERC-20) │
│  • EIP-712 signs claim attestation   │   │  ShipNFT  (ERC-721)    │
│  • Maintains weekly leaderboard      │   │  EquipNFT (ERC-1155)   │
│  • Issues nonces                     │   │  GameRegistry          │
│  • SQLite                            │   │  PaymentRouter         │
└────────┬─────────────────────────────┘   │  RewardsDistributor    │
         │                                 │  Treasury              │
         │ Off-chain only — no chain TXs   │  Aerodrome STRK/USDC   │
         │                                 └─────────┬──────────────┘
         │                                           │
         └──────────────────────────────────► RPC ◄──┘
```

## Trust model

| Component | What it trusts | What trusts it |
|---|---|---|
| Game (client) | Nothing | Nothing — client is untrusted by design |
| Backend signer | Deterministic replay of run | Rewards/Registry contracts |
| Rewards/Registry | EIP-712 sig from backend signer key | Players (they get tokens) |
| Treasury | Owner multisig (Safe) | Rewards pool (funded from treasury) |
| Token | Nothing (immutable ERC-20) | Everyone |

The single trust apex is the backend signer key. Compromise of that key drains the rewards pool up to the dailyCap × number of distinct wallets. Mitigations:
- Daily cap (2k STRK / wallet) limits blast radius.
- Signer rotation is owner-gated and operational.
- Signer key is a Cloud KMS HSM in production. The local dev key (in `.env`) is well-known and not authorised on mainnet.

## Determinism (replay)

Run seed: `seed = keccak256(playerAddress.toLowerCase(), levelId, dailyEpoch)`.
The same seed + the same input frame stream produces the same game state and score on any machine. Backend has the engine bundled, runs `runHeadless(seed, inputs)`, and compares the returned score to the claimed one. Tolerance is ±0 because the engine is integer-stepped.

The backend's verifier currently runs only the sanity layer; the full replay verifier is a build-time goal (sharing the engine via `npm workspaces`).

## Why this layering

- **Score logic on backend, not on chain.** Putting per-frame replay on chain is prohibitive (gas + state). EIP-712 signed attestation is the standard pattern.
- **Game determinism for free anti-cheat.** Players cannot fake a high score because the same inputs produce the same score on the server.
- **Daily caps on chain, not off chain.** Off-chain caps can be bypassed by rotating IPs; on-chain caps cannot (the contract has authoritative state).
- **Burn happens on chain.** All `$STRK` sinks burn through `burnFrom` on the token contract, visible on Basescan.

## Smart Wallet UX

When the user has a passkey-based Coinbase Smart Wallet:
- First-touch onboarding: passkey, no seed phrase.
- All gas can be sponsored via paymaster (Base Builder credits). Players never need ETH.
- Approvals for USDC and STRK can be batched with the buy call (Smart Wallet `wallet_sendCalls`).

When the user has a classic EOA (MetaMask etc):
- Standard flow. They need ETH on Base to pay gas.
- We do not subsidise gas for EOA users by default. (Configurable.)

## File map (key entry points)

| Path | Purpose |
|---|---|
| `src/main.ts` | App boot, wires UI, game, wallet |
| `src/game/Game.ts` | Fixed-step engine, collision, scoring |
| `src/game/levelgen.ts` | Deterministic level generator |
| `src/game/enemies.ts` | 12 enemy specs, 10 boss specs |
| `src/game/boss.ts` | Boss state machines |
| `src/web3/wallet.ts` | Wallet connection |
| `src/web3/api.ts` | Read/write helpers, claim flow |
| `contracts/src/RewardsDistributor.sol` | EIP-712 claim |
| `contracts/src/PaymentRouter.sol` | Buy ship/equipment in ETH/USDC/STRK |
| `backend/src/server.ts` | Express routes |
| `backend/src/verify.ts` | Run sanity verification |
