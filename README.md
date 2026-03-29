# ⚡ SatoshiAPI Cluster Node Kit

> Join the SatoshiAPI Agent Network in one command. You bring the sats — we bring the inbound liquidity.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Lightning Network](https://img.shields.io/badge/Lightning-Network-orange)](https://lightning.network)
[![LND](https://img.shields.io/badge/LND-mainnet-blue)](https://github.com/lightningnetwork/lnd)

---

## 🚀 One-Command Quickstart

```bash
curl -sSL https://raw.githubusercontent.com/SatoshiAPI/satoshi-node-kit/main/scripts/setup.sh | bash
```

> **Prerequisites:** Docker + Docker Compose installed. You'll need Bitcoin (sats) to fund channels.

---

## 🎯 What Is This?

The SatoshiAPI Cluster Node Kit bootstraps your LND node and connects it to the **SatoshiAPI Agent Network** — a Lightning cluster powering agent-to-agent commerce, L402 micropayments, and AI-native services.

### What You Bring
- ✅ A machine to run LND (Linux/macOS/Windows via WSL2/VPS)
- ✅ Docker + Docker Compose
- ✅ Sats to fund channels (500k minimum)
- ✅ Reliable uptime (95%+ over 90 days)

> **Windows users:** See [docs/windows-setup.md](docs/windows-setup.md) for WSL2 + Docker setup guide.

### What We Provide
- ✅ Inbound liquidity bonus (10%–25% of your commitment)
- ✅ Peering with our hub node
- ✅ Access to the SatoshiAPI Agent Network routing
- ✅ L402 payment infrastructure

---

## 💰 Bonus Tiers

| Tier | Sats Committed | Inbound Bonus | Min Channels | Uptime Req |
|------|---------------|---------------|--------------|------------|
| 🌱 **Seed** | 500k – 999k | +10% inbound | 2 channels | 95% / 90d |
| 🏗️ **Builder** | 1M – 4.99M | +15% inbound | 3 channels | 95% / 90d |
| ⚓ **Anchor** | 5M – 9.99M | +20% inbound | 5 channels | 95% / 90d |
| 🏛️ **Founding** | 10M+ | +25% inbound | 6 channels | 95% / 90d |

**Example:** Commit 1M sats as Builder → receive 150k sats of inbound liquidity from us.

> ⚠️ **Clawback Policy:** Inbound channels may be force-closed if uptime drops below 95% or required channels close within the first 90 days. See [docs/clawback-policy.md](docs/clawback-policy.md).

---

## 🌐 SatoshiAPI Hub Node

```
Pubkey:   03176f9948d333f9cc1d7d409353f995816e44b3c90a3300b5a08ceba811faf989
Clearnet: 74.244.146.41:9735
Onion:    34ok5fboyoxymwrb3mpynhhfgqkna3addrzmdkdzhibrkkdjokrrmpyd.onion:9735
```

---

## 📁 Repository Structure

```
satoshi-node-kit/
├── README.md               ← You are here
├── LICENSE                 ← MIT
├── docker-compose.yml      ← LND + Tor + optional bitcoind
├── lnd/
│   └── lnd.conf            ← Pre-baked mainnet LND config
├── scripts/
│   ├── setup.sh            ← One-command bootstrap
│   ├── peer-connect.sh     ← Connect to SatoshiAPI hub peers
│   ├── open-channels.sh    ← Open channels to the cluster
│   ├── check-uptime.sh     ← Verify your uptime status
│   └── claim-bonus.sh      ← Register for inbound liquidity bonus
├── config/
│   └── peers.json          ← Hub peer list
├── sdk/
│   ├── python/             ← Python SDK (SatoshiCluster class)
│   └── js/                 ← JavaScript SDK (ESM)
└── docs/
    ├── quickstart.md       ← Step-by-step guide for non-experts
    ├── windows-setup.md    ← Windows 10/11 WSL2 + Docker guide
    ├── firewall-ports.md   ← Required ports, CGNAT solutions
    ├── bonus-tiers.md      ← Full tier details with examples
    └── clawback-policy.md  ← 90-day vesting / clawback explained
```

---

## 🛠️ Manual Setup

### 1. Clone & Configure
```bash
git clone https://github.com/SatoshiAPI/satoshi-node-kit.git
cd satoshi-node-kit
```

### 2. Start LND
```bash
docker compose up -d lnd tor
```

### 3. Create Wallet

> ⚠️ **Interactive terminal required.** `lncli create` needs a TTY for the seed display and password prompt. This does NOT work when piped from `curl | bash` or over SSH without the `-t` flag. Use: `ssh -t user@host "docker exec -it lnd lncli create"`

```bash
docker exec -it lnd lncli create
```

### 4. Fund & Connect
```bash
# Get your on-chain address
docker exec -it lnd lncli newaddress p2wkh

# Once funded, connect to the hub
bash scripts/peer-connect.sh

# Open channels
bash scripts/open-channels.sh
```

### 5. Claim Your Bonus
```bash
bash scripts/claim-bonus.sh
```

---

## 🔗 Links

- **API:** https://api.satoshiapi.io
- **MCP Endpoint:** https://api.satoshiapi.io/mcp
- **Docs:** [docs/quickstart.md](docs/quickstart.md)
- **Windows Setup:** [docs/windows-setup.md](docs/windows-setup.md)
- **Firewall & Ports:** [docs/firewall-ports.md](docs/firewall-ports.md)
- **Bonus Tiers:** [docs/bonus-tiers.md](docs/bonus-tiers.md)
- **Clawback Policy:** [docs/clawback-policy.md](docs/clawback-policy.md)

---

## 📄 License

MIT © 2026 SatoshiAPI — See [LICENSE](LICENSE)
