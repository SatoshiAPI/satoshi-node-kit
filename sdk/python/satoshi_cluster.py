"""
satoshi_cluster.py — Python SDK for the SatoshiAPI Agent Network
=================================================================
Provides the SatoshiCluster class for interacting with the SatoshiAPI cluster:
  - L402 authentication (Lightning-native HTTP 402 payment flow)
  - Node registration and bonus eligibility
  - Price feed and escrow creation

Usage:
    from satoshi_cluster import SatoshiCluster

    cluster = SatoshiCluster(lnd_host="127.0.0.1", lnd_port=10009, macaroon_path="~/.lnd/admin.macaroon")
    price = cluster.get_price("BTC/USD")
    cluster.register_node(pubkey="...", tier="builder", channels_opened=3, committed_sats=1_000_000)

Requirements: see requirements.txt
"""

from __future__ import annotations

import base64
import json
import os
import re
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

import httpx

# ── Constants ──────────────────────────────────────────────────────────────────
API_BASE = "https://api.satoshiapi.io"
MCP_BASE = "https://api.satoshiapi.io/mcp"
REGISTER_ENDPOINT = f"{API_BASE}/cluster/register"
PRICE_ENDPOINT = f"{API_BASE}/price"
ESCROW_ENDPOINT = f"{API_BASE}/escrow"

VALID_TIERS = {"seed", "builder", "anchor", "founding"}

TIER_REQUIREMENTS = {
    "seed":     {"min_sats": 500_000,   "max_sats": 999_999,  "bonus_pct": 10, "min_channels": 2},
    "builder":  {"min_sats": 1_000_000, "max_sats": 4_999_999,"bonus_pct": 15, "min_channels": 3},
    "anchor":   {"min_sats": 5_000_000, "max_sats": 9_999_999,"bonus_pct": 20, "min_channels": 5},
    "founding": {"min_sats": 10_000_000,"max_sats": None,     "bonus_pct": 25, "min_channels": 6},
}


# ── Data classes ───────────────────────────────────────────────────────────────

@dataclass
class BonusEligibility:
    """Result of a bonus eligibility check."""
    eligible: bool
    tier: str
    bonus_pct: int
    bonus_sats: int
    message: str
    requirements: dict[str, Any] = field(default_factory=dict)


@dataclass
class RegistrationResult:
    """Result of a node registration attempt."""
    success: bool
    status_code: int
    message: str
    data: dict[str, Any] = field(default_factory=dict)


@dataclass
class L402Token:
    """A parsed L402 payment token."""
    macaroon: str
    preimage: str
    payment_hash: str


# ── Main SDK class ─────────────────────────────────────────────────────────────

