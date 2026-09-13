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
  --without-et \
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
  --without-et \
  --target "$TMP_DIR/.ssh/config" >/dev/null
test "$(grep -c '^# BEGIN homelab-reverse-ssh$' "$TMP_DIR/.ssh/config")" -eq 1

grep -q '^Host existing$' "$TMP_DIR/.ssh/config"

FAKE_BIN="$TMP_DIR/fake-bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
cat > "$FAKE_BIN/et" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ET_TEST_LOG"
EOF
chmod +x "$FAKE_BIN/uname" "$FAKE_BIN/et"

HOME="$TMP_DIR" PATH="$FAKE_BIN:$PATH" "$ROOT/install-client.sh" \
  --vps-host 203.0.113.10 \
  --vps-user relay \
  --homelab-user testuser \
  --public-port 443 \
  --alias test-homelab \
  --vps-alias test-vps \
  --skip-key-copy \
  --target "$TMP_DIR/.ssh/config" >/dev/null

test -x "$FAKE_BIN/test-homelab-et"
grep -q '^# Managed by homelab-reverse-ssh$' "$FAKE_BIN/test-homelab-et"
ET_TEST_LOG="$TMP_DIR/et-args" "$FAKE_BIN/test-homelab-et" --verbose
sed -n '1p' "$TMP_DIR/et-args" | grep -qx 'test-homelab:22023'
sed -n '2p' "$TMP_DIR/et-args" | grep -qx -- '--jport'
sed -n '3p' "$TMP_DIR/et-args" | grep -qx '2022'
sed -n '4p' "$TMP_DIR/et-args" | grep -qx -- '--ssh-option'
sed -n '5p' "$TMP_DIR/et-args" | grep -qx "IdentityFile=$TMP_DIR/.ssh/homelab_client_ed25519"
sed -n '6p' "$TMP_DIR/et-args" | grep -qx -- '--ssh-option'
sed -n '7p' "$TMP_DIR/et-args" | grep -qx 'IdentitiesOnly=yes'
sed -n '8p' "$TMP_DIR/et-args" | grep -qx -- '--ssh-option'
sed -n '9p' "$TMP_DIR/et-args" | grep -qx 'BatchMode=yes'
sed -n '10p' "$TMP_DIR/et-args" | grep -qx -- '--verbose'
grep -q '^Host existing$' "$TMP_DIR/.ssh/config"
test "$(grep -c '^# BEGIN homelab-reverse-ssh$' "$TMP_DIR/.ssh/config")" -eq 1

echo "Client config test passed."
