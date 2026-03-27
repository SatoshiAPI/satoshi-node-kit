/**
 * satoshi-cluster.js — JavaScript SDK for the SatoshiAPI Agent Network
 * =====================================================================
 * ESM module. Uses native fetch() (Node.js 18+ / browsers).
 *
 * Provides the SatoshiCluster class:
 *   - get_price()              — BTC/USD and other pair prices
 *   - register_node()          — Register for inbound liquidity bonus
 *   - create_escrow()          — Create a Lightning escrow invoice
 *   - check_bonus_eligibility()— Local eligibility check (no network)
 *
 * L402 flow is handled automatically when lndRestUrl + macaroonHex are set.
 *
 * @example
 * import { SatoshiCluster } from './satoshi-cluster.js';
 *
 * const cluster = new SatoshiCluster({
 *   lndRestUrl: 'https://127.0.0.1:8080',
 *   macaroonHex: 'deadbeef...', // admin.macaroon as hex
 * });
 *
 * const price = await cluster.get_price('BTC/USD');
 * console.log(`BTC: $${price.price.toLocaleString()}`);
 */

// ── Constants ────────────────────────────────────────────────────────────────

const API_BASE = 'https://api.satoshiapi.io';
const MCP_BASE = 'https://api.satoshiapi.io/mcp';

/** @type {Record<string, TierRequirement>} */
const TIER_REQUIREMENTS = {
  seed:     { minSats: 500_000,   maxSats: 999_999,    bonusPct: 10, minChannels: 2 },
  builder:  { minSats: 1_000_000, maxSats: 4_999_999,  bonusPct: 15, minChannels: 3 },
  anchor:   { minSats: 5_000_000, maxSats: 9_999_999,  bonusPct: 20, minChannels: 5 },
  founding: { minSats: 10_000_000, maxSats: null,       bonusPct: 25, minChannels: 6 },
};

const VALID_TIERS = new Set(Object.keys(TIER_REQUIREMENTS));
const UPTIME_REQUIREMENT_PCT = 95;


// ── Type definitions (JSDoc) ──────────────────────────────────────────────────

/**
 * @typedef {Object} TierRequirement
 * @property {number} minSats - Minimum sats required
 * @property {number|null} maxSats - Maximum sats (null = unlimited)
 * @property {number} bonusPct - Inbound bonus percentage
 * @property {number} minChannels - Minimum channels required
 */

/**
 * @typedef {Object} PriceResult
 * @property {string} pair - Trading pair, e.g. "BTC/USD"
 * @property {number} price - Current price
 * @property {string} currency - Quote currency
 * @property {string} timestamp - ISO timestamp
 * @property {string} source - Price source
 */

/**
 * @typedef {Object} RegistrationResult
 * @property {boolean} success - Whether registration succeeded
 * @property {number} statusCode - HTTP status code
 * @property {string} message - Human-readable result message
 * @property {Object} data - Raw response data
 */

/**
 * @typedef {Object} EscrowResult
 * @property {string} paymentRequest - BOLT-11 invoice
 * @property {string} paymentHash - Invoice payment hash
 * @property {number} amountSats - Invoice amount in sats
 * @property {string} expiresAt - ISO expiry timestamp
 */

/**
 * @typedef {Object} BonusEligibility
 * @property {boolean} eligible - Whether the node qualifies
 * @property {string} tier - Determined tier name
 * @property {number} bonusPct - Bonus percentage
 * @property {number} bonusSats - Calculated bonus in sats
 * @property {string} message - Human-readable status
 * @property {Object} requirements - Tier requirements
 */

/**
 * @typedef {Object} L402Token
 * @property {string} macaroon - Base64-encoded macaroon
 * @property {string} preimage - Payment preimage (hex)
 */

/**
 * @typedef {Object} SatoshiClusterOptions
 * @property {string} [lndRestUrl='https://127.0.0.1:8080'] - LND REST URL
 * @property {string} [macaroonHex] - LND admin.macaroon as hex string
 * @property {string} [apiBase='https://api.satoshiapi.io'] - API base URL
 * @property {number} [timeoutMs=30000] - Fetch timeout in milliseconds
 */


// ── Main class ────────────────────────────────────────────────────────────────

