# BaseStriker Subgraph

Indexes `GameRegistry`, `RewardsDistributor`, and `PaymentRouter` events for fast leaderboard reads, player profiles, and treasury dashboards.

## Entities

- `Player` — wallet aggregate (highest level, total score, life-time STRK claimed/spent, ETH/USDC spend).
- `BestScore` — per-player-per-level best score, lookup by `${player}-${level}`.
- `ScoreSubmission` / `LevelClear` / `Claim` / `Purchase` — append-only event tables.
- `DailyAggregate` — per-day totals for emission dashboards.
- `GlobalStats` — running counters (total players, claims, burns).

## Quick queries

### Top 100 players by lifetime score

```graphql
{
  players(orderBy: totalScore, orderDirection: desc, first: 100) {
    id
    highestLevelCleared
    totalScore
    totalStrkClaimed
  }
}
```

### Per-level leaderboard

```graphql
{
  bestScores(where: { level: 100 }, orderBy: score, orderDirection: desc, first: 100) {
    player { id }
    score
    updatedAt
  }
}
```

### A single player profile

```graphql
{
  player(id: "0xabc...") {
    highestLevelCleared
    totalScore
    totalStrkClaimed
    totalSpentEth
    totalSpentUsdc
    totalSpentStrk
    itemsPurchased
    bestScores(orderBy: level) { level score }
  }
}
```

### Emission dashboard

```graphql
{
  dailyAggregates(orderBy: epoch, orderDirection: desc, first: 30) {
    epoch
    totalClaimed
    uniqueClaimers
    totalPurchases
  }
  globalStats(id: "global") {
    totalPlayers
    totalClaimed
    totalStrkBurned
  }
}
```

## Build + deploy

```bash
cd subgraph
npm install
# After contracts are deployed, fill addresses + startBlock in subgraph.yaml.
# Also copy ABIs:
mkdir -p abis
cp ../contracts/out/GameRegistry.sol/GameRegistry.json abis/GameRegistry.json
cp ../contracts/out/RewardsDistributor.sol/RewardsDistributor.json abis/RewardsDistributor.json
cp ../contracts/out/PaymentRouter.sol/PaymentRouter.json abis/PaymentRouter.json

npm run codegen
npm run build

# Deploy to The Graph Studio (preferred for Base):
npm run deploy:studio
```

## Cost / scale

Base produces ~2s blocks. Even at 10k daily transactions across our 3 contracts, indexing keeps up trivially. The subgraph is the recommended fallback for the in-game leaderboard if the backend goes down — the frontend can switch the `leaderboard.ts` data source to the subgraph URL with no other changes.
