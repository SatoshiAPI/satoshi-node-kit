#!/usr/bin/env bash
# =============================================================================
# peer-connect.sh — Connect to SatoshiAPI Hub Peers
# =============================================================================
# Reads peers from config/peers.json and connects your LND node to each hub.
# Tries clearnet first, falls back to onion if clearnet fails.
#
# Usage:
#   bash scripts/peer-connect.sh
#   bash scripts/peer-connect.sh --tor-only    # force onion connections
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PEERS_FILE="$REPO_ROOT/config/peers.json"
LND_CONTAINER="lnd"
TOR_ONLY=false

# ── Parse args ───────────────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --tor-only) TOR_ONLY=true ;;
    --help|-h)
      echo "Usage: $0 [--tor-only]"
      echo "  --tor-only    Connect via onion only (skip clearnet)"
      exit 0
      ;;
  esac
done

# ── Banner ───────────────────────────────────────────────────────────────────
echo -e "${BOLD}${YELLOW}⚡ SatoshiAPI Peer Connect${NC}\n"

# ── Check LND is running ─────────────────────────────────────────────────────
if ! docker exec "$LND_CONTAINER" lncli --network=mainnet getinfo &>/dev/null 2>&1; then
  error "LND is not running or not ready."
  error "Start it with: docker-compose up -d lnd"
  error "Then unlock wallet: docker exec -it lnd lncli unlock"
  exit 1
fi

# ── Check jq ─────────────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  warn "jq not found — using fallback peer list"
  # Hardcoded fallback
  PEERS=(
    "03176f9948d333f9cc1d7d409353f995816e44b3c90a3300b5a08ceba811faf989@74.244.146.41:9735"
    "03176f9948d333f9cc1d7d409353f995816e44b3c90a3300b5a08ceba811faf989@34ok5fboyoxymwrb3mpynhhfgqkna3addrzmdkdzhibrkkdjokrrmpyd.onion:9735"
  )
  USE_FALLBACK=true
else
  USE_FALLBACK=false
fi

# ── Connect to peers ─────────────────────────────────────────────────────────
connect_peer() {
  local pubkey="$1"
  local address="$2"
  local name="${3:-Unknown}"

  info "Connecting to $name ($pubkey)..."
  info "  Address: $address"

  if docker exec "$LND_CONTAINER" lncli --network=mainnet connect "${pubkey}@${address}" 2>/dev/null; then
    success "Connected to $name"
    return 0
  else
    # Check if already connected
    if docker exec "$LND_CONTAINER" lncli --network=mainnet listpeers 2>/dev/null | grep -q "$pubkey"; then
      success "Already connected to $name"
      return 0
    fi
    warn "Failed to connect to $name at $address"
    return 1
  fi
}

if [[ "$USE_FALLBACK" == true ]]; then
  # Fallback: try hardcoded values
  PUBKEY="03176f9948d333f9cc1d7d409353f995816e44b3c90a3300b5a08ceba811faf989"
  if [[ "$TOR_ONLY" == false ]]; then
    connect_peer "$PUBKEY" "74.244.146.41:9735" "SatoshiAPI Primary Hub (clearnet)" || \
    connect_peer "$PUBKEY" "34ok5fboyoxymwrb3mpynhhfgqkna3addrzmdkdzhibrkkdjokrrmpyd.onion:9735" "SatoshiAPI Primary Hub (onion)"
  else
    connect_peer "$PUBKEY" "34ok5fboyoxymwrb3mpynhhfgqkna3addrzmdkdzhibrkkdjokrrmpyd.onion:9735" "SatoshiAPI Primary Hub (onion)"
  fi
else
  # Parse peers.json
  PEER_COUNT=$(jq '.hubs | length' "$PEERS_FILE")
  info "Found $PEER_COUNT hub peer(s) in config/peers.json"

  for i in $(seq 0 $((PEER_COUNT - 1))); do
    NAME=$(jq -r ".hubs[$i].name" "$PEERS_FILE")
    PUBKEY=$(jq -r ".hubs[$i].pubkey" "$PEERS_FILE")
    CLEARNET=$(jq -r ".hubs[$i].clearnet" "$PEERS_FILE")
    ONION=$(jq -r ".hubs[$i].onion" "$PEERS_FILE")

    if [[ "$TOR_ONLY" == true ]]; then
      connect_peer "$PUBKEY" "$ONION" "$NAME (onion)" || warn "Could not connect to $NAME"
    else
      # Try clearnet first, fall back to onion
      connect_peer "$PUBKEY" "$CLEARNET" "$NAME (clearnet)" || \
      connect_peer "$PUBKEY" "$ONION" "$NAME (onion)" || \
      warn "Could not connect to $NAME via clearnet or onion"
    fi
  done
fi

# ── Show current peers ───────────────────────────────────────────────────────
echo ""
info "Current peers:"
docker exec "$LND_CONTAINER" lncli --network=mainnet listpeers 2>/dev/null | \
  grep '"pub_key"' | sed 's/.*"pub_key": "\(.*\)".*/  - \1/' || true

echo ""
success "Peer connection complete. Next: bash scripts/open-channels.sh"
