// Weekly Top-10 Badge — server-side signing + leaderboard queries.
//
// The on-chain contract BaseStrikerBadgeV2 (Base mainnet) accepts mints
// gated by a signature from the backend `signer` over:
//   keccak256(player, weekId(u64), rank(u32), chainId(u256), contract)
// applied to Ethereum's signed-message envelope:
//   keccak256("\x19Ethereum Signed Message:\n32" + digest)
//
// `eligibleBadges` walks the `leaderboard_weekly` table, picks finished
// weeks where the player landed in top-10, and signs one payload per
// (weekId, rank) so the frontend can hand them straight to the wallet
// for `mint(weekId, rank, sig)`.

import { keccak256, encodePacked, type Address } from 'viem';
import type { PrivateKeyAccount } from 'viem/accounts';
import type Database from 'better-sqlite3';

/// BaseStrikerBadgeV2 — Base mainnet (chain 8453).
export const BADGE_CONTRACT: Address = '0xCf3d1eFd0f0862870d651AC9f40Ed65f76A41435';
export const BADGE_CHAIN_ID = 8453n;
export const BADGE_MAX_RANK = 10;
/// 0.0001 ETH (~$0.21) — must match the value the player sends with mint().
export const BADGE_MINT_FEE_WEI = '100000000000000';

export type BadgeTier = 'GOLD' | 'SILVER' | 'BRONZE' | 'TOP-10';

export function tierFor(rank: number): BadgeTier {
  if (rank === 1) return 'GOLD';
  if (rank === 2) return 'SILVER';
  if (rank === 3) return 'BRONZE';
  return 'TOP-10';
}

/// Week index since Unix epoch (matches the rest of leaderboard math in
/// server.ts: `Math.floor(Date.now() / (7 * 86_400_000))`).
export function currentWeekId(): number {
  return Math.floor(Date.now() / (7 * 86_400_000));
}

export interface LeaderboardRow {
  player: string;
  score: number;
  level: number;
  points: number;
}

export function weeklyTopN(db: Database.Database, weekId: number, n: number): LeaderboardRow[] {
  return db.prepare(`
    SELECT player, score, level, points
    FROM leaderboard_weekly
    WHERE week = ?
    ORDER BY points DESC, score DESC
    LIMIT ?
  `).all(weekId, n) as LeaderboardRow[];
}

/// ECDSA signature over the Badge mint digest. Backend signer wallet
/// (0x4aD737…) signs; the contract `_recover`s the same address and lets
/// the mint proceed.
export async function signBadgeMint(
  account: PrivateKeyAccount,
  player: Address,
  weekId: number,
  rank: number,
): Promise<`0x${string}`> {
  const digest = keccak256(
    encodePacked(
      ['address', 'uint64', 'uint32', 'uint256', 'address'],
      [player, BigInt(weekId), rank, BADGE_CHAIN_ID, BADGE_CONTRACT],
    ),
  );
  return account.signMessage({ message: { raw: digest } });
}

export interface EligibleBadge {
  weekId: number;
  rank: number;
  tier: BadgeTier;
  signature: `0x${string}`;
  contract: Address;
  chainId: number;
  mintFeeWei: string;
  imageUrl: string;
  metaUrl: string;
}

/// Walks every PAST (already-finished) week and signs one payload for
/// each (weekId, rank ≤ 10) the player landed in.
export async function eligibleBadges(
  db: Database.Database,
  account: PrivateKeyAccount,
  player: string,
  apiBase: string,
  publicBase: string,
): Promise<EligibleBadge[]> {
  const cur = currentWeekId();
  const playerLower = player.toLowerCase();

  // Get DISTINCT past weeks where there's any leaderboard data.
  const weeks = db.prepare(`
    SELECT DISTINCT week FROM leaderboard_weekly WHERE week < ? ORDER BY week DESC
  `).all(cur) as Array<{ week: number }>;

  const result: EligibleBadge[] = [];
  for (const { week } of weeks) {
    const top = weeklyTopN(db, week, BADGE_MAX_RANK);
    const idx = top.findIndex(r => r.player.toLowerCase() === playerLower);
    if (idx < 0) continue;
    const rank = idx + 1;
    const sig = await signBadgeMint(account, player as Address, week, rank);
    result.push({
      weekId: week,
      rank,
      tier: tierFor(rank),
      signature: sig,
      contract: BADGE_CONTRACT,
      chainId: 8453,
      mintFeeWei: BADGE_MINT_FEE_WEI,
      imageUrl: `${publicBase}/badges/week-${week}-rank-${rank}.png`,
      metaUrl: `${apiBase}/api/badge/meta/${week}/${rank}`,
    });
  }
  return result;
}