class SatoshiCluster:
    """
    SDK for the SatoshiAPI Agent Network cluster.

    Handles L402 authentication, node registration, price queries, and escrow
    creation. All Lightning-native: payment flows use actual invoices.

    Args:
        lnd_host:      LND REST host (default: 127.0.0.1)
        lnd_port:      LND REST port (default: 8080)
        macaroon_path: Path to LND admin.macaroon (default: ~/.lnd/admin.macaroon)
        tls_cert_path: Path to LND tls.cert (default: ~/.lnd/tls.cert)
        api_base:      Override API base URL
        timeout:       HTTP timeout in seconds (default: 30)
    """

    def __init__(
        self,
        lnd_host: str = "127.0.0.1",
        lnd_port: int = 8080,
        macaroon_path: Optional[str] = None,
        tls_cert_path: Optional[str] = None,
        api_base: str = API_BASE,
        timeout: float = 30.0,
    ) -> None:
        self.lnd_base = f"https://{lnd_host}:{lnd_port}"
        self.api_base = api_base.rstrip("/")
        self.timeout = timeout

        # Resolve macaroon
        self._macaroon_hex: Optional[str] = None
        if macaroon_path:
            self._macaroon_hex = self._load_macaroon(macaroon_path)

        # LND TLS cert path (for verifying self-signed cert)
        self.tls_cert_path = str(Path(tls_cert_path or "~/.lnd/tls.cert").expanduser())

        # Cached L402 tokens: endpoint → L402Token
        self._l402_cache: dict[str, L402Token] = {}

    # ── Public API ─────────────────────────────────────────────────────────────

    def get_price(self, pair: str = "BTC/USD") -> dict[str, Any]:
        """
        Fetch the current price for a trading pair.

        Args:
            pair: Trading pair string, e.g. "BTC/USD" (default)

        Returns:
            dict with keys: pair, price, currency, timestamp, source

        Raises:
            httpx.HTTPError: On network or API errors
            ValueError: If pair format is invalid

        Example:
            >>> cluster = SatoshiCluster()
            >>> result = cluster.get_price("BTC/USD")
            >>> print(f"BTC price: ${result['price']:,.2f}")
        """
        if "/" not in pair:
            raise ValueError(f"Invalid pair format '{pair}'. Expected 'BASE/QUOTE', e.g. 'BTC/USD'.")

        url = f"{self.api_base}/price"
        params = {"pair": pair}

        response = self._get_with_l402(url, params=params)
        return response

    def register_node(
        self,
        pubkey: str,
        tier: str,
        channels_opened: int,
        committed_sats: int,
        alias: str = "",
    ) -> RegistrationResult:
        """
        Register a Lightning node with the SatoshiAPI cluster for inbound bonus.

        Args:
            pubkey:          Node's Lightning public key (66 hex chars)
            tier:            Bonus tier: 'seed', 'builder', 'anchor', or 'founding'
            channels_opened: Number of channels opened to the SatoshiAPI hub
            committed_sats:  Total sats committed across all channels
            alias:           Optional human-readable node alias

        Returns:
            RegistrationResult with success status and response data

        Raises:
            ValueError: If inputs are invalid

        Example:
            >>> result = cluster.register_node(
            ...     pubkey="03abc...",
            ...     tier="builder",
            ...     channels_opened=3,
            ...     committed_sats=1_500_000,
            ... )
            >>> if result.success:
            ...     print("Registered! Bonus incoming.")

        Note:
            The /cluster/register endpoint is coming soon. This method will
            indicate when the endpoint is live.
        """
        # Validate pubkey
        if not re.match(r'^[0-9a-f]{66}$', pubkey.lower()):
            raise ValueError(f"Invalid pubkey format. Expected 66-char hex string, got: {pubkey[:20]}...")

        # Validate tier
        tier = tier.lower()
        if tier not in VALID_TIERS:
            raise ValueError(f"Invalid tier '{tier}'. Must be one of: {', '.join(VALID_TIERS)}")

        # Validate channel count
        min_ch = TIER_REQUIREMENTS[tier]["min_channels"]
        if channels_opened < min_ch:
            raise ValueError(
                f"Tier '{tier}' requires at least {min_ch} channels. Got {channels_opened}."
            )

        # Validate sats
        min_s = TIER_REQUIREMENTS[tier]["min_sats"]
        if committed_sats < min_s:
            raise ValueError(
                f"Tier '{tier}' requires at least {min_s:,} sats. Got {committed_sats:,}."
            )

        payload = {
            "pubkey": pubkey,
            "alias": alias,
            "tier": tier,
            "channels_opened": channels_opened,
            "committed_sats": committed_sats,
        }

        try:
            with httpx.Client(timeout=self.timeout) as client:
                resp = client.post(
                    f"{self.api_base}/cluster/register",
                    json=payload,
                    headers={"Content-Type": "application/json", "Accept": "application/json"},
                )

                if resp.status_code in (200, 201):
                    return RegistrationResult(
                        success=True,
                        status_code=resp.status_code,
                        message="Registration submitted successfully",
                        data=resp.json() if resp.content else {},
                    )
                elif resp.status_code == 404:
                    return RegistrationResult(
                        success=False,
                        status_code=404,
                        message="⏳ /cluster/register endpoint is coming soon. Save your payload and retry at launch.",
                        data={"payload": payload},
                    )
                else:
                    return RegistrationResult(
                        success=False,
                        status_code=resp.status_code,
                        message=f"API returned HTTP {resp.status_code}: {resp.text[:200]}",
                        data={},
                    )

        except httpx.ConnectError as e:
            return RegistrationResult(
                success=False,
                status_code=0,
                message=f"Connection failed: {e}",
                data={"payload": payload},
            )

    def create_escrow(
        self,
        amount_sats: int,
        description: str = "",
        expiry_seconds: int = 3600,
    ) -> dict[str, Any]:
        """
        Create an escrow invoice via the SatoshiAPI.

        Args:
            amount_sats:    Amount in satoshis to escrow
            description:    Optional memo/description
            expiry_seconds: Invoice expiry time in seconds (default: 1 hour)

        Returns:
            dict with keys: payment_request, payment_hash, amount_sats, expires_at

        Raises:
            ValueError: If amount is below minimum
            httpx.HTTPError: On network or API errors

        Example:
            >>> escrow = cluster.create_escrow(50000, "Channel open deposit")
            >>> print(f"Pay: {escrow['payment_request']}")
        """
        if amount_sats < 1:
            raise ValueError(f"Escrow amount must be >= 1 sat. Got {amount_sats}.")

        payload = {
            "amount_sats": amount_sats,
            "description": description or f"SatoshiAPI escrow - {int(time.time())}",
            "expiry_seconds": expiry_seconds,
        }

        response = self._post_with_l402(
            f"{self.api_base}/escrow",
            payload=payload,
        )
        return response

    def check_bonus_eligibility(
        self,
        committed_sats: int,
        channels_opened: int,
        uptime_pct: float = 100.0,
    ) -> BonusEligibility:
        """
        Check whether a node is eligible for a bonus tier without making a
        network request (purely local validation).

        Args:
            committed_sats:  Total sats committed in channels
            channels_opened: Number of channels open to the hub
            uptime_pct:      Uptime percentage over the last 90 days (default: 100%)

        Returns:
            BonusEligibility with eligibility status, tier, and bonus details

        Example:
            >>> eligibility = cluster.check_bonus_eligibility(
            ...     committed_sats=1_500_000,
            ...     channels_opened=3,
            ...     uptime_pct=97.5,
            ... )
            >>> print(f"Tier: {eligibility.tier}, Bonus: {eligibility.bonus_sats} sats")
        """
        UPTIME_REQUIREMENT = 95.0

        # Determine tier by sats
        tier = None
        for tier_name in ("founding", "anchor", "builder", "seed"):
            req = TIER_REQUIREMENTS[tier_name]
            if committed_sats >= req["min_sats"]:
                tier = tier_name
                break

        if tier is None:
            return BonusEligibility(
                eligible=False,
                tier="none",
                bonus_pct=0,
                bonus_sats=0,
                message=f"Minimum 500,000 sats required. You have {committed_sats:,} sats.",
            )

        req = TIER_REQUIREMENTS[tier]
        min_channels = req["min_channels"]
        bonus_pct = req["bonus_pct"]

        issues: list[str] = []

        if channels_opened < min_channels:
            issues.append(
                f"Need {min_channels} channels for {tier} tier (have {channels_opened})"
            )

        if uptime_pct < UPTIME_REQUIREMENT:
            issues.append(
                f"Need {UPTIME_REQUIREMENT}% uptime (have {uptime_pct:.1f}%)"
            )

        eligible = len(issues) == 0
        bonus_sats = (committed_sats * bonus_pct // 100) if eligible else 0

        return BonusEligibility(
            eligible=eligible,
            tier=tier,
            bonus_pct=bonus_pct,
            bonus_sats=bonus_sats,
            message="Eligible for inbound liquidity bonus!" if eligible else f"Not eligible: {'; '.join(issues)}",
            requirements={
                "min_sats": req["min_sats"],
                "min_channels": min_channels,
                "uptime_pct": UPTIME_REQUIREMENT,
            },
        )

    # ── L402 helpers ────────────────────────────────────────────────────────────

    def _get_with_l402(self, url: str, params: Optional[dict] = None) -> dict[str, Any]:
        """
        Perform a GET request, handling L402 challenge/response flow.

        On HTTP 402:
          1. Parse WWW-Authenticate header for invoice + macaroon
          2. Pay the invoice via LND
          3. Retry with Authorization: L402 <macaroon>:<preimage>
        """
        # Include query params in cache key so different requests (e.g. BTC/USD vs ETH/USD)
        # don't share L402 tokens — tokens may have caveats bound to specific resources.
        if params:
            from urllib.parse import urlencode
            cache_key = f"{url}?{urlencode(sorted(params.items()))}"
        else:
            cache_key = url
        headers: dict[str, str] = {"Accept": "application/json"}

        # Attach cached token if available
        if cache_key in self._l402_cache:
            token = self._l402_cache[cache_key]
            headers["Authorization"] = f"L402 {token.macaroon}:{token.preimage}"

        with httpx.Client(timeout=self.timeout) as client:
            resp = client.get(url, params=params, headers=headers)

            if resp.status_code == 402:
                token = self._handle_l402_challenge(resp)
                self._l402_cache[cache_key] = token
                headers["Authorization"] = f"L402 {token.macaroon}:{token.preimage}"
                resp = client.get(url, params=params, headers=headers)

            resp.raise_for_status()
            return resp.json()

    def _post_with_l402(self, url: str, payload: dict[str, Any]) -> dict[str, Any]:
        """
        Perform a POST request, handling L402 challenge/response flow.
        """
        cache_key = url
        headers: dict[str, str] = {
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

        if cache_key in self._l402_cache:
            token = self._l402_cache[cache_key]
            headers["Authorization"] = f"L402 {token.macaroon}:{token.preimage}"

        with httpx.Client(timeout=self.timeout) as client:
            resp = client.post(url, json=payload, headers=headers)

            if resp.status_code == 402:
                token = self._handle_l402_challenge(resp)
                self._l402_cache[cache_key] = token
                headers["Authorization"] = f"L402 {token.macaroon}:{token.preimage}"
                resp = client.post(url, json=payload, headers=headers)

            resp.raise_for_status()
            return resp.json()

    def _handle_l402_challenge(self, response: httpx.Response) -> L402Token:
        """
        Parse WWW-Authenticate header and pay the Lightning invoice via LND.

        Args:
            response: The 402 response from the API

        Returns:
            L402Token with macaroon and payment preimage

        Raises:
            RuntimeError: If LND macaroon is not configured or payment fails
            ValueError: If WWW-Authenticate header is malformed
        """
        www_auth = response.headers.get("WWW-Authenticate", "")

        # Parse: L402 macaroon="...", invoice="..."
        macaroon_match = re.search(r'macaroon="([^"]+)"', www_auth)
        invoice_match = re.search(r'invoice="([^"]+)"', www_auth)

        if not macaroon_match or not invoice_match:
            raise ValueError(
                f"Malformed WWW-Authenticate header: {www_auth[:200]}"
            )

        macaroon_b64 = macaroon_match.group(1)
        invoice = invoice_match.group(1)

        if not self._macaroon_hex:
            raise RuntimeError(
                "LND macaroon not configured. Pass macaroon_path= to SatoshiCluster()."
            )

        # Pay the invoice via LND REST
        preimage = self._pay_invoice(invoice)

        return L402Token(
            macaroon=macaroon_b64,
            preimage=preimage,
            payment_hash="",  # Could extract from invoice decode if needed
        )

    def _pay_invoice(self, payment_request: str) -> str:
        """
        Pay a Lightning invoice via LND REST API and return the payment preimage.

        Args:
            payment_request: BOLT-11 invoice string

        Returns:
            Payment preimage (hex string)

        Raises:
            RuntimeError: If payment fails
        """
        url = f"{self.lnd_base}/v1/channels/transactions"
        headers = {
            "Grpc-Metadata-macaroon": self._macaroon_hex,
            "Content-Type": "application/json",
        }
        payload = {"payment_request": payment_request}

        try:
            # SECURITY: Never silently disable TLS verification.
            # A missing cert means misconfiguration, not "connect insecurely."
            if not os.path.exists(self.tls_cert_path):
                raise FileNotFoundError(
                    f"LND TLS cert not found at {self.tls_cert_path}. "
                    "Cannot connect securely. Check tls_cert_path or run "
                    "'docker cp lnd:/root/.lnd/tls.cert ~/.lnd/tls.cert' to copy it."
                )

            with httpx.Client(
                timeout=60.0,
                verify=self.tls_cert_path,
            ) as client:
                resp = client.post(url, json=payload, headers=headers)
                resp.raise_for_status()
                data = resp.json()

                if "payment_error" in data and data["payment_error"]:
                    raise RuntimeError(f"Payment failed: {data['payment_error']}")

                preimage_b64 = data.get("payment_preimage", "")
                if not preimage_b64:
                    raise RuntimeError("Payment response missing preimage")

                # Decode base64 to hex
                preimage_bytes = base64.b64decode(preimage_b64)
                return preimage_bytes.hex()

        except httpx.HTTPStatusError as e:
            raise RuntimeError(f"LND payment request failed (HTTP {e.response.status_code}): {e}") from e

    @staticmethod
    def _load_macaroon(path: str) -> str:
        """Load a macaroon file and return its hex representation."""
        p = Path(path).expanduser()
        if not p.exists():
            raise FileNotFoundError(f"Macaroon not found at {p}")
        return p.read_bytes().hex()

    # ── Convenience ─────────────────────────────────────────────────────────────

    def __repr__(self) -> str:
        return f"SatoshiCluster(api={self.api_base!r}, lnd={self.lnd_base!r})"


# ── CLI-like usage example ─────────────────────────────────────────────────────

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="SatoshiAPI Cluster SDK CLI")
    sub = parser.add_subparsers(dest="cmd")

    # price
    p_price = sub.add_parser("price", help="Get BTC price")
    p_price.add_argument("--pair", default="BTC/USD")

    # eligibility
    p_elig = sub.add_parser("eligibility", help="Check bonus eligibility")
    p_elig.add_argument("--sats", type=int, required=True)
    p_elig.add_argument("--channels", type=int, required=True)
    p_elig.add_argument("--uptime", type=float, default=100.0)

    # register
    p_reg = sub.add_parser("register", help="Register node for bonus")
    p_reg.add_argument("--pubkey", required=True)
    p_reg.add_argument("--tier", required=True)
    p_reg.add_argument("--channels", type=int, required=True)
    p_reg.add_argument("--sats", type=int, required=True)

    args = parser.parse_args()
    cluster = SatoshiCluster()

    if args.cmd == "price":
        result = cluster.get_price(args.pair)
        print(json.dumps(result, indent=2))

    elif args.cmd == "eligibility":
        elig = cluster.check_bonus_eligibility(args.sats, args.channels, args.uptime)
        print(f"Eligible: {elig.eligible}")
        print(f"Tier:     {elig.tier}")
        print(f"Bonus:    +{elig.bonus_pct}% ({elig.bonus_sats:,} sats)")
        print(f"Message:  {elig.message}")

    elif args.cmd == "register":
        result = cluster.register_node(args.pubkey, args.tier, args.channels, args.sats)
        print(f"Success: {result.success}")
        print(f"Message: {result.message}")
        if result.data:
            print(f"Data:    {json.dumps(result.data, indent=2)}")

    else:
        parser.print_help()