export class SatoshiCluster {
  /**
   * Create a SatoshiCluster client.
   *
   * @param {SatoshiClusterOptions} [options={}]
   */
  constructor(options = {}) {
    this.lndRestUrl = (options.lndRestUrl || 'https://127.0.0.1:8080').replace(/\/$/, '');
    this.macaroonHex = options.macaroonHex || null;
    this.apiBase = (options.apiBase || API_BASE).replace(/\/$/, '');
    this.timeoutMs = options.timeoutMs || 30_000;

    /** @type {Map<string, L402Token>} */
    this._l402Cache = new Map();
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /**
   * Fetch the current price for a trading pair.
   *
   * @param {string} [pair='BTC/USD'] - Trading pair, e.g. 'BTC/USD'
   * @returns {Promise<PriceResult>}
   * @throws {Error} On invalid pair or network errors
   *
   * @example
   * const price = await cluster.get_price('BTC/USD');
   * console.log(`₿ = $${price.price.toLocaleString()}`);
   */
  async get_price(pair = 'BTC/USD') {
    if (!pair.includes('/')) {
      throw new Error(`Invalid pair format '${pair}'. Expected 'BASE/QUOTE', e.g. 'BTC/USD'.`);
    }

    const url = new URL(`${this.apiBase}/price`);
    url.searchParams.set('pair', pair);

    return this._getWithL402(url.toString());
  }

  /**
   * Register a Lightning node for the SatoshiAPI inbound liquidity bonus.
   *
   * @param {Object} params
   * @param {string} params.pubkey - Node pubkey (66-char hex)
   * @param {string} params.tier - Tier: 'seed' | 'builder' | 'anchor' | 'founding'
   * @param {number} params.channelsOpened - Channels opened to the hub
   * @param {number} params.committedSats - Total sats committed
   * @param {string} [params.alias=''] - Optional node alias
   * @returns {Promise<RegistrationResult>}
   * @throws {Error} On validation failure
   *
   * @example
   * const result = await cluster.register_node({
   *   pubkey: '03abc...',
   *   tier: 'builder',
   *   channelsOpened: 3,
   *   committedSats: 1_500_000,
   * });
   * console.log(result.message);
   */
  async register_node({ pubkey, tier, channelsOpened, committedSats, alias = '' }) {
    // Validate pubkey
    if (!/^[0-9a-f]{66}$/i.test(pubkey)) {
      throw new Error(`Invalid pubkey format. Expected 66-char hex, got: ${pubkey.slice(0, 20)}...`);
    }

    // Validate tier
    tier = tier.toLowerCase();
    if (!VALID_TIERS.has(tier)) {
      throw new Error(`Invalid tier '${tier}'. Must be one of: ${[...VALID_TIERS].join(', ')}`);
    }

    const req = TIER_REQUIREMENTS[tier];

    // Validate channels
    if (channelsOpened < req.minChannels) {
      throw new Error(
        `Tier '${tier}' requires at least ${req.minChannels} channels. Got ${channelsOpened}.`
      );
    }

    // Validate sats
    if (committedSats < req.minSats) {
      throw new Error(
        `Tier '${tier}' requires at least ${req.minSats.toLocaleString()} sats. Got ${committedSats.toLocaleString()}.`
      );
    }

    const payload = {
      pubkey,
      alias,
      tier,
      channels_opened: channelsOpened,
      committed_sats: committedSats,
    };

    try {
      const response = await this._fetchWithTimeout(
        `${this.apiBase}/cluster/register`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
          body: JSON.stringify(payload),
        }
      );

      if (response.status === 200 || response.status === 201) {
        const data = await response.json().catch(() => ({}));
        return {
          success: true,
          statusCode: response.status,
          message: 'Registration submitted successfully',
          data,
        };
      }

      if (response.status === 404) {
        return {
          success: false,
          statusCode: 404,
          message: '⏳ /cluster/register endpoint is coming soon. Save your payload and retry at launch.',
          data: { payload },
        };
      }

      const text = await response.text().catch(() => '');
      return {
        success: false,
        statusCode: response.status,
        message: `API returned HTTP ${response.status}: ${text.slice(0, 200)}`,
        data: {},
      };

    } catch (err) {
      return {
        success: false,
        statusCode: 0,
        message: `Connection failed: ${err.message}`,
        data: { payload },
      };
    }
  }

