# Build progress tracker

This file is a self-paced loop checkpoint — when context fills up, the next iteration of `/loop` reads this to know what still needs doing.

## Done

- [x] Project scaffolding (`basestriker/` directory tree)
- [x] `TOKENOMICS.md`, `WHITEPAPER.md`, `ROADMAP.md`, top-level `README.md`
- [x] HTML / CSS / Vite config / TS config
- [x] Deterministic RNG (`src/game/rng.ts`)
- [x] 12 enemy species (`src/game/enemies.ts`)
- [x] 10 boss specs + boss FSM (`src/game/boss.ts`)
- [x] 5 ships + 7 weapons (`src/game/ships.ts`)
- [x] Difficulty curve (`src/game/difficulty.ts`)
- [x] 100-level deterministic generator (`src/game/levelgen.ts`)
- [x] Entities, input, renderer (`src/game/{entities,input,render}.ts`)
- [x] Main Game class with fixed-step engine (`src/game/Game.ts`)
- [x] Wallet adapter (`src/web3/wallet.ts`)
- [x] Contract addresses + ABIs (`src/web3/{config,abis,api}.ts`)
- [x] Shop UI (4 tabs)
- [x] Leaderboard UI
- [x] Main app entry (`src/main.ts`)
- [x] `StrikerToken.sol`, `ShipNFT.sol`, `EquipmentNFT.sol`
- [x] `RewardsDistributor.sol` (EIP-712 claim, daily cap, replay protect)
- [x] `GameRegistry.sol` (score submission)
- [x] `PaymentRouter.sol` (ETH / USDC / STRK purchases with TWAP, burn, treasury split)
- [x] `Treasury.sol` (BBB executor, fundRewards)
- [x] `script/Deploy.s.sol` (full stack, all item prices seeded)
- [x] `test/RewardsDistributor.t.sol`
- [x] Backend Express server, EIP-712 signing, leaderboard, nonces, rate limiting
- [x] Sanity verifier for runs
- [x] Docs: `GAME_DESIGN.md`, `ARCHITECTURE.md`, `DEPLOYMENT.md`
- [x] `.env.example` (frontend + backend)
- [x] `scripts/generate-levels.ts`
- [x] Audio: WebAudio 8-bit SFX (`shoot`, `hit`, `explode`, `bomb`, `damage`, `level-clear`, `boss-die`, `connect`) + 13 procedural music tracks (`src/game/audio.ts`)
- [x] Esc-pause / `M` sound toggle / `N` music toggle keybinds in `src/main.ts`
- [x] Audio prime on first user gesture (autoplay-policy compliance)
- [x] Foundry tests for `GameRegistry` (sig, expiry, nonce, owner gating, best-score monotonicity)
- [x] Foundry tests for `PaymentRouter` (ETH/USDC/STRK buy, burn-half, treasury split, item gating, owner-only setItem)
- [x] Foundry tests for `Treasury` (fundRewards, withdraw ETH+ERC20, two-step ownership)
- [x] Daily missions: backend (`/api/missions/:addr`, `/api/missions/claim`), 6 mission templates with deterministic per-day RNG, SQLite progress table, on-run progress aggregation, EIP-712 signed claim → on-chain `RewardsDistributor.claim`
- [x] Daily missions UI panel (`src/ui/missions.ts`) with per-mission progress bar, completion gating, claim button; wired into overlay via new `DAILY MISSIONS` button
- [x] CI · `contracts.yml`: foundry fmt + build + test + snapshot, Slither (fail-on-medium), Mythril advisory (`.github/workflows/contracts.yml`, `contracts/slither.config.json`)
- [x] CI · `frontend.yml`: typecheck + build for game and backend
- [x] `SECURITY.md`: disclosure policy, bug-bounty scale, trust model, automated-check list
- [x] Tournament mode: deterministic 7-level daily set (`backend/src/tournament.ts`), endpoints `today / submit / leaderboard`, SQLite `tournament_runs` table, sanity-checks each per-level run on submit, geometric prize curve
- [x] Tournament UI panel (`src/ui/tournament.ts`), wired into overlay via `TOURNAMENT` button; in-game tournament chaining auto-advances through the 7 levels and POSTs the submission
- [x] PWA: `manifest.webmanifest` (installable, app shortcuts for Tournament/Missions/Shop), `icon.svg` (Galaxian-style hero), service worker (`public/sw.js`) with network-first HTML / cache-first hashed assets / SWR for everything else / API never cached; iOS/Android meta tags and OG tags in `index.html`; SW registered only in prod builds
- [x] Settings panel (`src/ui/settings.ts`): SFX/music toggles, master-volume slider, ship + weapon picker, hotkey reference; persists to `localStorage`, restored on boot; new `SETTINGS` overlay button
- [x] Mobile touch on-screen joystick polish (`src/game/touchControls.ts`): left analog joystick with knob + dead-zone, hold-to-fire button, tap-to-bomb button, pause button; attached only on touch devices; visibility-change cleanup; layered above canvas
- [x] LBP launch tooling: Foundry script `script/DeployLBP.s.sol` (Balancer V2 / Fjord on Base) — sorts tokens, 90/10 → 50/50 weight glide over 48h, INIT-join with treasury seeds, swap-disabled at create, multisig as owner. `docs/LBP_LAUNCH.md` runbook with parameters, price math, T-0/T+48 procedure, failure modes, post-launch checklist.
- [x] Subgraph (`subgraph/`): manifest indexes `GameRegistry`, `RewardsDistributor`, `PaymentRouter`; schema with `Player`/`BestScore`/`ScoreSubmission`/`LevelClear`/`Claim`/`Purchase`/`DailyAggregate`/`GlobalStats`; AssemblyScript mappings for 4 events; package + README with 4 ready-to-use GraphQL queries
- [x] Stripe fiat onramp: `PaymentRouter.setRelayer` + `relayerMintShip` / `relayerMintEquipment` (gated mints w/ external-ref audit trail); backend `stripe.ts` with raw HMAC-SHA256 webhook verification (5-min replay window) and `checkout.session.completed` → on-chain mint via viem walletClient; raw-body middleware in `server.ts` so signature verification survives JSON parsing; deployment runbook section in `docs/DEPLOYMENT.md`
- [x] Discord + X/Twitter OAuth2 PKCE linking (`backend/src/social.ts`): start/callback routes, in-memory state cache (10-min TTL), `social_link` SQLite table (unique on platform+social_id), `GET /api/social/:addr` lookup; `LINK DISCORD` / `LINK X/TWITTER` buttons in settings panel with live status of currently-linked accounts; env vars added to `.env.example`
- [x] PNG icon pipeline: `scripts/generate-icons.mjs` rasterises `icon.svg` via `sharp` into `icon-192.png` / `icon-512.png` / `icon-180.png` (Apple) / `screenshot-1.png` / `og-image.png` (1200×630 social card with centered hero); `npm run gen:icons` + `prebuild` hook (graceful no-op if sharp missing); Apple touch icon + OG image tags in `index.html`
- [x] Headless score-bound verifier (`backend/src/shared/replay.ts`): ports the enemy reward table, intro-level gating, difficulty/density multipliers, and boss reward schedule from the client; computes a deterministic per-level max score and exposes `isRunPlausible` checks (fire-ratio, frame/input drift, kill-to-score ratio); `verify.ts` upgraded to use the new bound instead of a flat `score_per_frame` cap
- [x] Sprite atlas (`src/game/spriteAtlas.ts`): offscreen pre-rendered canvas with all 12 enemy species + 5 ship variants (32×32 cells, glow halos, eyes, highlights); renderer blits via `drawImage` (one call vs many fills per frame) with graceful fallback to the procedural path

## Open (for follow-up iterations)

_All items handled — the build is at v1 scope._

## How to resume work via `/loop`

1. Read this file.
2. Pick the highest-value unchecked item in **Open**.
3. Implement it.
4. Check it off, append a new line under **Done**.
5. If nothing remains, end the loop.

The repo is structured so each open item lives in a single clear directory:
- engine extensions → `src/game/`
- web3 → `src/web3/` and `contracts/`
- backend → `backend/src/`
- docs → `docs/`
