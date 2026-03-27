#!/usr/bin/env bash
# =============================================================================
# setup.sh — SatoshiAPI Cluster Node Kit Bootstrap
# =============================================================================
# One-command bootstrap: checks prerequisites, starts LND, creates wallet,
# connects to SatoshiAPI hub peers, and guides through next steps.
#
# Usage:
#   bash setup.sh
#   # or via curl:
#   curl -sSL https://raw.githubusercontent.com/SatoshiAPI/satoshi-node-kit/main/scripts/setup.sh | bash
#
# What this does:
#   1. Checks for Docker + Docker Compose
#   2. Pulls required images
#   3. Starts LND + Tor containers
#   4. Waits for LND to be ready
#   5. Guides wallet creation
#   6. Prints your on-chain funding address
#   7. Reminds you to connect peers + open channels
#
# What this does NOT do:
#   - Move any funds
#   - Open channels (run open-channels.sh after funding)
#   - Register for bonus (run claim-bonus.sh after channels are open)
# =============================================================================

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Constants ────────────────────────────────────────────────────────────────
SATOSHI_PUBKEY="03176f9948d333f9cc1d7d409353f995816e44b3c90a3300b5a08ceba811faf989"
SATOSHI_CLEARNET="74.244.146.41:9735"
LND_CONTAINER="lnd"
COMPOSE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docker-compose.yml"

# ── Helpers ──────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }
header()  { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}\n"; }

# ── Banner ───────────────────────────────────────────────────────────────────
echo -e "${BOLD}${YELLOW}"
cat << 'EOF'
  ⚡ SatoshiAPI Cluster Node Kit
  ─────────────────────────────
  Join the Agent Network. Stack sats.
EOF
echo -e "${NC}"

# ── Step 1: Check prerequisites ──────────────────────────────────────────────
header "Step 1: Checking Prerequisites"

# Check Docker
if ! command -v docker &>/dev/null; then
  die "Docker not found. Install Docker Desktop: https://docs.docker.com/get-docker/"
fi
success "Docker found: $(docker --version)"

# Check Docker Compose (v2 or v1)
if docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
  success "Docker Compose v2 found"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
  success "Docker Compose v1 found"
else
  die "Docker Compose not found. Install via: https://docs.docker.com/compose/install/"
fi

# Check Docker daemon is running
if ! docker info &>/dev/null; then
  die "Docker daemon is not running. Start Docker Desktop and try again."
fi
success "Docker daemon is running"

# Check compose file exists
if [[ ! -f "$COMPOSE_FILE" ]]; then
  die "docker-compose.yml not found at $COMPOSE_FILE — are you running from the repo root?"
fi
success "docker-compose.yml found"

# ── Step 2: Pull images ──────────────────────────────────────────────────────
header "Step 2: Pulling Docker Images"
info "This may take a few minutes on first run..."

cd "$(dirname "$COMPOSE_FILE")"
$COMPOSE_CMD pull lnd tor
success "Images pulled"

# ── Step 3: Start LND + Tor ──────────────────────────────────────────────────
header "Step 3: Starting LND + Tor"

$COMPOSE_CMD up -d tor lnd
success "Containers started"

# ── Step 4: Wait for LND to be ready ────────────────────────────────────────
header "Step 4: Waiting for LND"

info "LND is syncing and starting up (this can take 2–5 minutes for Neutrino sync)..."
MAX_WAIT=120
WAIT_INTERVAL=5
elapsed=0

while (( elapsed < MAX_WAIT )); do
  if docker exec "$LND_CONTAINER" lncli --network=mainnet state 2>/dev/null | grep -q "RPC_ACTIVE\|SERVER_ACTIVE\|WAITING_TO_START"; then
    success "LND is responding"
    break
  fi
  echo -n "."
  sleep $WAIT_INTERVAL
  (( elapsed += WAIT_INTERVAL ))
done

if (( elapsed >= MAX_WAIT )); then
  warn "LND hasn't fully started yet (this is normal on first run)."
  warn "Run 'docker logs lnd' to check progress."
  warn "Once ready, run: docker exec -it lnd lncli create"
fi

# ── Step 5: Wallet setup ─────────────────────────────────────────────────────
header "Step 5: Wallet Setup"

echo -e "${YELLOW}You need to create (or unlock) your LND wallet.${NC}"
echo ""
echo "  To CREATE a new wallet:"
echo "    docker exec -it lnd lncli create"
echo ""
echo "  To RESTORE an existing wallet:"
echo "    docker exec -it lnd lncli create  (choose option 2 for seed restore)"
echo ""
echo "  To UNLOCK an existing wallet:"
echo "    docker exec -it lnd lncli unlock"
echo ""

read -rp "Would you like to create/unlock your wallet now? [y/N] " answer
if [[ "${answer,,}" == "y" ]]; then
  echo ""
  info "Launching wallet creation. Follow the prompts carefully and BACKUP YOUR SEED."
  docker exec -it "$LND_CONTAINER" lncli create || warn "Wallet creation exited — run manually: docker exec -it lnd lncli create"
else
  warn "Skipping wallet setup. Run manually: docker exec -it lnd lncli create"
fi

# ── Step 6: Get funding address ──────────────────────────────────────────────
header "Step 6: Get Your Funding Address"

if docker exec "$LND_CONTAINER" lncli --network=mainnet getinfo &>/dev/null 2>&1; then
  ADDR=$(docker exec "$LND_CONTAINER" lncli newaddress p2wkh 2>/dev/null | grep '"address"' | sed 's/.*"address": "\(.*\)".*/\1/' || echo "")
  if [[ -n "$ADDR" ]]; then
    success "Your LND on-chain address:"
    echo -e "\n  ${BOLD}${GREEN}$ADDR${NC}\n"
    echo "  Fund this address with sats to open channels."
    echo "  Minimum: 500,000 sats (Seed tier)"
  else
    warn "Could not get address yet. After wallet creation run:"
    warn "  docker exec -it lnd lncli newaddress p2wkh"
  fi
else
  warn "LND not yet ready. After wallet creation + sync, run:"
  warn "  docker exec -it lnd lncli newaddress p2wkh"
fi

# ── Step 7: Summary & next steps ─────────────────────────────────────────────
header "Setup Complete — Next Steps"

echo -e "${BOLD}1. Fund your on-chain address${NC} (500k sats minimum)"
echo ""
echo -e "${BOLD}2. Connect to the SatoshiAPI hub:${NC}"
echo "   bash scripts/peer-connect.sh"
echo ""
echo -e "${BOLD}3. Open channels:${NC}"
echo "   bash scripts/open-channels.sh"
echo ""
echo -e "${BOLD}4. Claim your inbound liquidity bonus:${NC}"
echo "   bash scripts/claim-bonus.sh"
echo ""
echo -e "${BOLD}5. Monitor uptime:${NC}"
echo "   bash scripts/check-uptime.sh"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Hub: ${SATOSHI_PUBKEY:0:16}...@${SATOSHI_CLEARNET}"
echo " API: https://api.satoshiapi.io"
echo " Docs: docs/quickstart.md"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
success "Bootstrap complete. Stack those sats. ₿"
