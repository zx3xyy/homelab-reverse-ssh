# homelab-reverse-ssh

[![CI](https://github.com/zx3xyy/homelab-reverse-ssh/actions/workflows/ci.yml/badge.svg)](https://github.com/zx3xyy/homelab-reverse-ssh/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Reach a NATed Home Lab through a public VPS with reconnecting SSH and Eternal Terminal sessions.

```text
Laptop -- SSH / ProxyJump --> VPS <-- persistent reverse SSH -- Home Lab
```

- No router port forwarding, public home IP, or VPN
- Automatic startup and reconnection with systemd and autossh
- Eternal Terminal sessions survive laptop sleep and TCP disconnects
- Dedicated tunnel key and least-privilege VPS account
- Home Lab ports remain bound to VPS loopback only

> Use this only where access to personal infrastructure is permitted. Port 443 support is not intended to bypass organizational policy.

## Requirements

- VPS and Home Lab: Ubuntu 20.04+ or Debian 11+
- An existing sudo-capable VPS SSH account
- Laptop: macOS, OpenSSH, and Homebrew (Homebrew is only needed for Eternal Terminal)

## Setup

Run on the Home Lab:

```bash
git clone https://github.com/zx3xyy/homelab-reverse-ssh.git
cd homelab-reverse-ssh

./setup.sh \
  --vps-host VPS_IP_OR_DOMAIN \
  --vps-user VPS_USER
```

This configures both machines and creates:

```text
VPS 127.0.0.1:22022 -> Home Lab localhost:22
VPS 127.0.0.1:22023 -> Home Lab Eternal Terminal
```

It also installs an Eternal Terminal jump server on VPS TCP `2022`. Allow that port in the VPS cloud firewall or security group. Use `--without-et` to keep an SSH-only installation.

If TCP 22 is unavailable and VPS port 443 is free:

```bash
./setup.sh \
  --vps-host VPS_IP_OR_DOMAIN \
  --vps-user VPS_USER \
  --public-port 443
```

If the VPS uses a cloud firewall or security group, allow the selected public SSH port there.

The first run generates a dedicated setup key and asks for the VPS login password once. Subsequent setup runs are passwordless; `sudo` may still prompt on the VPS.

## Connect from the laptop

No configuration file needs to be copied. Clone the repository on the laptop and generate the matching SSH configuration locally:

```bash
git clone https://github.com/zx3xyy/homelab-reverse-ssh.git
cd homelab-reverse-ssh

./install-client.sh \
  --vps-host VPS_IP_OR_DOMAIN \
  --vps-user VPS_USER \
  --homelab-user HOMELAB_USER

ssh homelab
homelab-et
```

The installer generates `~/.ssh/homelab_client_ed25519` and copies it to both the VPS and Home Lab. Enter each machine's current password once; future `ssh homelab` connections are passwordless. Use `--skip-key-copy` if keys are managed separately.

`homelab-et` reconnects the same terminal after laptop sleep or a temporary network loss. Keep `ssh homelab` for file transfer, VS Code Remote SSH, and recovery. To opt out, pass `--without-et` to both installers.

## Operations

```bash
# Diagnose from the Home Lab
./doctor.sh
sudo journalctl -u homelab-reverse-ssh -f

# Show all setup options
./setup.sh --help

# Remove the Home Lab service
sudo ./uninstall-homelab.sh

# Remove the VPS relay configuration (run on the VPS)
sudo ./scripts/uninstall-vps.sh
```

Re-run both installers with the same arguments to update an existing installation. Updates preserve existing keys, unmanaged SSH configuration, and the original `ssh homelab` path; Eternal Terminal is added as a separate service and command.

For recovery after a physical power outage, enable **Power On After AC Loss** (or the equivalent option) in the Home Lab BIOS/UEFI.

## Security

- The VPS reverse port listens only on `localhost`.
- The Home Lab Eternal Terminal server listens only on `localhost`; its VPS endpoint is reached through a separate restricted reverse tunnel.
- The tunnel user cannot open a TTY, forward an agent, use X11, or create local forwards.
- `PermitListen` restricts it to the configured reverse port.
- Host keys are pinned before the persistent service starts.
- New sshd configuration is validated before reload and rolled back on failure.

The host OpenSSH and systemd services are used directly; Docker would add networking, volume, and daemon dependencies to a recovery path.

See [SECURITY.md](SECURITY.md) for vulnerability reporting and [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## License

[MIT](LICENSE)
