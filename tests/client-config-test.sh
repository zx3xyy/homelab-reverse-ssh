#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/.ssh"
printf 'Host existing\n    HostName example.com\n' > "$TMP_DIR/.ssh/config"
HOME="$TMP_DIR" "$ROOT/install-client.sh" \
  --vps-host 203.0.113.10 \
  --vps-user relay \
  --homelab-user testuser \
  --public-port 443 \
  --alias test-homelab \
  --vps-alias test-vps \
  --skip-key-copy \
  --target "$TMP_DIR/.ssh/config" >/dev/null

grep -q '^# BEGIN homelab-reverse-ssh$' "$TMP_DIR/.ssh/config"
grep -q '^Host test-homelab$' "$TMP_DIR/.ssh/config"
test "$(grep -c '^# BEGIN homelab-reverse-ssh$' "$TMP_DIR/.ssh/config")" -eq 1

HOME="$TMP_DIR" "$ROOT/install-client.sh" \
  --vps-host 203.0.113.10 \
  --vps-user relay \
  --homelab-user testuser \
  --public-port 443 \
  --alias test-homelab \
  --vps-alias test-vps \
  --skip-key-copy \
  --target "$TMP_DIR/.ssh/config" >/dev/null
test "$(grep -c '^# BEGIN homelab-reverse-ssh$' "$TMP_DIR/.ssh/config")" -eq 1

echo "Client config test passed."
