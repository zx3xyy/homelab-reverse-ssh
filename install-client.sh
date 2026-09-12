#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG=""
TARGET="${HOME}/.ssh/config"
BEGIN_MARKER="# BEGIN homelab-reverse-ssh"
END_MARKER="# END homelab-reverse-ssh"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    --config) CONFIG="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: ./install-client.sh --config PATH [--target ~/.ssh/config]"
      exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "$CONFIG" && -f "$CONFIG" ]] || die "Pass an existing generated file with --config"
command -v ssh >/dev/null || die "OpenSSH client is required"
CLIENT_HOST="$(awk '/^[[:space:]]*Host[[:space:]]+/ {host=$2} END {print host}' "$CONFIG")"
[[ -n "$CLIENT_HOST" ]] || die "Generated config does not contain a Host entry"

mkdir -p "$(dirname "$TARGET")"
chmod 700 "$(dirname "$TARGET")"
touch "$TARGET"
chmod 600 "$TARGET"
BACKUP="$TARGET.backup.$(date +%Y%m%d%H%M%S)"
cp -a "$TARGET" "$BACKUP"

TMP="$(mktemp)"
trap 'rm -f -- "$TMP"' EXIT
awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
  $0 == begin {skip=1; next}
  $0 == end {skip=0; next}
  !skip {print}
' "$TARGET" > "$TMP"
if awk -v host="$CLIENT_HOST" '
  /^[[:space:]]*Host[[:space:]]+/ {
    for (i=2; i<=NF; i++) if ($i == host) found=1
  }
  END {exit !found}
' "$TMP"; then
  die "Host $CLIENT_HOST already exists outside the managed block in $TARGET"
fi
{
  cat "$TMP"
  printf '\n%s\n' "$BEGIN_MARKER"
  cat "$CONFIG"
  printf '%s\n' "$END_MARKER"
} > "$TARGET"
chmod 600 "$TARGET"

if ! ssh -G -F "$TARGET" "$CLIENT_HOST" >/dev/null 2>&1; then
  cp -a "$BACKUP" "$TARGET"
  die "SSH rejected the generated configuration; the previous config was restored"
fi
printf 'Installed SSH config. Try: ssh %s\n' "$CLIENT_HOST"
