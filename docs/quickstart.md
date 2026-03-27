# ⚡ SatoshiAPI Node Kit — Quickstart Guide

> **For non-experts.** Step-by-step from zero to a running Lightning node peered into the SatoshiAPI cluster.

---

## What You'll Need

Before you start, make sure you have:

1. **A computer or VPS** running Linux or macOS
2. **Docker + Docker Compose** installed ([get Docker](https://docs.docker.com/get-docker/))
3. **Bitcoin (sats)** — minimum 500,000 sats (~$500 USD at current prices) to open channels
4. **A reliable internet connection** (95%+ uptime required over 90 days)

**Time required:** ~30–60 minutes to set up. Channel confirmations take ~30 minutes.

---

## Step 1: Install Docker

### On macOS
Download and install [Docker Desktop for Mac](https://docs.docker.com/desktop/install/mac-install/).

### On Ubuntu/Debian
```bash
curl -fsSL https://get.docker.com | bash
sudo usermod -aG docker $USER
# Log out and back in
```

Verify it's working:
```bash
docker --version
docker compose version
```

---

## Step 2: Get the Node Kit

```bash
git clone https://github.com/SatoshiAPI/satoshi-node-kit.git
cd satoshi-node-kit
```

**Or use the one-liner:**
```bash
curl -sSL https://raw.githubusercontent.com/SatoshiAPI/satoshi-node-kit/main/scripts/setup.sh | bash
```

---

## Step 3: Run the Bootstrap Script

```bash
bash scripts/setup.sh
```

This will:
- ✅ Check Docker is installed and running
- ✅ Pull the LND and Tor Docker images
- ✅ Start your node
- ✅ Walk you through wallet creation

> ⏳ First startup may take 5–10 minutes while images download and Neutrino syncs.

---

## Step 4: Create Your Lightning Wallet

When prompted during `setup.sh`, or manually:

```bash
docker exec -it lnd lncli create
```

You'll be asked to:
1. Set a wallet password (remember this — you'll need it to unlock after restart)
2. Generate a new seed phrase **OR** restore from an existing seed

> 🔑 **CRITICAL:** Write down your 24-word seed phrase and store it offline. Losing it = losing your funds.

---

## Step 5: Fund Your On-Chain Address

Get your Bitcoin address to receive funds:

```bash
docker exec -it lnd lncli newaddress p2wkh
```

Example output:
```
{
    "address": "bc1q..."
}
```

Send at least **500,000 sats** (0.005 BTC) to this address from your exchange or wallet.

> 💡 **Tip:** Send a little extra for on-chain fees. Opening a channel costs ~5,000–10,000 sats in fees.

Wait for 1+ blockchain confirmations (~10 minutes). Check balance:
```bash
docker exec -it lnd lncli walletbalance
```

---

## Step 6: Connect to the SatoshiAPI Hub

```bash
bash scripts/peer-connect.sh
```

This connects your node to:
```
03176f9948d333f9cc1d7d409353f995816e44b3c90a3300b5a08ceba811faf989@74.244.146.41:9735
```

Verify:
```bash
docker exec -it lnd lncli listpeers
```

---

## Step 7: Open Channels

Choose your tier based on how many sats you're committing:

| Tier | Sats | Command |
|------|------|---------|
| Seed | 500k–999k | `bash scripts/open-channels.sh --sats 500000` |
| Builder | 1M–4.99M | `bash scripts/open-channels.sh --sats 1000000` |
| Anchor | 5M–9.99M | `bash scripts/open-channels.sh --sats 5000000` |
| Founding | 10M+ | `bash scripts/open-channels.sh --sats 10000000` |

The script will:
- Tell you your tier and expected bonus
- Ask for confirmation before opening
- Open the required number of channels

**Wait for confirmation** (~30 minutes / 3 blocks):
```bash
docker exec -it lnd lncli listchannels
```

Channels are active when `"active": true` appears.

---

## Step 8: Claim Your Bonus

Once channels are confirmed and active:

```bash
bash scripts/claim-bonus.sh
```

This will:
1. Auto-detect your pubkey and open channels
2. Let you confirm your tier
3. Submit a registration request to the SatoshiAPI cluster
4. SatoshiAPI will open inbound channels back to you within 24 hours

> ⚠️ The `/cluster/register` endpoint is coming soon. Your registration will be saved locally and submitted automatically when it launches.

---

## Step 9: Monitor Your Node

```bash
# Check health and uptime status
bash scripts/check-uptime.sh

# View all channels
docker exec -it lnd lncli listchannels

# View on-chain balance
docker exec -it lnd lncli walletbalance

# View channel balance
docker exec -it lnd lncli channelbalance
```

---

## Keeping Your Node Running

Your node must stay online 95%+ of the time over 90 days to keep your bonus.

**If you restart your machine:**
```bash
cd satoshi-node-kit
docker-compose up -d tor lnd
docker exec -it lnd lncli unlock  # Enter your wallet password
```

**Optional: Set up auto-restart**

The `restart: unless-stopped` in docker-compose.yml means Docker will auto-restart containers after a system reboot, but **you still need to unlock the wallet**. Consider using a wallet unlock script with a secured password file.

---

## Troubleshooting

### "LND is not synced"
Neutrino sync can take 5–30 minutes. Check progress:
```bash
docker logs lnd --tail 50
```

### "Cannot connect to peer"
```bash
# Try onion connection
docker exec -it lnd lncli connect \
  03176f9948d333f9cc1d7d409353f995816e44b3c90a3300b5a08ceba811faf989@34ok5fboyoxymwrb3mpynhhfgqkna3addrzmdkdzhibrkkdjokrrmpyd.onion:9735
```

### "Insufficient funds"
Make sure your on-chain wallet has enough balance including fees:
```bash
docker exec -it lnd lncli walletbalance
```

### Channel stuck in "pending"
This is normal — wait for 3 block confirmations (~30 min):
```bash
docker exec -it lnd lncli pendingchannels
```

---

## Useful Commands Reference

```bash
# Node info
docker exec -it lnd lncli getinfo

# List all channels
docker exec -it lnd lncli listchannels

# Pending channels (not yet confirmed)
docker exec -it lnd lncli pendingchannels

# Wallet balance (on-chain)
docker exec -it lnd lncli walletbalance

# Channel balance (Lightning)
docker exec -it lnd lncli channelbalance

# View peers
docker exec -it lnd lncli listpeers

# Container logs
docker logs lnd
docker logs tor

# Stop everything
docker-compose down

# Start everything
docker-compose up -d tor lnd
```

---

## What Happens Next?

After channels are open and confirmed:

1. **SatoshiAPI reviews your registration** (within 24 hours of endpoint launch)
2. **Inbound channels are opened** — your node receives liquidity from the hub
3. **Your node earns routing fees** for payments that flow through it
4. **After 90 days** with 95%+ uptime, your bonus is fully vested

See [bonus-tiers.md](bonus-tiers.md) for full details on what you receive.
See [clawback-policy.md](clawback-policy.md) for what happens if uptime drops.

---

## Need Help?

- **API:** https://api.satoshiapi.io
- **GitHub Issues:** https://github.com/SatoshiAPI/satoshi-node-kit/issues
