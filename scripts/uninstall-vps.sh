#!/usr/bin/env bash
set -Eeuo pipefail

TUNNEL_USER="${1:-homelab-tunnel}"
[[ "$EUID" -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }
[[ "$TUNNEL_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { echo "Invalid user" >&2; exit 1; }

if [[ -f /etc/homelab-reverse-ssh/et-managed ]]; then
  systemctl disable --now homelab-reverse-ssh-etserver 2>/dev/null || true
  rm -f /etc/systemd/system/homelab-reverse-ssh-etserver.service
fi
rm -rf /etc/homelab-reverse-ssh
rm -f /etc/ssh/sshd_config.d/90-homelab-reverse-ssh.conf
sshd -t
systemctl reload ssh
if id "$TUNNEL_USER" >/dev/null 2>&1; then
  userdel --remove "$TUNNEL_USER"
fi
systemctl daemon-reload
echo "Removed managed VPS relay services and user $TUNNEL_USER. Packages and UFW rules were kept."
