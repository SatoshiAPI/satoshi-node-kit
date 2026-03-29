# ⚡ SatoshiAPI Node Kit — Windows Setup (WSL2)

> Running a Lightning node on Windows requires WSL2 + Docker. This guide walks you through the entire process.

---

## Prerequisites

- **Windows 10** (version 2004+) or **Windows 11**
- **8 GB RAM minimum** (16 GB recommended — LND + Tor + WSL2 overhead)
- **20 GB free disk space** (blockchain headers via Neutrino are ~600 MB; full node needs 600+ GB)
- **Admin access** to install WSL2

---

## Step 1: Install WSL2

Open **PowerShell as Administrator** and run:

```powershell
wsl --install
```

This installs WSL2 with Ubuntu by default. Restart your machine when prompted.

After restart, Ubuntu will open and ask you to create a username/password. This is your Linux user — remember it.

Verify WSL2 is working:

```powershell
wsl --version
```

You should see `WSL version: 2.x.x`.

---

## Step 2: Install Docker

### Option A: Docker Desktop (easiest)

1. Download [Docker Desktop for Windows](https://docs.docker.com/desktop/install/windows-install/)
2. Install and enable **"Use WSL 2 based engine"** in Settings → General
3. In Settings → Resources → WSL Integration, enable your Ubuntu distro
4. Restart Docker Desktop

### Option B: Docker Engine inside WSL2 (no Docker Desktop)

If you don't want Docker Desktop (e.g., licensing concerns), install Docker Engine directly in WSL2:

```bash
# Inside your WSL2 Ubuntu terminal:
curl -fsSL https://get.docker.com | bash
sudo usermod -aG docker $USER

# Start Docker daemon (must do this after every WSL restart)
sudo service docker start
```

⚠️ **Important:** Without Docker Desktop, you must start the Docker daemon manually after each Windows reboot:

```bash
wsl -d Ubuntu -u root service docker start
```

Or add it to your `.bashrc`:

```bash
echo 'sudo service docker start 2>/dev/null' >> ~/.bashrc
```

Verify Docker works:

```bash
docker --version
docker compose version
docker run hello-world
```

---

## Step 3: Clone and Run the Node Kit

Open your WSL2 terminal (search "Ubuntu" in Start menu):

```bash
git clone https://github.com/SatoshiAPI/satoshi-node-kit.git
cd satoshi-node-kit
bash scripts/setup.sh
```

The setup script will:
- Verify Docker is working
- Pull LND + Tor images
- Start your node
- Guide you through wallet creation

---

## Step 4: Wallet Creation (Interactive TTY Required)

⚠️ **`lncli create` requires an interactive terminal.** This means:

- ✅ Works: WSL2 terminal, Windows Terminal, PowerShell running `wsl`
- ❌ Does NOT work: SSH without `-t` flag, piped scripts, CI/CD
- ❌ Does NOT work: `curl ... | bash` (stdin is consumed by the pipe)

If you're running over SSH, use:

```bash
ssh -t user@host "docker exec -it lnd lncli create"
```

The `-t` flag allocates a pseudo-TTY, which `lncli create` requires for the interactive seed display and password prompt.

---

## Windows-Specific Considerations

### Port Forwarding

WSL2 uses a NAT network. Ports opened inside WSL2 are **automatically forwarded** to `localhost` on Windows (Docker Desktop handles this). However, they are NOT automatically accessible from other machines on your LAN.

To make your Lightning node reachable from the internet:

1. **Find your WSL2 IP:** `hostname -I` inside WSL2
2. **Forward port 9735** on your Windows firewall and router to your WSL2 IP
3. Or use **Tor-only mode** (no port forwarding needed — see `lnd.conf` Tor section)

### Firewall

Windows Defender Firewall may block Docker ports. If peers can't connect:

```powershell
# Run in PowerShell as Admin
New-NetFirewallRule -DisplayName "LND P2P" -Direction Inbound -LocalPort 9735 -Protocol TCP -Action Allow
```

### Performance

WSL2 file I/O is significantly slower when accessing Windows drives (`/mnt/c/`). **Always clone the repo inside the Linux filesystem** (e.g., `~/satoshi-node-kit`), not on `/mnt/c/Users/...`.

### Persistence

WSL2 shuts down after ~8 seconds of inactivity (no running processes). Since Docker containers run inside WSL2, your node will stop if WSL2 shuts down.

To keep WSL2 alive, create a `.wslconfig` file at `C:\Users\<YourName>\.wslconfig`:

```ini
[wsl2]
# Prevent WSL2 from auto-shutting down
# (keeps your Lightning node running)
networkingMode=mirrored
```

Or ensure Docker Desktop is running — it keeps WSL2 alive automatically.

### Memory

WSL2 can consume a lot of RAM. Limit it in `.wslconfig`:

```ini
[wsl2]
memory=4GB
swap=2GB
```

LND + Tor + Neutrino typically uses 500 MB–1 GB.

---

## Troubleshooting

### "Cannot connect to Docker daemon"

```bash
# If using Docker Desktop: make sure it's running and WSL integration is enabled
# If using Docker Engine in WSL2:
sudo service docker start
```

### "docker compose" not found

```bash
# Docker Compose v2 comes with Docker Desktop.
# For standalone install in WSL2:
sudo apt-get update && sudo apt-get install docker-compose-plugin
```

### "Ports not reachable from internet"

Your router likely needs port forwarding for TCP 9735 → your machine's LAN IP. Check [docs/firewall-ports.md](firewall-ports.md) for full port requirements.

Alternatively, use **Tor-only mode** which requires no port forwarding at all.

### "Node crashes after Windows sleep/hibernate"

WSL2 doesn't survive Windows sleep cleanly. After waking:

```bash
cd ~/satoshi-node-kit
docker compose up -d
docker exec -it lnd lncli unlock   # Enter wallet password
```

Consider enabling [auto-unlock](../lnd/lnd.conf) to avoid manual unlock after every restart.

---

## Quick Reference

```bash
# Start node
cd ~/satoshi-node-kit && docker compose up -d

# Check status
docker exec lnd lncli --network=mainnet getinfo

# Unlock wallet after restart
docker exec -it lnd lncli unlock

# View logs
docker logs lnd --tail 50
docker logs satoshi-tor --tail 50

# Stop node
docker compose down
```

---

**Next steps:** Follow the [main quickstart guide](quickstart.md) from Step 5 onward (funding, channels, bonus).
