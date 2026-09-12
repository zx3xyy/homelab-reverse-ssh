#!/usr/bin/env bash
set -Eeuo pipefail

[[ "$EUID" -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }
systemctl disable --now homelab-reverse-ssh 2>/dev/null || true
rm -f /etc/systemd/system/homelab-reverse-ssh.service
rm -rf /etc/homelab-reverse-ssh
systemctl daemon-reload
echo "Removed the Home Lab tunnel service. The dedicated key in the user's ~/.ssh was kept."