  /**
   * Create an escrow invoice via SatoshiAPI.
   *
   * @param {Object} params
   * @param {number} params.amountSats - Amount in satoshis
   * @param {string} [params.description=''] - Memo/description
   * @param {number} [params.expirySeconds=3600] - Invoice expiry in seconds
   * @returns {Promise<EscrowResult>}
   * @throws {Error} On validation or network errors
   *
   * @example
   * const escrow = await cluster.create_escrow({ amountSats: 50_000 });
   * console.log(`Pay: ${escrow.paymentRequest}`);
   */
  async create_escrow({ amountSats, description = '', expirySeconds = 3600 }) {
    if (!amountSats || amountSats < 1) {
      throw new Error(`Escrow amount must be >= 1 sat. Got ${amountSats}.`);
    }

    const payload = {
      amount_sats: amountSats,
      description: description || `SatoshiAPI escrow - ${Date.now()}`,
      expiry_seconds: expirySeconds,
    };

    return this._postWithL402(`${this.apiBase}/escrow`, payload);
  }

  /**
   * Check whether a node is eligible for a bonus tier (local, no network).
   *
   * @param {Object} params
   * @param {number} params.committedSats - Total sats committed
   * @param {number} params.channelsOpened - Channels open to the hub
   * @param {number} [params.uptimePct=100] - Node uptime percentage over 30d
   * @returns {BonusEligibility}
   *
   * @example
   * const elig = cluster.check_bonus_eligibility({
   *   committedSats: 1_500_000,
   *   channelsOpened: 3,
   *   uptimePct: 97.5,
   * });
   * console.log(`${elig.tier}: +${elig.bonusSats.toLocaleString()} sats`);
   */
  check_bonus_eligibility({ committedSats, channelsOpened, uptimePct = 100 }) {
    // Find tier by sats
    let tier = null;
    for (const [name, req] of Object.entries(TIER_REQUIREMENTS).reverse()) {
      if (committedSats >= req.minSats) {
        tier = name;
        break;
      }
    }

    if (!tier) {
      return {
        eligible: false,
        tier: 'none',
        bonusPct: 0,
        bonusSats: 0,
        message: `Minimum 500,000 sats required. You have ${committedSats.toLocaleString()} sats.`,
        requirements: {},
      };
    }

    const req = TIER_REQUIREMENTS[tier];
    const issues = [];

    if (channelsOpened < req.minChannels) {
      issues.push(`Need ${req.minChannels} channels for ${tier} tier (have ${channelsOpened})`);
    }

    if (uptimePct < UPTIME_REQUIREMENT_PCT) {
      issues.push(`Need ${UPTIME_REQUIREMENT_PCT}% uptime (have ${uptimePct.toFixed(1)}%)`);
    }

    const eligible = issues.length === 0;
    const bonusSats = eligible ? Math.floor(committedSats * req.bonusPct / 100) : 0;

    return {
      eligible,
      tier,
      bonusPct: req.bonusPct,
      bonusSats,
      message: eligible
        ? 'Eligible for inbound liquidity bonus! 🎉'
        : `Not eligible: ${issues.join('; ')}`,
      requirements: {
        minSats: req.minSats,
        minChannels: req.minChannels,
        uptimePct: UPTIME_REQUIREMENT_PCT,
      },
    };
  }

  // ── L402 helpers ─────────────────────────────────────────────────────────────

  /**
   * GET request with automatic L402 handling.
   * @private
   */
  async _getWithL402(url) {
    const headers = { Accept: 'application/json' };

    if (this._l402Cache.has(url)) {
      const token = this._l402Cache.get(url);
      headers['Authorization'] = `L402 ${token.macaroon}:${token.preimage}`;
    }

    let response = await this._fetchWithTimeout(url, { headers });

    if (response.status === 402) {
      const token = await this._handleL402Challenge(response);
      this._l402Cache.set(url, token);
      headers['Authorization'] = `L402 ${token.macaroon}:${token.preimage}`;
      response = await this._fetchWithTimeout(url, { headers });
    }

    if (!response.ok) {
      throw new Error(`HTTP ${response.status} from ${url}`);
    }

    return response.json();
  }

