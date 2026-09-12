# homelab-reverse-ssh

[![CI](https://github.com/zx3xyy/homelab-reverse-ssh/actions/workflows/ci.yml/badge.svg)](https://github.com/zx3xyy/homelab-reverse-ssh/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Reach a NATed Home Lab through a public VPS using only OpenSSH.

```text
Laptop -- SSH / ProxyJump --> VPS <-- persistent reverse SSH -- Home Lab
```

- No router port forwarding, public home IP, VPN, or laptop-side agent
- Automatic startup and reconnection with systemd and autossh
- Dedicated tunnel key and least-privilege VPS account
- Reverse port bound to VPS loopback only

> Use this only where access to personal infrastructure is permitted. Port 443 support is not intended to bypass organizational policy.

## Requirements

- VPS and Home Lab: Ubuntu 20.04+ or Debian 11+
- An existing sudo-capable VPS SSH account
- Laptop: OpenSSH with access to that VPS account

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
```

If TCP 22 is unavailable and VPS port 443 is free:

```bash
./setup.sh \
  --vps-host VPS_IP_OR_DOMAIN \
  --vps-user VPS_USER \
  --public-port 443
```

If the VPS uses a cloud firewall or security group, allow the selected public SSH port there.

## Connect from the laptop

Copy the generated `client-ssh-config` and this installer to the laptop, then run:

```bash
./install-client.sh --config ./client-ssh-config
ssh homelab
```

The laptop must already have key-based access to `VPS_USER@VPS_IP_OR_DOMAIN`.

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

Re-run `setup.sh` with the same arguments to update the installation. It is idempotent and preserves the tunnel key.

For recovery after a physical power outage, enable **Power On After AC Loss** (or the equivalent option) in the Home Lab BIOS/UEFI.

## Security

- The VPS reverse port listens only on `localhost`.
- The tunnel user cannot open a TTY, forward an agent, use X11, or create local forwards.
- `PermitListen` restricts it to the configured reverse port.
- Host keys are pinned before the persistent service starts.
- New sshd configuration is validated before reload and rolled back on failure.

The host OpenSSH and systemd services are used directly; Docker would add networking, volume, and daemon dependencies to a recovery path.

See [SECURITY.md](SECURITY.md) for vulnerability reporting and [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## License

[MIT](LICENSE)
