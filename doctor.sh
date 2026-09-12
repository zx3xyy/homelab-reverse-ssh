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

if ((failures)); then
  printf '\nRecent logs:\n'
  journalctl -u homelab-reverse-ssh -n 20 --no-pager 2>/dev/null || true
  exit 1
fi
printf '\nAll local checks passed.\n'
