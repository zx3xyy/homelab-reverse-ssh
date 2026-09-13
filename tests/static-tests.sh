#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

for file in \
  "$ROOT/setup.sh" \
  "$ROOT/install-client.sh" \
  "$ROOT/doctor.sh" \
  "$ROOT/uninstall-homelab.sh" \
  "$ROOT/scripts/install-et-server.sh" \
  "$ROOT/scripts/install-vps.sh" \
  "$ROOT/scripts/bootstrap-key.sh" \
  "$ROOT/scripts/uninstall-vps.sh"; do
  bash -n "$file"
done

"$ROOT/setup.sh" --help >/dev/null
"$ROOT/install-client.sh" --help >/dev/null
"$ROOT/scripts/bootstrap-key.sh" --help >/dev/null
"$ROOT/scripts/install-et-server.sh" --help >/dev/null
if "$ROOT/setup.sh" --vps-host 'bad host' --vps-user test >/dev/null 2>&1; then
  echo "Invalid VPS hostname was unexpectedly accepted" >&2
  exit 1
fi
"$ROOT/tests/client-config-test.sh"

if command -v shellcheck >/dev/null; then
  shellcheck -x \
    "$ROOT/setup.sh" \
    "$ROOT/install-client.sh" \
    "$ROOT/doctor.sh" \
    "$ROOT/uninstall-homelab.sh" \
    "$ROOT/scripts/install-et-server.sh" \
    "$ROOT/scripts/install-vps.sh" \
    "$ROOT/scripts/uninstall-vps.sh"
else
  echo "shellcheck not installed; skipped"
fi

echo "Static tests passed."
