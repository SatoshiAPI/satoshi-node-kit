# 🔒 Firewall & Port Configuration

> Which ports to open, which to keep closed, and how to handle CGNAT.

---

## Required Ports

| Port | Protocol | Direction | Service | Must be public? |
|------|----------|-----------|---------|-----------------|
| **9735** | TCP | Inbound + Outbound | LND P2P (Lightning) | **Yes** — peers connect here |
| **10009** | TCP | Localhost only | LND gRPC | **No** — never expose to internet |
| **8080** | TCP | Localhost only | LND REST API | **No** — never expose to internet |
| **8332** | TCP | Localhost only | bitcoind RPC (full node only) | **No** — never expose |
| **8333** | TCP | Inbound + Outbound | bitcoind P2P (full node only) | Yes, for full node |

### Tor-Specific Ports (outbound only)

If your node uses Tor (enabled by default), these **outbound** ports must not be blocked by your firewall:

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| **9001** | TCP | Outbound | Tor relay connections |
| **9030** | TCP | Outbound | Tor directory connections |
| **443** | TCP | Outbound | Tor bridges (fallback) |

> **Tor-only mode requires NO inbound ports.** If you can't open port 9735 (e.g., CGNAT), Tor-only operation is your best option. See the `lnd.conf` Tor section.

---

## Firewall Configuration

### Linux (UFW)

```bash
# Allow Lightning P2P
sudo ufw allow 9735/tcp comment "LND Lightning P2P"

# If running bitcoind full node
sudo ufw allow 8333/tcp comment "Bitcoin P2P"

# Verify
sudo ufw status
```

### Linux (iptables)

```bash
sudo iptables -A INPUT -p tcp --dport 9735 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8333 -j ACCEPT  # full node only
```

### macOS

macOS firewall doesn't block outbound by default. For inbound, allow Docker in System Settings → Network → Firewall → Options.

### Windows

```powershell
# PowerShell as Admin
New-NetFirewallRule -DisplayName "LND Lightning P2P" -Direction Inbound -LocalPort 9735 -Protocol TCP -Action Allow
```

---

## Router / Port Forwarding

Most home internet requires port forwarding on your router:

1. Find your machine's **LAN IP**: `hostname -I` (Linux) or `ipconfig` (Windows)
2. Log into your router (usually `192.168.1.1` or `192.168.0.1`)
3. Find **Port Forwarding** settings
4. Forward **TCP 9735** → your machine's LAN IP, port 9735
5. (Optional) Forward **TCP 8333** if running a full node

### Verify Port is Open

After forwarding, test from outside your network:

```bash
# From a different machine or use an online port checker
nc -zv YOUR_PUBLIC_IP 9735
```

Or use https://www.yougetsignal.com/tools/open-ports/

---

## CGNAT (Carrier-Grade NAT)

If your ISP uses CGNAT, you **cannot** open inbound ports. Signs of CGNAT:

- Your router's WAN IP starts with `100.64.x.x` or `10.x.x.x`
- Your router's WAN IP doesn't match what `curl ifconfig.me` shows
- Port forwarding is configured but external checks fail

### Solutions for CGNAT

1. **Use Tor-only mode** (recommended) — no inbound ports needed:
   - In `lnd.conf`, ensure `tor.active=true` and `tor.v3=true`
   - Comment out `tor.skip-proxy-for-clearnet-targets=true`
   - Enable `tor.streamisolation=true`
   - Peers connect to your `.onion` address instead

2. **Use a VPS** — rent a small VPS ($5/month) with a public IP and run the node there

3. **Use a VPN with port forwarding** — some VPN providers (e.g., Mullvad) offer port forwarding

4. **Ask your ISP** — some ISPs will assign you a public IP on request (sometimes for a fee)

---

## Security Reminders

- ❌ **NEVER** expose port 10009 (gRPC) or 8080 (REST) to the internet
- ❌ **NEVER** expose port 8332 (bitcoind RPC) to the internet
- ✅ Only port 9735 (and optionally 8333) should be publicly accessible
- ✅ Use SSH tunnels if you need remote access to gRPC/REST: `ssh -L 10009:localhost:10009 your-server`