  /**
   * POST request with automatic L402 handling.
   * @private
   */
  async _postWithL402(url, payload) {
    const headers = { 'Content-Type': 'application/json', Accept: 'application/json' };

    if (this._l402Cache.has(url)) {
      const token = this._l402Cache.get(url);
      headers['Authorization'] = `L402 ${token.macaroon}:${token.preimage}`;
    }

    let response = await this._fetchWithTimeout(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(payload),
    });

    if (response.status === 402) {
      const token = await this._handleL402Challenge(response);
      this._l402Cache.set(url, token);
      headers['Authorization'] = `L402 ${token.macaroon}:${token.preimage}`;
      response = await this._fetchWithTimeout(url, {
        method: 'POST',
        headers,
        body: JSON.stringify(payload),
      });
    }

    if (!response.ok) {
      throw new Error(`HTTP ${response.status} from ${url}`);
    }

    return response.json();
  }

  /**
   * Parse WWW-Authenticate header and pay the invoice via LND.
   * @private
   * @param {Response} response - The 402 Response object
   * @returns {Promise<L402Token>}
   */
  async _handleL402Challenge(response) {
    const wwwAuth = response.headers.get('WWW-Authenticate') || '';

    const macaroonMatch = wwwAuth.match(/macaroon="([^"]+)"/);
    const invoiceMatch  = wwwAuth.match(/invoice="([^"]+)"/);

    if (!macaroonMatch || !invoiceMatch) {
      throw new Error(`Malformed WWW-Authenticate header: ${wwwAuth.slice(0, 200)}`);
    }

    const macaroon = macaroonMatch[1];
    const invoice  = invoiceMatch[1];

    if (!this.macaroonHex) {
      throw new Error('LND macaroon not configured. Pass macaroonHex to SatoshiCluster().');
    }

    const preimage = await this._payInvoice(invoice);
    return { macaroon, preimage };
  }

  /**
   * Pay a Lightning invoice via LND REST and return the preimage.
   * @private
   * @param {string} paymentRequest - BOLT-11 invoice
   * @returns {Promise<string>} Preimage as hex string
   */
  async _payInvoice(paymentRequest) {
    const url = `${this.lndRestUrl}/v1/channels/transactions`;

    const response = await this._fetchWithTimeout(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Grpc-Metadata-macaroon': this.macaroonHex,
      },
      body: JSON.stringify({ payment_request: paymentRequest }),
    }, 60_000); // 60s timeout for payments

    if (!response.ok) {
      throw new Error(`LND payment failed: HTTP ${response.status}`);
    }

    const data = await response.json();

    if (data.payment_error) {
      throw new Error(`Lightning payment failed: ${data.payment_error}`);
    }

    if (!data.payment_preimage) {
      throw new Error('LND response missing payment_preimage');
    }

    // LND returns base64, convert to hex
    const bytes = Uint8Array.from(atob(data.payment_preimage), c => c.charCodeAt(0));
    return Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('');
  }

  /**
   * fetch() wrapper with AbortController timeout.
   * @private
   */
  async _fetchWithTimeout(url, options = {}, timeoutMs = null) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs || this.timeoutMs);

    try {
      return await fetch(url, { ...options, signal: controller.signal });
    } finally {
      clearTimeout(timer);
    }
  }

  toString() {
    return `SatoshiCluster(api=${this.apiBase}, lnd=${this.lndRestUrl})`;
  }
}


// ── Convenience factory ───────────────────────────────────────────────────────

/**
 * Create a SatoshiCluster with environment variable config.
 * Reads: SATOSHI_LND_URL, SATOSHI_MACAROON_HEX
 *
 * @returns {SatoshiCluster}
 *
 * @example
 * const cluster = fromEnv();
 * const price = await cluster.get_price();
 */
export function fromEnv() {
  return new SatoshiCluster({
    lndRestUrl: process.env.SATOSHI_LND_URL,
    macaroonHex: process.env.SATOSHI_MACAROON_HEX,
  });
}

export { TIER_REQUIREMENTS, VALID_TIERS, API_BASE, MCP_BASE };
export default SatoshiCluster;
