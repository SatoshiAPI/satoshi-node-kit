#!/usr/bin/env bash
# =============================================================================
# check-uptime.sh — Verify Your Node Uptime Status
# =============================================================================
# Checks your LND node's uptime, channel health, and whether you're meeting
# the 95% uptime requirement for your bonus tier.
#
# Usage:
#   bash scripts/check-uptime.sh
#   bash scripts/check-uptime.sh --json    # output JSON
# =============================================================================

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Config ───────────────────────────────────────────────────────────────────
LND_CONTAINER="lnd"
HUB_PUBKEY="03176f9948d333f9cc1d7d409353f995816e44b3c90a3300b5a08ceba811faf989"
JSON_OUTPUT=false
UPTIME_REQUIREMENT=95

# ── Parse args ────────────────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --json) JSON_OUTPUT=true ;;
    --help|-h)
      echo "Usage: $0 [--json]"
      echo "  --json    Output machine-readable JSON"
      exit 0
      ;;
  esac
done

# ── Banner ───────────────────────────────────────────────────────────────────
if ! $JSON_OUTPUT; then
  echo -e "${BOLD}${YELLOW}⚡ SatoshiAPI Node Uptime Check${NC}\n"
fi

# ── Check LND ────────────────────────────────────────────────────────────────
if ! docker exec "$LND_CONTAINER" lncli --network=mainnet getinfo &>/dev/null 2>&1; then
  if $JSON_OUTPUT; then
    echo '{"status":"error","message":"LND not running or not ready"}'
  else
    error "LND is not running or not ready."
    error "Start with: docker-compose up -d lnd && docker exec -it lnd lncli unlock"
  fi
  exit 1
fi

# ── Get node info ─────────────────────────────────────────────────────────────
NODE_INFO=$(docker exec "$LND_CONTAINER" lncli --network=mainnet getinfo 2>/dev/null)
OWN_PUBKEY=$(echo "$NODE_INFO" | grep '"identity_pubkey"' | sed 's/.*: "\(.*\)".*/\1/')
ALIAS=$(echo "$NODE_INFO" | grep '"alias"' | sed 's/.*: "\(.*\)".*/\1/')
SYNCED=$(echo "$NODE_INFO" | grep '"synced_to_chain"' | grep -o 'true\|false')
BLOCK_HEIGHT=$(echo "$NODE_INFO" | grep '"block_height"' | sed 's/[^0-9]//g')
NUM_ACTIVE_CHANNELS=$(echo "$NODE_INFO" | grep '"num_active_channels"' | sed 's/[^0-9]//g')
NUM_INACTIVE_CHANNELS=$(echo "$NODE_INFO" | grep '"num_inactive_channels"' | sed 's/[^0-9]//g')
NUM_PEERS=$(echo "$NODE_INFO" | grep '"num_peers"' | sed 's/[^0-9]//g')

# ── Get channel list ──────────────────────────────────────────────────────────
CHANNELS=$(docker exec "$LND_CONTAINER" lncli --network=mainnet listchannels 2>/dev/null)
HUB_CHANNELS=$(echo "$CHANNELS" | grep -c "$HUB_PUBKEY" || echo 0)

# ── Get wallet balance ────────────────────────────────────────────────────────
WALLET=$(docker exec "$LND_CONTAINER" lncli --network=mainnet walletbalance 2>/dev/null)
ONCHAIN_BALANCE=$(echo "$WALLET" | grep '"total_balance"' | sed 's/[^0-9]//g' || echo 0)

# ── Container uptime ─────────────────────────────────────────────────────────
CONTAINER_STARTED=$(docker inspect --format='{{.State.StartedAt}}' "$LND_CONTAINER" 2>/dev/null || echo "unknown")
CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' "$LND_CONTAINER" 2>/dev/null || echo "unknown")

# ── Uptime status assessment ──────────────────────────────────────────────────
if [[ "$SYNCED" == "true" && "$CONTAINER_STATUS" == "running" ]]; then
  UPTIME_STATUS="healthy"
else
  UPTIME_STATUS="degraded"
fi

# ── Output ───────────────────────────────────────────────────────────────────
if $JSON_OUTPUT; then
  cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "pubkey": "$OWN_PUBKEY",
  "alias": "$ALIAS",
  "synced_to_chain": $SYNCED,
  "block_height": $BLOCK_HEIGHT,
  "active_channels": $NUM_ACTIVE_CHANNELS,
  "inactive_channels": $NUM_INACTIVE_CHANNELS,
  "hub_channels": $HUB_CHANNELS,
  "peers": $NUM_PEERS,
  "onchain_balance_sats": $ONCHAIN_BALANCE,
  "container_status": "$CONTAINER_STATUS",
  "container_started": "$CONTAINER_STARTED",
  "uptime_status": "$UPTIME_STATUS",
  "uptime_requirement_pct": $UPTIME_REQUIREMENT,
  "hub_pubkey": "$HUB_PUBKEY"
}
EOF
else
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Node alias:        $ALIAS"
  echo "  Pubkey:            ${OWN_PUBKEY:0:20}..."
  echo "  Block height:      $BLOCK_HEIGHT"

  if [[ "$SYNCED" == "true" ]]; then
    echo -e "  Chain sync:        ${GREEN}✓ Synced${NC}"
  else
    echo -e "  Chain sync:        ${RED}✗ Not synced${NC}"
  fi

  if [[ "$CONTAINER_STATUS" == "running" ]]; then
    echo -e "  Container status:  ${GREEN}✓ Running${NC}"
  else
    echo -e "  Container status:  ${RED}✗ $CONTAINER_STATUS${NC}"
  fi

  echo "  Container since:   $CONTAINER_STARTED"
  echo ""
  echo "  Active channels:   $NUM_ACTIVE_CHANNELS"
  echo "  Inactive channels: $NUM_INACTIVE_CHANNELS"
  echo -e "  Hub channels:      $HUB_CHANNELS (to SatoshiAPI)"
  echo "  Peers:             $NUM_PEERS"
  echo "  On-chain balance:  $ONCHAIN_BALANCE sats"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # ── Health assessment ─────────────────────────────────────────────────────
  if [[ "$UPTIME_STATUS" == "healthy" ]]; then
    success "Node is healthy and meets uptime requirements"
  else
    warn "Node health degraded:"
    [[ "$SYNCED" != "true" ]] && warn "  - Not synced to chain"
    [[ "$CONTAINER_STATUS" != "running" ]] && warn "  - Container not running ($CONTAINER_STATUS)"
  fi

  if [[ $NUM_INACTIVE_CHANNELS -gt 0 ]]; then
    warn "$NUM_INACTIVE_CHANNELS inactive channel(s) detected — check connectivity"
  fi

  if [[ $HUB_CHANNELS -eq 0 ]]; then
    warn "No channels to SatoshiAPI hub — run: bash scripts/open-channels.sh"
  else
    success "$HUB_CHANNELS channel(s) open to SatoshiAPI hub"
  fi

  echo ""
  info "For continuous monitoring, run this script periodically or add to cron:"
  info "  */30 * * * * bash $(realpath "${BASH_SOURCE[0]}") --json >> /var/log/satoshi-uptime.log"
fi
