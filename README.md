# BaseStriker

<div align="center">

![Base](https://img.shields.io/badge/Base-0052FF?style=for-the-badge&logo=coinbase&logoColor=white)
![TypeScript](https://img.shields.io/badge/TypeScript-3178C6?style=for-the-badge&logo=typescript&logoColor=white)
![Vite](https://img.shields.io/badge/Vite-646CFF?style=for-the-badge&logo=vite&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-4cff7a?style=for-the-badge)

**A Galaxian-style retro arcade shooter that pays in USDC on Base.**

[🎮 Play it now](https://basestriker.xyz) · [📱 Mobile app](https://app.basestriker.xyz) · [📜 Terms](https://basestriker.xyz/legal/terms.html) · [🛡 Privacy](https://basestriker.xyz/legal/privacy.html)

</div>

---

## ✨ Features

| Feature | Description |
|---|---|
| 🎮 **100 levels** | 12 enemy types, 10 hand-crafted bosses (every 10th level) |
| 💵 **USDC payments** | Buy in-game boosts on **Base mainnet** — same chain players already hold USDC on |
| 🏆 **Onchain leaderboard** | Per-wallet, anti-cheat verified runs, weekly + lifetime |
| 🎯 **Daily missions** | Rotate per-day, signed-reward claims, 4 mission types |
| ⚡ **No own token** | Just pure USDC for shop purchases — no airdrop farming, no rug risk |
| 📱 **Mobile-friendly** | Adaptive layout, dedicated touch-controls band, install as PWA |
| 🛡 **Anti-cheat** | Replay-bound score verification + signed claim attestations |

## 🎯 How it works

```
   Player                  Backend                     Base mainnet
   ──────                  ───────                     ────────────
   Plays level
   Clears it      ──→  POST /api/run/verify
                       (replay-bound checks)
                       ←──  signed verdict
   Opens shop
   Taps BUY       ──→  USDC.transferChecked → treasury 0xe569A1f7…
                       ←──  on-chain confirmation
   Boost credited
```

No custom contracts to deploy — Base's native USDC SPL transfer is the whole payment stack. **Less than 50 lines of payment code.**

## 🏗 Repo layout

```
basestriker/
├── src/                  # Game client — TypeScript + Canvas 2D
│   ├── game/             # Engine: Player, Enemy, Formation, Boss, Bullet, Particle, Level
│   ├── web3/             # viem wallet + USDC payment helpers
│   ├── ui/               # Menu, shop, leaderboard, settings, missions, legal
│   └── style.css         # 8-bit aesthetic + adaptive mobile layout
├── backend/              # Express API
│   └── src/
│       ├── server.ts     # /api/run/verify, /api/leaderboard, /api/missions/*
│       ├── verify.ts     # Anti-cheat: bound checks + replay plausibility
│       ├── missions.ts   # Daily missions (deterministic per wallet)
│       └── shared/       # Anti-cheat replay bounds (shared with client types)
├── landing/              # Static landing page (basestriker.xyz)
│   └── legal/            # Terms of Use, Privacy Policy, Disclaimer
├── scripts/              # Deploy + ops scripts
└── docs/                 # ARCHITECTURE, DEPLOYMENT, GAME_DESIGN
```

## 🚀 Quickstart

### Prerequisites
- Node 20+ (uses native `fetch`)
- A wallet on Base mainnet with a couple of dollars in USDC (for shop purchases) and ~$0.10 in ETH (for gas)

### Run locally

```bash
# Frontend
npm install
npm run dev                 # http://localhost:5173

# Backend (in another shell)
cd backend
cp .env.example .env        # tweak SIGNER_KEY, CHAIN_ID for your setup
npm install
npm run dev                 # http://localhost:8787
```

### Build for production

```bash
npm run build               # → dist/
cd backend && npm run build # → backend/dist/
```

## 🌐 Live infrastructure

| | URL / Address |
|---|---|
| Landing | https://basestriker.xyz |
| Game (PWA / TWA) | https://app.basestriker.xyz |
| API | https://api.basestriker.xyz |

### On-chain contracts (Base mainnet)

| Contract | Address |
|---|---|
| [`BaseStrikerPaymentRouter`](contracts/talent-deploy/BaseStrikerPaymentRouter.sol) | [`0xc08bda33E32Da9255f21BB57afF78e6d1EAb6789`](https://basescan.org/address/0xc08bda33E32Da9255f21BB57afF78e6d1EAb6789) |
| [`BaseStrikerLeaderboardCheckpoint`](contracts/talent-deploy/BaseStrikerLeaderboardCheckpoint.sol) | [`0xAdBD63254aaF3836cE8295E3E39B3B3f25aF1219`](https://basescan.org/address/0xAdBD63254aaF3836cE8295E3E39B3B3f25aF1219) |
| [`BaseStrikerBadgeV2`](contracts/talent-deploy/BaseStrikerBadgeV2.sol) (Top-10 SBT, dynamic tokenURI) | [`0xCf3d1eFd0f0862870d651AC9f40Ed65f76A41435`](https://basescan.org/address/0xCf3d1eFd0f0862870d651AC9f40Ed65f76A41435) |
| Treasury (USDC recipient EOA) | [`0xe569A1f798D14809A076ea1c11cb13d698DFcE64`](https://basescan.org/address/0xe569A1f798D14809A076ea1c11cb13d698DFcE64) |
| Backend signer EOA (claims) | [`0x4aD73779955087673e089B29812e6c1451B8E17b`](https://basescan.org/address/0x4aD73779955087673e089B29812e6c1451B8E17b) |

USDC on Base: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (6 decimals).

## 🎮 Scoring & economy

**Score** is linear — each enemy kill is worth its flat `ENEMY_REWARDS[kind]` value:

```
grunt 10 · drone 15 · scout 25 · sniper 40 · bomber 55
splitter 60 · phantom 75 · swarmer 35 · turret 100
reaper 120 · mirror 150 · voidling 180
```

Bosses pay 1 000 → 100 000 across LV10 → LV100. No combo multiplier, no level multiplier, no shop-booster amplification — clean math, clear ceilings.

**Lifetime POINTS** (separate from per-run score, persists across deaths) come from exactly three sources:
1. Level clears (5–80 PTS per level, scales with difficulty)
2. Shop purchases (300 PTS per $1 USDC spent)
3. The "+100" bonus-score loot drop (flat 5 PTS)

POINTS are an in-game currency — **not a token, not redeemable**.

## 🛡 Anti-cheat

Per-run plausibility checks live in [`backend/src/shared/replay.ts`](backend/src/shared/replay.ts):

- Score must be ≤ cumulative `Σ maxScoreFor(LV)` for levels played
- Kills must be ≥ `(score − bossReward) / bestReward × 0.8` (proportional to score)
- Frame count must match recorded inputs within 4 frames (60 Hz)
- Non-zero score with zero fire inputs is impossible

A signed claim message is generated server-side after verification — the client cannot mint POINTS or move on the leaderboard without a valid backend signature.

## 🗺 Roadmap

See [ROADMAP.md](ROADMAP.md). Highlights:
- Farcaster Frame — "Play BaseStriker" embed in casts
- Soulbound badge NFT on Base for weekly top-100 (rotating)
- Coinbase Wallet "Discover" tab submission
- Smart Wallet (paymaster-sponsored) optional connect

Companion repos:
- [basestriker-frame](https://github.com/malashd1/basestriker-frame) — Farcaster Frame
- [basestriker-sdk](https://github.com/malashd1/basestriker-sdk) — Read-only leaderboard SDK
- [basestriker-badge](https://github.com/malashd1/basestriker-badge) — Soulbound NFT contract
- [cosmic-seeker](https://github.com/malashd1/cosmic-seeker) — Solana Seeker variant of the same engine

## 📜 Legal

- [Terms of Use](https://basestriker.xyz/legal/terms.html)
- [Privacy Policy](https://basestriker.xyz/legal/privacy.html)
- [Disclaimer](https://basestriker.xyz/legal/disclaimer.html)

## 📄 License

MIT — see [LICENSE](LICENSE).

Contact: dima@chisoft.co
