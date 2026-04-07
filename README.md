# SupercomputerReconnect

**One command to rule them all: VPN → SLURM → Tunnels.**

Persistent SSH tunnels to HPC compute nodes that survive daily SLURM job changes. Full automation from VPN authentication to job submission to port forwarding — with an interactive job builder.

Built by and for researchers running GPU workloads on university HPC clusters (HiPerGator, etc.) who are tired of the daily reconnect dance.

## Quick Start

```bash
git clone https://github.com/AndreTregear/SupercomputerReconnect.git
cd SupercomputerReconnect
bash hpc-setup
```

The interactive wizard walks you through everything:
1. Generates an SSH keypair and shows you what to paste on the login node
2. Tests the connection live
3. Configures port forwarding
4. Sets up EduVPN auto-authentication (optional)
5. Creates SLURM job templates
6. Installs systemd services for persistent tunnels

## Daily Workflow

```bash
# Morning: one command does everything
hpc-reconnect

# Or: submit a new job interactively
hpc-job

# Job landed on a new node? Switch tunnels:
hpc-node c1101a-s17

# Let it figure out the node:
hpc-node --auto
```

## What `hpc-reconnect` Does

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

## What `hpc-job` Does

```
╔══════════════════════════════════════════════════╗
║  hpc-job — SLURM Job Builder                     ║
╚══════════════════════════════════════════════════╝

Current Jobs
────────────────────────────────────────
  29015496  hpg-b200   research     RUNNING  8:56:50  c1100a-s15

Saved Job Templates
────────────────────────────────────────
  [1] gpu-1day          hpg-b200  gpu=1  mem=64gb  time=1-00:00:00
  [2] dev-2hr           hpg-dev   gpu=1  mem=32gb  time=2:00:00

Available Partitions
────────────────────────────────────────
  #    Partition              GPU                Time       Nodes
  [1]  hpg-b200              gres:gpu:b200:4    1-00:00:00 12
  [2]  hpg-ai                gres:gpu:a100:8    7-00:00:00 45
  ...

What do you want to do?

  [T] Submit a saved template
  [N] Build a new job
  [R] Re-submit last job
  [C] Connect to existing running job
  [Q] Quit
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
              (WAYF → CAS/Shibboleth → Duo MFA → callback)
```

## Commands

| Command | Description |
|---------|-------------|
| `hpc-setup` | Interactive first-run wizard |
| `hpc-reconnect` | Full pipeline: VPN → job → tunnels |
| `hpc-job` | Interactive SLURM job builder |
| `hpc-job --new` | Build a new job directly |
| `hpc-job --submit NAME` | Submit a saved template |
| `hpc-job --list` | List saved templates |
| `hpc-node` | Show current node and status |
| `hpc-node NODE` | Switch to a specific node |
| `hpc-node --auto` | Auto-detect from SLURM |
| `hpc-node --stop` | Stop all tunnels |

## EduVPN Auto-Authentication

When your VPN session expires, `hpc-reconnect` handles the full re-auth automatically:

1. Tries silent reconnect (OAuth refresh token)
2. If expired, launches headless Chromium via Playwright
3. Navigates InCommon WAYF → selects your university
4. Completes Shibboleth/CAS login
5. Waits for Duo MFA push (you approve on your phone)
6. Clicks through device trust and attribute consent
7. OAuth callback completes → VPN connected

**Supported auth flows:**
- InCommon WAYF federation discovery
- Shibboleth / CAS / SAML IdPs
- Duo MFA (push notification)
- Attribute consent pages

## Configuration

### `~/.config/hpc-tunnel.conf`
Connection settings (no secrets).

### `~/.config/hpc-tunnel.env`
IdP credentials for VPN auto-auth (mode 600, gitignored).

### `~/.config/hpc-jobs/`
Saved SLURM job templates.

## Requirements

- Linux with systemd (Debian, Ubuntu, Fedora, etc.)
- SSH access to HPC
- Node.js (for EduVPN browser automation)
- `eduvpn-cli` (if your HPC requires EduVPN)

## Uninstall

```bash
hpc-node --stop
systemctl --user disable hpc-tunnel-forward hpc-tunnel-reverse 2>/dev/null
rm -f ~/.local/bin/hpc-{node,reconnect,job,setup,tunnel-*}
rm -rf ~/.local/share/hpc-reconnect
rm -f ~/.config/systemd/user/hpc-tunnel-*.service
rm -f ~/.config/hpc-tunnel.{conf,env}
rm -rf ~/.config/hpc-jobs
systemctl --user daemon-reload
```

## Contributing

PRs welcome! This tool was built for HiPerGator but should work with any SLURM-based HPC with SSH access.

## License

MIT
