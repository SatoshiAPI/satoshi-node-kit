# 💰 SatoshiAPI Cluster Bonus Tiers

> Bring sats. We bring inbound liquidity. Together we build a stronger routing network.

---

## Overview

When you commit sats by opening channels to the SatoshiAPI hub, we reward you with **inbound liquidity** — channels opened from our side back to yours. This gives your node the ability to *receive* Lightning payments, which is what most new nodes lack.

The more you commit, the higher your bonus percentage.

---

## Tier Table

| Tier | Committed Sats | Inbound Bonus | Min Channels | Uptime Req | Vesting |
|------|---------------|---------------|--------------|------------|---------|
| 🌱 **Seed** | 500k – 999k | +10% inbound | 2 channels | 95% / 30d | 30 days |
| 🏗️ **Builder** | 1M – 4.99M | +15% inbound | 3 channels | 95% / 30d | 30 days |
| ⚓ **Anchor** | 5M – 9.99M | +20% inbound | 5 channels | 95% / 30d | 30 days |
| 🏛️ **Founding** | 10M+ | +25% inbound | 6 channels | 95% / 30d | 30 days |

---

## Detailed Tier Breakdown

### 🌱 Seed Tier

**Who it's for:** First-time node operators, individuals testing the network.

| Requirement | Value |
|-------------|-------|
| Minimum commitment | 500,000 sats (0.005 BTC) |
| Maximum commitment | 999,999 sats |
| Inbound bonus | **+10%** |
| Minimum channels | 2 |
| Uptime requirement | 95% over 30 days |
| Vesting period | 30 days |

**Example:**
- You open **2 channels × 250,000 sats** = 500,000 sats committed
- We open **50,000 sats** of inbound liquidity back to you (10%)
- Your node can now receive up to 50,000 sats in Lightning payments

---

### 🏗️ Builder Tier

**Who it's for:** Serious node operators building routing capacity.

| Requirement | Value |
|-------------|-------|
| Minimum commitment | 1,000,000 sats (0.01 BTC) |
| Maximum commitment | 4,999,999 sats |
| Inbound bonus | **+15%** |
| Minimum channels | 3 |
| Uptime requirement | 95% over 30 days |
| Vesting period | 30 days |

**Example:**
- You open **3 channels × 500,000 sats** = 1,500,000 sats committed
- We open **225,000 sats** of inbound liquidity (15%)
- Excellent for merchants and services receiving payments

---

### ⚓ Anchor Tier

**Who it's for:** Infrastructure operators and power users.

| Requirement | Value |
|-------------|-------|
| Minimum commitment | 5,000,000 sats (0.05 BTC) |
| Maximum commitment | 9,999,999 sats |
| Inbound bonus | **+20%** |
| Minimum channels | 5 |
| Uptime requirement | 95% over 30 days |
| Vesting period | 30 days |

**Example:**
- You open **5 channels × 1,200,000 sats** = 6,000,000 sats committed
- We open **1,200,000 sats** of inbound liquidity (20%)
- Significantly improves your routing revenue

---

### 🏛️ Founding Tier

**Who it's for:** Major infrastructure providers, exchanges, liquidity providers.

| Requirement | Value |
|-------------|-------|
| Minimum commitment | 10,000,000 sats (0.1 BTC) |
| Maximum commitment | Unlimited |
| Inbound bonus | **+25%** |
| Minimum channels | 6 |
| Uptime requirement | 95% over 30 days |
| Vesting period | 30 days |

**Example:**
- You open **6 channels × 2,000,000 sats** = 12,000,000 sats committed
- We open **3,000,000 sats** of inbound liquidity (25%)
- Maximum routing capacity and network influence

---

## What "Inbound Bonus" Means

**Outbound liquidity** = sats *you* can send through a channel (your side)
**Inbound liquidity** = sats others can send *to you* through a channel

When you open a channel to us, all the funds start on your side (outbound). Most nodes struggle with inbound liquidity. Our bonus solves this:

```
You open → 1,000,000 sats (outbound to hub)
We open  →   150,000 sats (inbound to you) ← that's your 15% Builder bonus
```

You effectively get extra routing capacity to receive payments at no additional cost.

---

## Tier Upgrade

When your commitment grows past a tier threshold:
- Open additional channels to bring your total past the next threshold
- Run `bash scripts/claim-bonus.sh` again with your updated commitment
- New inbound bonus will be issued at the higher tier rate

---

## Channel Size Recommendations

For best routing performance, we recommend balanced channel sizes:

| Tier | Recommended Channel Size |
|------|--------------------------|
| Seed | 250,000 sats per channel |
| Builder | 350,000–500,000 sats per channel |
| Anchor | 1,000,000+ sats per channel |
| Founding | 2,000,000+ sats per channel |

Minimum channel size enforced by our node: **100,000 sats**

---

## Calculating Your Bonus

```
bonus_sats = committed_sats × bonus_pct / 100

Seed:     500,000 × 10% = 50,000 sats inbound
Builder:  1,000,000 × 15% = 150,000 sats inbound
Anchor:   5,000,000 × 20% = 1,000,000 sats inbound
Founding: 10,000,000 × 25% = 2,500,000 sats inbound
```

**Use the SDK to check eligibility:**
```python
from satoshi_cluster import SatoshiCluster
cluster = SatoshiCluster()
elig = cluster.check_bonus_eligibility(committed_sats=1_000_000, channels_opened=3)
print(f"Bonus: {elig.bonus_sats:,} sats ({elig.bonus_pct}%)")
```

```javascript
import SatoshiCluster from './satoshi-cluster.js';
const cluster = new SatoshiCluster();
const elig = cluster.check_bonus_eligibility({ committedSats: 1_000_000, channelsOpened: 3 });
console.log(`Bonus: ${elig.bonusSats.toLocaleString()} sats (${elig.bonusPct}%)`);
```

---

## Important Notes

- **Vesting:** Bonuses vest over 30 days. See [clawback-policy.md](clawback-policy.md).
- **Uptime:** 95% uptime over 30 days is required. ~1 day of downtime is the max.
- **Channel lifetime:** Do not close channels during the first 30 days.
- **Force-close:** If SatoshiAPI force-closes inbound channels due to policy violation, funds return to your wallet after ~144 block CLTV timeout (~24 hours).
