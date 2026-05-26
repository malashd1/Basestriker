# Deployment

## Environments

| Env | Chain | Purpose |
|---|---|---|
| local | Anvil | `forge test`, `npm run dev` |
| testnet | Base Sepolia (84532) | Closed beta, audits, dry runs |
| mainnet | Base (8453) | Production |

## Prereqs

- Node 20+
- Foundry (`curl -L https://foundry.paradigm.xyz | bash; foundryup`)
- A funded deployer EOA on Base Sepolia and Base
- A Basescan API key
- A backend signer key (KMS in production, env var in dev)

## Smart contracts

```bash
cd contracts
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts
forge test -vv
```

Set env:

```bash
export DEPLOYER_PK=0x...
export BACKEND_SIGNER=0xYourSignerAddress
export BASE_RPC_URL=https://mainnet.base.org
export BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
export BASESCAN_API_KEY=...
```

Deploy to Sepolia:

```bash
forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify -vv
```

Capture printed addresses → copy them into `basestriker/.env.local`:

```ini
VITE_DEFAULT_NETWORK=baseSepolia
VITE_STRK_ADDR_TEST=0x...
VITE_SHIP_ADDR_TEST=0x...
VITE_EQUIP_ADDR_TEST=0x...
VITE_REGISTRY_ADDR_TEST=0x...
VITE_PAYMENT_ADDR_TEST=0x...
VITE_REWARDS_ADDR_TEST=0x...
VITE_TREASURY_ADDR_TEST=0x...
VITE_BACKEND_URL_TEST=https://api.basestriker.xyz
```

Fund the `RewardsDistributor` from the `Treasury` (40% of supply = 400M STRK).

## Backend

```bash
cd backend
npm install
cp .env.example .env
# edit SIGNER_KEY (or wire KMS), REWARDS_CONTRACT, REGISTRY_CONTRACT, CHAIN_ID
npm run dev
```

For production, run behind a reverse proxy (Caddy / Nginx) with HTTPS and tighten the rate limiter. Use a managed KMS (AWS, GCP, or HashiCorp Vault) instead of a local hex key.

## Frontend

```bash
cd basestriker
npm install
npm run dev   # http://localhost:5173
npm run build # builds to dist/
```

For production deploy `dist/` to a static host (Cloudflare Pages, Vercel). The frontend only needs the contract addresses and backend URL — no secrets.

## Stripe fiat onramp

Once the contracts are deployed, the backend can mint NFTs paid by credit card.

1. Create a Stripe account, obtain `STRIPE_SECRET_KEY` and a webhook signing secret `STRIPE_WEBHOOK_SECRET`.
2. Generate (or reuse) a relayer EOA. Authorise it on the router:

   ```bash
   cast send $PAYMENT_ROUTER 'setRelayer(address,bool)' $RELAYER_ADDR true \
     --rpc-url $BASE_RPC_URL --account multisig
   ```

3. Set backend env:

   ```ini
   STRIPE_SECRET_KEY=sk_live_...
   STRIPE_WEBHOOK_SECRET=whsec_...
   RELAYER_KEY=0x...           # or wire to KMS
   PAYMENT_ROUTER=0x...
   CHAIN_ID=8453
   RPC_URL=https://mainnet.base.org
   ```

4. Configure the Stripe webhook endpoint at `https://api.basestriker.xyz/api/stripe/webhook`, listening for `checkout.session.completed`.
5. Test the full flow on Stripe test mode + Base Sepolia before flipping to live.

Frontend flow:

```ts
const r = await fetch('/api/stripe/checkout', {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({
    wallet: '0xabc...',
    itemKind: 'ship',
    tier: 2,
    priceUsdCents: 1500,
    successUrl: 'https://app/?ok=1',
    cancelUrl:  'https://app/?ok=0',
  }),
});
const { url } = await r.json();
location.href = url;
```

## Mainnet checklist

- [ ] Both audits passed; report public
- [ ] Bug bounty active (Immunefi / Code4rena) for 30 days pre-launch
- [ ] Multisig (Safe) owns Token, Treasury, Rewards, Registry, PaymentRouter, both NFTs
- [ ] Timelock (7-day) wraps ownership of Token / Treasury
- [ ] Aerodrome `STRK/USDC` pool seeded with locked LP
- [ ] Paymaster gas-credits topped up to cover 30 days of estimated claims
- [ ] Backend signer KMS provisioned, key never present in cleartext
- [ ] Leaderboard reset cadence configured (weekly cron)
- [ ] Stripe → ETH onramp test-flowed
- [ ] LBP price discovery curve agreed with market maker (if any)

## Day-0 runbook

1. Deploy contracts (above).
2. Multisig accepts ownership transfers (`acceptOwnership()` on each Ownable2Step contract).
3. Multisig calls `treasury.fundRewards(rewards, 400_000_000 ether)`.
4. Multisig calls `treasury.fundRewards(<airdrop_distributor>, 150_000_000 ether)`.
5. Aerodrome LP create: pair STRK/USDC, deposit 150M STRK + treasury USDC, lock LP.
6. Set `PaymentRouter.twap` to Aerodrome quoter.
7. Backend signer authorised at `RewardsDistributor.setSigner(kmsAddr)` and `GameRegistry.setSigner(kmsAddr)`.
8. Flip `RewardsDistributor.setPaused(false)` (if launched paused).
9. Announce TGE.
