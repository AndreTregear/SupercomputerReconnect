# SupercomputerReconnect

Persistent SSH tunnels to HPC compute nodes that survive daily SLURM job changes. Switch nodes with one command.

Built for researchers who run services (LLM inference, ASR, TTS, Jupyter, etc.) on HPC nodes that change every day when jobs are resubmitted.

## The Problem

HPC jobs land on different compute nodes each time. You SSH in, set up port forwards, and when the job expires and you resubmit — everything breaks. You redo the tunnels manually. Every. Single. Day.

## The Solution

```bash
# New job landed on a different node? One command:
hpc-node c1101a-s17

# Or let it figure it out from SLURM:
hpc-node --auto
```

That's it. Systemd services handle the tunnels, auto-reconnect on drops, and the reverse tunnel pushes your HPC services to a remote workstation.

## Architecture

```
[HPC Compute Node]           [Your Machine]           [Remote Workstation]
 :8080 LLM          ←──SSH──  :18080        ──SSH──→   :18080
 :8082 ASR          (forward) :18082       (reverse)   :18082
 :8083 TTS                    :18083                   :18083
        ↑
   [Jump Host]
   (ProxyJump)
```

- **Forward tunnel**: Your machine → jump host → compute node
- **Reverse tunnel** (optional): Your machine → remote workstation
- **Systemd**: Auto-restart on failure, survives reboots

## Install

```bash
git clone https://github.com/AndreTregear/SupercomputerReconnect.git
cd SupercomputerReconnect
bash install.sh
```

The installer will ask for:
- HPC jump host alias and credentials
- Current compute node name
- Port mappings (defaults: 18080→8080, 18082→8082, 18083→8083)
- Optional remote workstation for reverse tunnel

## Usage

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

Config lives at `~/.config/hpc-tunnel.conf`:

```ini
HPC_NODE=c1100a-s15
HPC_USER=username
HPC_JUMP=myjumphost
HPC_KEY=/home/user/.ssh/id_ed25519
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

Edit directly or re-run `install.sh` to reconfigure.

## Uninstall

```bash
systemctl --user disable --now hpc-tunnel-forward hpc-tunnel-reverse
rm ~/.local/bin/hpc-node ~/.local/bin/hpc-tunnel-*.sh
rm ~/.config/systemd/user/hpc-tunnel-*.service
rm ~/.config/hpc-tunnel.conf
systemctl --user daemon-reload
```

## Requirements

- Linux with systemd (Debian, Ubuntu, Fedora, etc.)
- SSH access to HPC jump host + compute nodes
- Optional: SSH access to a remote workstation for reverse tunnels

## License

MIT
