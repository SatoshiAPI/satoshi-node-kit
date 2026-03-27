# ⚠️ SatoshiAPI Clawback Policy

> Plain English. No surprises.

---

## The Short Version

We open inbound channels to your node as a bonus for committing sats to our cluster.

**To keep those channels, you must:**
1. Stay online 95%+ of the time over the first 90 days
2. Keep your channels to our hub open for the full 90 days

If you don't meet these requirements, we may close our inbound channels and reclaim that liquidity. Your original sats are always safe — only our inbound liquidity is at risk.

---

## Why We Have This Policy

Opening inbound channels costs us on-chain fees and locks up our capital. We're investing real sats in your node's success. In exchange, we need reliability.

If nodes could take our inbound liquidity and immediately go offline or close channels, it would drain our routing capital with no benefit to the network.

**This is a mutual commitment.** We bring the inbound. You bring the uptime and stability.

---

## The 90-Day Vesting Period

Think of the first 90 days as a **vesting window**.

```
Day 0:    You open channels → We open inbound channels
Day 1–90: Vesting window — both sides must stay open and online
Day 90:   Fully vested — your inbound channels are yours to keep
After:    Normal Lightning Network rules apply
```

After 90 days, the channels behave like any normal Lightning channel. You can close them whenever you want (with standard Lightning notice). We won't force-close just because the window ended.

---

## When We Trigger a Clawback

We will **force-close our inbound channels** (the ones we opened to you) if:

### 1. Uptime Drops Below 95%

Over any rolling 90-day window, your node must be reachable and online at least 95% of the time.

- **95% = ~131.4 hours** of downtime allowed per 90 days
- Short maintenance windows are fine
- Multi-day outages will trigger review

How we measure:
- Regular Lightning peer probes from our hub
- Channel state monitoring

### 2. You Close Our Required Channels

If you close channels that were required for your tier during the first 90 days, we reserve the right to close our inbound channels in response.

- Closing one channel in a multi-channel tier may trigger partial clawback
- We'll attempt to notify you before taking action when possible

### 3. Abuse or Policy Violation

If we detect channel manipulation, misrepresentation of tier commitment, or other bad-faith actions, channels may be closed immediately.

---

## What Happens When We Force-Close

A force-close is different from a cooperative close.

1. **We broadcast a commitment transaction** to the Bitcoin blockchain
2. **Your funds** (on your side of the channel) are locked for ~144 blocks (~24 hours) due to the CLTV timelock — this is standard Lightning behavior, not a penalty
3. **After ~144 blocks**, your funds are automatically swept to your on-chain wallet
4. **Our inbound liquidity** (our side) returns to us

> 🔑 **Your original sats are never at risk.** Only our inbound liquidity (the bonus we provided) is at stake. We cannot touch your committed sats.

### Timeline After Force-Close

```
Force-close broadcast
         ↓
    ~10 minutes: Transaction confirmed on-chain
         ↓
    ~144 blocks (~24 hours): Your CLTV timelock expires
         ↓
    Your on-chain wallet receives your sats automatically
```

---

## What We Do NOT Clawback

| Scenario | Our Response |
|----------|-------------|
| Brief maintenance (< 4 hours) | No action |
| Hardware upgrade (planned, < 2 days) | No action (contact us first) |
| ISP outage (documented) | Case-by-case |
| Natural disaster / emergency | Reach out — we're human |
| Channels open for 90+ days | No clawback — fully vested |
| You close channels after 90 days | No clawback |

---

## Best Practices to Avoid Clawback

1. **Use a reliable server** — VPS providers like Linode, DigitalOcean, or Hetzner are better than home internet
2. **Set up Docker restart policies** — `restart: unless-stopped` is already set in our docker-compose.yml
3. **Monitor your node** — run `bash scripts/check-uptime.sh` regularly or add to cron
4. **Auto-unlock your wallet** — configure a wallet password file so LND unlocks after restart
5. **Don't close channels** in the first 90 days

---

## Monitoring Your Uptime

```bash
# Quick health check
bash scripts/check-uptime.sh

# JSON output for logging/automation
bash scripts/check-uptime.sh --json

# Add to crontab (every 30 minutes)
*/30 * * * * /path/to/satoshi-node-kit/scripts/check-uptime.sh --json >> /var/log/satoshi-uptime.log
```

---

## Contact Before Problems Arise

If you know you'll have an outage, please reach out proactively. We'd rather work with you than lose a reliable node from the network.

- **API / Status:** https://api.satoshiapi.io
- **GitHub Issues:** https://github.com/SatoshiAPI/satoshi-node-kit/issues

---

## Summary

| Rule | Threshold | Consequence |
|------|-----------|-------------|
| Uptime | < 95% over 90 days | Force-close inbound channels |
| Channel close (within 90d) | Required channels closed | Partial/full inbound clawback |
| After vesting (90+ days) | N/A | No clawback — keep your liquidity |
| Your committed sats | — | Never at risk — always yours |
| CLTV timelock (if force-closed) | ~144 blocks | ~24 hour delay, then auto-swept |

This policy exists to keep the SatoshiAPI routing network healthy, reliable, and profitable for everyone in it. We want you to succeed — and reliable nodes are how that happens.

₿
