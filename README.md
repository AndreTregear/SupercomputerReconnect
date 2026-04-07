# SupercomputerReconnect

Persistent SSH tunnels to HPC compute nodes that survive daily SLURM job changes. Full automation: VPN → job submission → tunnel setup — one command.

Built for researchers who run services (LLM inference, ASR, TTS, Jupyter, etc.) on HPC nodes that change every day when jobs are resubmitted.

## The Problem

HPC jobs land on different compute nodes each time. You SSH in, set up port forwards, and when the job expires and you resubmit — everything breaks. You redo the tunnels manually. Every. Single. Day. And first you have to reauth your campus VPN.

## The Solution

```bash
# Morning routine — one command does everything:
hpc-reconnect
```

```
[1/4] Checking VPN...
  ✓ VPN connected (14h 30m remaining)
[2/4] Checking HPC access...
  ✓ Jump host reachable
[3/4] Checking SLURM job...
  ✓ Submitted job 29016001
  ... waiting for node allocation...
  ✓ Job running on c1101a-s17 (waited 30s)
[4/4] Setting up tunnels to c1101a-s17...
  Tunnels active → c1101a-s17

═══════════════════════════════════════
  HPC pipeline ready
═══════════════════════════════════════
  Node:  c1101a-s17
  Job:   29016001
  LLM:   localhost:18080
  ASR:   localhost:18082
  TTS:   localhost:18083
```

Or switch nodes manually:
```bash
hpc-node c1101a-s17        # switch to specific node
hpc-node --auto             # auto-detect from SLURM
```

## Architecture

```
[HPC Compute Node]           [Your Machine]           [Remote Workstation]
 :8080 LLM          ←──SSH──  :18080        ──SSH──→   :18080
 :8082 ASR          (forward) :18082       (reverse)   :18082
 :8083 TTS                    :18083                   :18083
        ↑
   [Jump Host]
   (ProxyJump)
        ↑
   [EduVPN]  ← auto-authenticated via Playwright
```

**Pipeline stages:**
1. **VPN** — Checks EduVPN, auto-reconnects (silent refresh or Playwright browser automation)
2. **HPC** — Verifies jump host is reachable
3. **SLURM** — Detects running jobs or submits a new one, waits for node allocation
4. **Tunnels** — Systemd services with auto-reconnect, optional reverse tunnel to workstation

## Install

```bash
git clone https://github.com/AndreTregear/SupercomputerReconnect.git
cd SupercomputerReconnect
bash install.sh
```

### Requirements

- Linux with systemd (Debian, Ubuntu, Fedora, etc.)
- SSH access to HPC jump host + compute nodes
- Node.js + npm (for EduVPN browser automation)
- `eduvpn-cli` (if your HPC requires EduVPN)

### What the installer does

1. Asks for HPC connection details (jump host, user, key, ports)
2. Optionally configures a remote workstation for reverse tunnels
3. Optionally sets up EduVPN auto-authentication (credentials stored locally in `~/.config/hpc-tunnel.env`, mode 600)
4. Installs `hpc-node` and `hpc-reconnect` to `~/.local/bin/`
5. Sets up systemd user services for persistent tunnels
6. Installs Playwright + Chromium for headless VPN auth

## Usage

### Full pipeline
```bash
hpc-reconnect               # VPN → job → tunnels, all automatic
```

### Tunnel management
```bash
hpc-node                    # Show current node and tunnel status
hpc-node c1100a-s15         # Switch to a specific node
hpc-node --auto             # Auto-detect node from SLURM queue
hpc-node --start            # Start tunnels
hpc-node --stop             # Stop tunnels
hpc-node --restart          # Restart tunnels
hpc-node --status           # Show systemd service status
```

## Configuration

### Connection config: `~/.config/hpc-tunnel.conf`

```ini
HPC_NODE=c1100a-s15
HPC_USER=username
HPC_JUMP=myjumphost
HPC_KEY=/home/user/.ssh/id_ed25519
SLURM_JOB_SCRIPT=/home/username/my_job.sh
WORKSTATION=my.workstation.com
WORKSTATION_USER=me
WORKSTATION_KEY=/home/user/.ssh/id_ed25519
LLM_PORT=18080
ASR_PORT=18082
TTS_PORT=18083
HPC_LLM_PORT=8080
HPC_ASR_PORT=8082
HPC_TTS_PORT=8083
```

### Credentials: `~/.config/hpc-tunnel.env`

```ini
# Created by install.sh, mode 600, never committed
IDP_USER=youruser
IDP_PASS=yourpassword
```

## How EduVPN auto-auth works

1. `hpc-reconnect` checks if EduVPN is connected
2. If not, tries `eduvpn-cli connect` (uses cached refresh token — no browser needed)
3. If the refresh token is expired, starts `eduvpn-cli renew`, captures the OAuth URL, and launches a headless Chromium via Playwright to complete the Shibboleth/SAML login automatically
4. The IdP callback hits the local loopback server and eduvpn-cli completes the token exchange

## Uninstall

```bash
systemctl --user disable --now hpc-tunnel-forward hpc-tunnel-reverse
rm ~/.local/bin/hpc-node ~/.local/bin/hpc-reconnect ~/.local/bin/hpc-tunnel-*.sh
rm -rf ~/.local/share/hpc-reconnect
rm ~/.config/systemd/user/hpc-tunnel-*.service
rm ~/.config/hpc-tunnel.conf ~/.config/hpc-tunnel.env
systemctl --user daemon-reload
```

## License

MIT
