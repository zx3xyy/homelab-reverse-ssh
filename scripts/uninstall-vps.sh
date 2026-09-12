#!/usr/bin/env bash
set -Eeuo pipefail

TUNNEL_USER="${1:-homelab-tunnel}"
[[ "$EUID" -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }
[[ "$TUNNEL_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { echo "Invalid user" >&2; exit 1; }

rm -f /etc/ssh/sshd_config.d/90-homelab-reverse-ssh.conf
sshd -t
systemctl reload ssh
if id "$TUNNEL_USER" >/dev/null 2>&1; then
  userdel --remove "$TUNNEL_USER"
fi
echo "Removed VPS relay configuration and user $TUNNEL_USER. UFW rules, if any, were kept."
