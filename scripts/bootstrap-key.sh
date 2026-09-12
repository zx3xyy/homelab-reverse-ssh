#!/usr/bin/env bash
set -Eeuo pipefail

HOST=""
REMOTE_USER=""
PORT=22
IDENTITY="${HOME}/.ssh/homelab_vps_admin_ed25519"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && ((1 <= 10#$1 && 10#$1 <= 65535)); }

while (($#)); do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --user) REMOTE_USER="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --identity) IDENTITY="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: bootstrap-key.sh --host HOST --user USER [--port 22] [--identity PATH]"
      exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ "$HOST" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || die "Invalid --host"
[[ "$REMOTE_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "Invalid --user"
valid_port "$PORT" || die "Invalid --port"
[[ "$IDENTITY" = /* && ! "$IDENTITY" =~ [[:space:]] ]] || die "--identity must be an absolute path without whitespace"

for cmd in ssh ssh-keygen base64; do
  command -v "$cmd" >/dev/null || die "Missing command: $cmd"
done

mkdir -p "$(dirname "$IDENTITY")"
chmod 700 "$(dirname "$IDENTITY")"
if [[ ! -f "$IDENTITY" ]]; then
  printf 'Generating dedicated VPS setup key: %s\n' "$IDENTITY"
  ssh-keygen -q -t ed25519 -N '' -C "homelab-vps-admin" -f "$IDENTITY"
elif [[ ! -f "$IDENTITY.pub" ]]; then
  ssh-keygen -y -f "$IDENTITY" > "$IDENTITY.pub"
fi
chmod 600 "$IDENTITY"
chmod 644 "$IDENTITY.pub"

SSH_ARGS=(-p "$PORT" -i "$IDENTITY" -o IdentitiesOnly=yes)
TARGET="$REMOTE_USER@$HOST"
if ssh "${SSH_ARGS[@]}" -o BatchMode=yes "$TARGET" true >/dev/null 2>&1; then
  printf 'Passwordless VPS access already works.\n'
  exit 0
fi

printf 'Installing the setup key on %s (enter the VPS password once)...\n' "$TARGET"
KEY_B64="$(base64 < "$IDENTITY.pub" | tr -d '\n')"
REMOTE_COMMAND="umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; key=\$(printf '%s' '$KEY_B64' | base64 -d); grep -qxF \"\$key\" ~/.ssh/authorized_keys || printf '%s\\n' \"\$key\" >> ~/.ssh/authorized_keys"
ssh "${SSH_ARGS[@]}" "$TARGET" "$REMOTE_COMMAND"
ssh "${SSH_ARGS[@]}" -o BatchMode=yes "$TARGET" true >/dev/null 2>&1 \
  || die "Passwordless VPS key verification failed"
printf 'Passwordless VPS access is ready.\n'
