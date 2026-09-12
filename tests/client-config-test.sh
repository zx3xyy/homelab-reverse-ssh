#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT

cat > "$TMP_DIR/generated" <<'EOF'
Host test-vps
    HostName 203.0.113.10
    User relay
    Port 443

Host test-homelab
    HostName localhost
    User testuser
    Port 22022
    ProxyJump test-vps
EOF

mkdir -p "$TMP_DIR/.ssh"
printf 'Host existing\n    HostName example.com\n' > "$TMP_DIR/.ssh/config"
HOME="$TMP_DIR" "$ROOT/install-client.sh" \
  --config "$TMP_DIR/generated" \
  --target "$TMP_DIR/.ssh/config" >/dev/null

grep -q '^# BEGIN homelab-reverse-ssh$' "$TMP_DIR/.ssh/config"
grep -q '^Host test-homelab$' "$TMP_DIR/.ssh/config"
test "$(grep -c '^# BEGIN homelab-reverse-ssh$' "$TMP_DIR/.ssh/config")" -eq 1

HOME="$TMP_DIR" "$ROOT/install-client.sh" \
  --config "$TMP_DIR/generated" \
  --target "$TMP_DIR/.ssh/config" >/dev/null
test "$(grep -c '^# BEGIN homelab-reverse-ssh$' "$TMP_DIR/.ssh/config")" -eq 1

echo "Client config test passed."
