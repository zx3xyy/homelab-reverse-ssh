#!/usr/bin/env bash
set -Eeuo pipefail

[[ "$EUID" -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }
systemctl disable --now homelab-reverse-ssh 2>/dev/null || true
systemctl disable --now homelab-reverse-ssh-et-tunnel 2>/dev/null || true
if [[ -f /etc/homelab-reverse-ssh/et-managed ]]; then
  systemctl disable --now homelab-reverse-ssh-etserver 2>/dev/null || true
fi
rm -f /etc/systemd/system/homelab-reverse-ssh.service
rm -f /etc/systemd/system/homelab-reverse-ssh-et-tunnel.service
rm -f /etc/systemd/system/homelab-reverse-ssh-etserver.service
rm -rf /etc/homelab-reverse-ssh
systemctl daemon-reload
echo "Removed managed Home Lab tunnel services. Dedicated keys and installed packages were kept."
