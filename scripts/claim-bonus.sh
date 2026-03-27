#!/usr/bin/env bash
# =============================================================================
# claim-bonus.sh — Register for SatoshiAPI Inbound Liquidity Bonus
# =============================================================================
# Collects your node info and submits a registration request to the
# SatoshiAPI cluster API to claim your inbound liquidity bonus.
#
# Usage:
#   bash scripts/claim-bonus.sh
#   bash scripts/claim-bonus.sh --sats 1000000 --tier builder --channels 3
#   bash scripts/claim-bonus.sh --dry-run
#
# ⚠️  NOTE: The /cluster/register endpoint is coming soon.
#     This script will gracefully inform you when the endpoint is live.
# =============================================================================

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

# ── Config ───────────────────────────────────────────────────────────────────
LND_CONTAINER="lnd"
REGISTER_ENDPOINT="https://api.satoshiapi.io/cluster/register"
API_BASE="https://api.satoshiapi.io"
DRY_RUN=false

TIER=""
COMMITTED_SATS=0
CHANNELS_OPENED=0

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --sats)     COMMITTED_SATS="$2"; shift 2 ;;
    --tier)     TIER="$2"; shift 2 ;;
    --channels) CHANNELS_OPENED="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=true; shift ;;
    --help|-h)
      echo "Usage: $0 [--sats <n>] [--tier <seed|builder|anchor|founding>] [--channels <n>] [--dry-run]"
      exit 0
      ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# ── Banner ───────────────────────────────────────────────────────────────────
echo -e "${BOLD}${YELLOW}⚡ SatoshiAPI Bonus Registration${NC}\n"

# ── Check LND ────────────────────────────────────────────────────────────────
if ! docker exec "$LND_CONTAINER" lncli --network=mainnet getinfo &>/dev/null 2>&1; then
  die "LND is not running. Start with: docker-compose up -d lnd"
fi

# ── Get node pubkey ───────────────────────────────────────────────────────────
NODE_INFO=$(docker exec "$LND_CONTAINER" lncli --network=mainnet getinfo 2>/dev/null)
PUBKEY=$(echo "$NODE_INFO" | grep '"identity_pubkey"' | sed 's/.*: "\(.*\)".*/\1/')
ALIAS=$(echo "$NODE_INFO" | grep '"alias"' | sed 's/.*: "\(.*\)".*/\1/')

if [[ -z "$PUBKEY" ]]; then
  die "Could not retrieve pubkey from LND. Is your wallet unlocked?"
fi

info "Node pubkey: $PUBKEY"
info "Node alias:  $ALIAS"

# ── Auto-detect channels if not specified ─────────────────────────────────────
if [[ $CHANNELS_OPENED -eq 0 ]]; then
  CHANNEL_LIST=$(docker exec "$LND_CONTAINER" lncli --network=mainnet listchannels 2>/dev/null)
  HUB_PUBKEY="03176f9948d333f9cc1d7d409353f995816e44b3c90a3300b5a08ceba811faf989"
  CHANNELS_OPENED=$(echo "$CHANNEL_LIST" | grep -c "$HUB_PUBKEY" || echo 0)
  info "Auto-detected $CHANNELS_OPENED channel(s) to SatoshiAPI hub"
fi

if [[ $CHANNELS_OPENED -eq 0 ]]; then
  warn "No channels to SatoshiAPI hub detected."
  warn "Open channels first: bash scripts/open-channels.sh"
  read -rp "Continue registration anyway? [y/N] " ans
  [[ "${ans,,}" != "y" ]] && exit 1
fi

# ── Auto-detect tier if not specified ─────────────────────────────────────────
if [[ -z "$TIER" ]] && [[ $COMMITTED_SATS -gt 0 ]]; then
  if   (( COMMITTED_SATS >= 10000000 )); then TIER="founding"
  elif (( COMMITTED_SATS >= 5000000  )); then TIER="anchor"
  elif (( COMMITTED_SATS >= 1000000  )); then TIER="builder"
  elif (( COMMITTED_SATS >= 500000   )); then TIER="seed"
  else die "Minimum 500,000 sats required for any tier"
  fi
  info "Auto-detected tier: ${TIER^}"
fi

if [[ -z "$TIER" ]]; then
  echo ""
  echo "Select your tier:"
  echo "  1) Seed     (500k–999k sats,  +10% inbound)"
  echo "  2) Builder  (1M–4.99M sats,   +15% inbound)"
  echo "  3) Anchor   (5M–9.99M sats,   +20% inbound)"
  echo "  4) Founding (10M+ sats,        +25% inbound)"
  echo ""
  read -rp "Choice [1-4]: " tier_choice
  case $tier_choice in
    1) TIER="seed" ;;
    2) TIER="builder" ;;
    3) TIER="anchor" ;;
    4) TIER="founding" ;;
    *) die "Invalid choice" ;;
  esac
fi

if [[ $COMMITTED_SATS -eq 0 ]]; then
  read -rp "Total sats committed across all channels: " COMMITTED_SATS
fi

# ── Build payload ─────────────────────────────────────────────────────────────
PAYLOAD=$(cat <<EOF
{
  "pubkey": "$PUBKEY",
  "alias": "$ALIAS",
  "tier": "$TIER",
  "channels_opened": $CHANNELS_OPENED,
  "committed_sats": $COMMITTED_SATS
}
EOF
)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Registration payload:"
echo "$PAYLOAD" | sed 's/^/    /'
if $DRY_RUN; then
  echo -e "  ${YELLOW}Mode: DRY RUN — no request sent${NC}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if $DRY_RUN; then
  success "[DRY RUN] Would POST to: $REGISTER_ENDPOINT"
  success "[DRY RUN] Payload validated ✓"
  exit 0
fi

read -rp "Submit registration? [y/N] " confirm
[[ "${confirm,,}" != "y" ]] && { info "Aborted."; exit 0; }

# ── Check if endpoint is live ─────────────────────────────────────────────────
info "Checking API availability..."
HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" --max-time 10 "$API_BASE" 2>/dev/null || echo "000")

if [[ "$HTTP_STATUS" == "000" ]]; then
  error "Cannot reach $API_BASE — check your internet connection"
  exit 1
fi

# ── Submit registration ───────────────────────────────────────────────────────
info "Submitting registration to $REGISTER_ENDPOINT..."

RESPONSE=$(curl -s \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "$PAYLOAD" \
  --max-time 30 \
  -w "\n%{http_code}" \
  "$REGISTER_ENDPOINT" 2>/dev/null || echo -e "\n000")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

echo ""
case "$HTTP_CODE" in
  200|201)
    success "Registration submitted successfully!"
    echo ""
    echo "  Response: $BODY"
    echo ""
    info "SatoshiAPI will verify your channels and open inbound liquidity."
    info "This typically happens within 24 hours."
    ;;
  404)
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  ⏳ Coming Soon!${NC}"
    echo ""
    echo "  The /cluster/register endpoint is not yet live."
    echo "  Your registration details have been saved locally."
    echo ""
    echo "  Save this info and try again when the endpoint launches:"
    echo "  $PAYLOAD" | sed 's/^/    /'
    echo ""
    echo "  Follow @SatoshiAPI for launch announcement."
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Save locally for later
    SAVE_PATH="$(dirname "${BASH_SOURCE[0]}")/../config/pending-registration.json"
    echo "$PAYLOAD" > "$SAVE_PATH"
    info "Saved to: config/pending-registration.json"
    ;;
  429)
    warn "Rate limited. Wait a moment and try again."
    ;;
  *)
    error "Unexpected response (HTTP $HTTP_CODE):"
    echo "$BODY"
    ;;
esac
