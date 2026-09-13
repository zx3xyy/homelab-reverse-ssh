#!/usr/bin/env bash
set -u

failures=0
check() {
  label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '[OK]   %s\n' "$label"
  else
    printf '[FAIL] %s\n' "$label"
    failures=$((failures + 1))
  fi
}

check "OpenSSH server is active" systemctl is-active --quiet ssh
check "Reverse tunnel service is enabled" systemctl is-enabled --quiet homelab-reverse-ssh
check "Reverse tunnel service is active" systemctl is-active --quiet homelab-reverse-ssh
check "autossh is installed" command -v autossh
check "Pinned VPS host key exists" test -s /etc/homelab-reverse-ssh/known_hosts

if [[ -f /etc/systemd/system/homelab-reverse-ssh-et-tunnel.service ]]; then
  check "Eternal Terminal server is installed" command -v etserver
  check "ET reverse tunnel is enabled" systemctl is-enabled --quiet homelab-reverse-ssh-et-tunnel
  check "ET reverse tunnel is active" systemctl is-active --quiet homelab-reverse-ssh-et-tunnel
fi
if [[ -f /etc/homelab-reverse-ssh/et-managed ]]; then
  check "Eternal Terminal server is enabled" systemctl is-enabled --quiet homelab-reverse-ssh-etserver
  check "Eternal Terminal server is active" systemctl is-active --quiet homelab-reverse-ssh-etserver
fi

if ((failures)); then
  printf '\nRecent logs:\n'
  journalctl -u homelab-reverse-ssh -n 20 --no-pager 2>/dev/null || true
  exit 1
fi
printf '\nAll local checks passed.\n'
