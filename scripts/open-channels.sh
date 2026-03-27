#!/usr/bin/env bash
# =============================================================================
# open-channels.sh — Open Channels to SatoshiAPI Cluster
# =============================================================================
# Opens Lightning channels to the SatoshiAPI hub based on your chosen tier.
# Automatically determines your tier based on total committed sats.
#
# Usage:
#   bash scripts/open-channels.sh --sats 1000000
#   bash scripts/open-channels.sh --sats 5000000 --channels 5
#   bash scripts/open-channels.sh --sats 1000000 --dry-run
#
# Options:
#   --sats <amount>      Total sats to commit across all channels (required)
#   --channels <n>       Number of channels to open (default: tier minimum)
#   --dry-run            Show what would happen, don't execute
#   --push-sats <amt>    Push sats to remote side on open (optional)
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
HUB_PUBKEY="03176f9948d333f9cc1d7d409353f995816e44b3c90a3300b5a08ceba811faf989"
MIN_CHAN_SIZE=100000   # 100k sats minimum channel size

TOTAL_SATS=0
NUM_CHANNELS=0
DRY_RUN=false
PUSH_SATS=0

# ── Parse args ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --sats)       TOTAL_SATS="$2"; shift 2 ;;
    --channels)   NUM_CHANNELS="$2"; shift 2 ;;
    --push-sats)  PUSH_SATS="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=true; shift ;;
    --help|-h)
      echo "Usage: $0 --sats <total_sats> [--channels <n>] [--push-sats <amt>] [--dry-run]"
      echo ""
      echo "  --sats <amount>      Total sats to commit (500000 minimum)"
      echo "  --channels <n>       Number of channels (default: tier minimum)"
      echo "  --push-sats <amt>    Push sats to remote on open"
      echo "  --dry-run            Simulate without executing"
      exit 0
      ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# ── Validate ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}${YELLOW}⚡ SatoshiAPI Channel Opener${NC}\n"

if [[ $TOTAL_SATS -lt 500000 ]]; then
  die "Minimum commitment is 500,000 sats (Seed tier). Got: $TOTAL_SATS"
fi

# ── Determine tier ───────────────────────────────────────────────────────────
determine_tier() {
  local sats=$1
  if   (( sats >= 10000000 )); then echo "founding"; return; fi
  if   (( sats >= 5000000  )); then echo "anchor";   return; fi
  if   (( sats >= 1000000  )); then echo "builder";  return; fi
  echo "seed"
}

get_tier_channels() {
  case $1 in
    seed)     echo 2 ;;
    builder)  echo 3 ;;
    anchor)   echo 5 ;;
    founding) echo 6 ;;
  esac
}

get_tier_bonus() {
  case $1 in
    seed)     echo 10 ;;
    builder)  echo 15 ;;
    anchor)   echo 20 ;;
    founding) echo 25 ;;
  esac
}

TIER=$(determine_tier "$TOTAL_SATS")
TIER_MIN_CHANNELS=$(get_tier_channels "$TIER")
TIER_BONUS=$(get_tier_bonus "$TIER")

# Use user-specified channels or tier minimum
if [[ $NUM_CHANNELS -eq 0 ]]; then
  NUM_CHANNELS=$TIER_MIN_CHANNELS
fi

if [[ $NUM_CHANNELS -lt $TIER_MIN_CHANNELS ]]; then
  warn "Tier '$TIER' requires minimum $TIER_MIN_CHANNELS channels. Using $TIER_MIN_CHANNELS."
  NUM_CHANNELS=$TIER_MIN_CHANNELS
fi

# ── Calculate per-channel amount ─────────────────────────────────────────────
PER_CHANNEL_SATS=$(( TOTAL_SATS / NUM_CHANNELS ))

if [[ $PER_CHANNEL_SATS -lt $MIN_CHAN_SIZE ]]; then
  die "Per-channel size ($PER_CHANNEL_SATS sats) is below minimum ($MIN_CHAN_SIZE sats). Reduce channels or increase total sats."
fi

BONUS_SATS=$(( TOTAL_SATS * TIER_BONUS / 100 ))

# ── Summary ──────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  Tier:              ${BOLD}${TIER^}${NC}"
echo    "  Total committed:   $(numfmt --grouping "$TOTAL_SATS") sats"
echo    "  Channels to open:  $NUM_CHANNELS"
echo    "  Per-channel size:  $(numfmt --grouping "$PER_CHANNEL_SATS") sats"
echo -e "  Inbound bonus:     ${GREEN}+$(numfmt --grouping "$BONUS_SATS") sats (${TIER_BONUS}%)${NC}"
echo    "  Target pubkey:     ${HUB_PUBKEY:0:20}..."
echo    "  Uptime required:   95% over 30 days"
if $DRY_RUN; then
  echo -e "  ${YELLOW}Mode:              DRY RUN (no channels will be opened)${NC}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Confirm ──────────────────────────────────────────────────────────────────
if ! $DRY_RUN; then
  read -rp "Open $NUM_CHANNELS channel(s) of $PER_CHANNEL_SATS sats each? [y/N] " confirm
  if [[ "${confirm,,}" != "y" ]]; then
    info "Aborted. No channels opened."
    exit 0
  fi
fi

# ── Check LND ────────────────────────────────────────────────────────────────
if ! $DRY_RUN; then
  if ! docker exec "$LND_CONTAINER" lncli --network=mainnet getinfo &>/dev/null 2>&1; then
    die "LND is not running or not synced. Run: docker-compose up -d lnd"
  fi

  # Check that peer is connected
  if ! docker exec "$LND_CONTAINER" lncli --network=mainnet listpeers 2>/dev/null | grep -q "$HUB_PUBKEY"; then
    warn "Not connected to hub. Running peer-connect.sh first..."
    bash "$(dirname "${BASH_SOURCE[0]}")/peer-connect.sh"
  fi
fi

# ── Open channels ─────────────────────────────────────────────────────────────
OPENED=0
FAILED=0

for i in $(seq 1 "$NUM_CHANNELS"); do
  info "Opening channel $i/$NUM_CHANNELS (${PER_CHANNEL_SATS} sats)..."

  if $DRY_RUN; then
    success "[DRY RUN] Would open channel $i: $PER_CHANNEL_SATS sats → ${HUB_PUBKEY:0:20}..."
    (( OPENED++ ))
    continue
  fi

  CMD="docker exec $LND_CONTAINER lncli --network=mainnet openchannel \
    --node_key=$HUB_PUBKEY \
    --local_amt=$PER_CHANNEL_SATS"

  if [[ $PUSH_SATS -gt 0 ]]; then
    CMD="$CMD --push_amt=$PUSH_SATS"
  fi

  if eval "$CMD" 2>/dev/null; then
    success "Channel $i opened successfully"
    (( OPENED++ ))
  else
    warn "Channel $i failed to open"
    (( FAILED++ ))
  fi

  # Small delay between channel opens
  if [[ $i -lt $NUM_CHANNELS ]]; then
    sleep 2
  fi
done

# ── Result ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
success "Channels opened: $OPENED / $NUM_CHANNELS"
if [[ $FAILED -gt 0 ]]; then
  warn "Failed: $FAILED channels. Check 'docker logs lnd' for details."
fi
echo ""
info "Channels need 3+ confirmations (~30 min) before they're active."
info "Check status: docker exec lnd lncli --network=mainnet listchannels"
echo ""
echo "Next: Wait for confirmations, then run:"
echo "  bash scripts/claim-bonus.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
