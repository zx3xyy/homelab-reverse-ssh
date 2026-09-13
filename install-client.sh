#!/usr/bin/env bash
set -Eeuo pipefail

VPS_HOST=""
VPS_USER=""
HOMELAB_USER=""
PUBLIC_PORT=22
REMOTE_PORT=22022
CLIENT_ALIAS="homelab"
VPS_ALIAS="homelab-vps"
TARGET="${HOME}/.ssh/config"
IDENTITY="${HOME}/.ssh/homelab_client_ed25519"
COPY_KEYS=1
WITH_ET=1
ET_PUBLIC_PORT=2022
ET_REMOTE_PORT=22023
ET_ALIAS=""
BEGIN_MARKER="# BEGIN homelab-reverse-ssh"
END_MARKER="# END homelab-reverse-ssh"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && ((1 <= 10#$1 && 10#$1 <= 65535)); }
valid_name() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }
valid_alias() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }
valid_host() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; }

usage() {
  cat <<'EOF'
Usage:
  ./install-client.sh --vps-host HOST --vps-user USER --homelab-user USER [options]

Options:
  --public-port PORT   VPS SSH port (default: 22)
  --remote-port PORT   VPS loopback reverse port (default: 22022)
  --alias NAME         Home Lab SSH alias (default: homelab)
  --vps-alias NAME     VPS SSH alias (default: homelab-vps)
  --identity PATH      Client key (default: ~/.ssh/homelab_client_ed25519)
  --target PATH        SSH config path (default: ~/.ssh/config)
  --skip-key-copy      Configure SSH without generating or installing a key
  --et-public-port PORT  Public ET jump-server port (default: 2022)
  --et-remote-port PORT  VPS loopback ET reverse port (default: 22023)
  --et-alias NAME        ET command name (default: ALIAS-et)
  --without-et           Skip Eternal Terminal setup (enabled by default)
EOF
}

while (($#)); do
  case "$1" in
    --vps-host) VPS_HOST="${2:-}"; shift 2 ;;
    --vps-user) VPS_USER="${2:-}"; shift 2 ;;
    --homelab-user) HOMELAB_USER="${2:-}"; shift 2 ;;
    --public-port) PUBLIC_PORT="${2:-}"; shift 2 ;;
    --remote-port) REMOTE_PORT="${2:-}"; shift 2 ;;
    --alias) CLIENT_ALIAS="${2:-}"; shift 2 ;;
    --vps-alias) VPS_ALIAS="${2:-}"; shift 2 ;;
    --identity) IDENTITY="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --skip-key-copy) COPY_KEYS=0; shift ;;
    --et-public-port) ET_PUBLIC_PORT="${2:-}"; shift 2 ;;
    --et-remote-port) ET_REMOTE_PORT="${2:-}"; shift 2 ;;
    --et-alias) ET_ALIAS="${2:-}"; shift 2 ;;
    --without-et) WITH_ET=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

valid_host "$VPS_HOST" || die "--vps-host must be an IPv4 address or DNS name"
valid_name "$VPS_USER" || die "Invalid --vps-user"
valid_name "$HOMELAB_USER" || die "Invalid --homelab-user"
valid_port "$PUBLIC_PORT" || die "Invalid --public-port"
valid_port "$REMOTE_PORT" || die "Invalid --remote-port"
valid_alias "$CLIENT_ALIAS" || die "Invalid --alias"
valid_alias "$VPS_ALIAS" || die "Invalid --vps-alias"
ET_ALIAS="${ET_ALIAS:-$CLIENT_ALIAS-et}"
if ((WITH_ET)); then
  valid_port "$ET_PUBLIC_PORT" || die "Invalid --et-public-port"
  valid_port "$ET_REMOTE_PORT" || die "Invalid --et-remote-port"
  valid_alias "$ET_ALIAS" || die "Invalid --et-alias"
  [[ "$ET_PUBLIC_PORT" != "$PUBLIC_PORT" ]] || die "ET and SSH public ports must differ"
  [[ "$ET_REMOTE_PORT" != "$REMOTE_PORT" ]] || die "ET and SSH reverse ports must differ"
fi
[[ "$IDENTITY" = /* && ! "$IDENTITY" =~ [[:space:]] ]] || die "--identity must be an absolute path without whitespace"
[[ "$TARGET" = /* ]] || die "--target must be an absolute path"
for cmd in ssh ssh-keygen base64; do
  command -v "$cmd" >/dev/null || die "Missing command: $cmd"
done

mkdir -p "$(dirname "$TARGET")"
chmod 700 "$(dirname "$TARGET")"
touch "$TARGET"
chmod 600 "$TARGET"
BACKUP="$TARGET.backup.$(date +%Y%m%d%H%M%S)"
cp -a "$TARGET" "$BACKUP"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT
CLEAN_CONFIG="$TMP_DIR/ssh-config"
awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
  $0 == begin {skip=1; next}
  $0 == end {skip=0; next}
  !skip {print}
' "$TARGET" > "$CLEAN_CONFIG"

for host_alias in "$VPS_ALIAS" "$CLIENT_ALIAS"; do
  if awk -v host="$host_alias" '
    /^[[:space:]]*Host[[:space:]]+/ {
      for (i=2; i<=NF; i++) if ($i == host) found=1
    }
    END {exit !found}
  ' "$CLEAN_CONFIG"; then
    die "Host $host_alias already exists outside the managed block in $TARGET"
  fi
done

{
  cat "$CLEAN_CONFIG"
  printf '\n%s\n' "$BEGIN_MARKER"
  cat <<EOF
Host $VPS_ALIAS
    HostName $VPS_HOST
    User $VPS_USER
    Port $PUBLIC_PORT
    IdentityFile $IDENTITY
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 3

Host $CLIENT_ALIAS
    HostName localhost
    User $HOMELAB_USER
    Port $REMOTE_PORT
    ProxyJump $VPS_ALIAS
    IdentityFile $IDENTITY
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 3
EOF
  printf '%s\n' "$END_MARKER"
} > "$TARGET"
chmod 600 "$TARGET"

if ! ssh -G -F "$TARGET" "$CLIENT_ALIAS" >/dev/null 2>&1; then
  cp -a "$BACKUP" "$TARGET"
  die "SSH rejected the generated configuration; the previous config was restored"
fi

install_public_key() {
  local host="$1"
  local key_b64 remote_command

  if ssh -F "$TARGET" -i "$IDENTITY" -o IdentitiesOnly=yes -o BatchMode=yes "$host" true >/dev/null 2>&1; then
    printf 'Key access already works: %s\n' "$host"
    return
  fi

  printf '\nInstalling the client key on %s (enter its current password once)...\n' "$host"
  key_b64="$(base64 < "$IDENTITY.pub" | tr -d '\n')"
  remote_command="umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; key=\$(printf '%s' '$key_b64' | base64 -d); grep -qxF \"\$key\" ~/.ssh/authorized_keys || printf '%s\\n' \"\$key\" >> ~/.ssh/authorized_keys"
  ssh -F "$TARGET" -i "$IDENTITY" -o IdentitiesOnly=yes "$host" "$remote_command"
  ssh -F "$TARGET" -i "$IDENTITY" -o IdentitiesOnly=yes -o BatchMode=yes "$host" true >/dev/null 2>&1 \
    || die "Passwordless key verification failed for $host"
}

if ((COPY_KEYS)); then
  mkdir -p "$(dirname "$IDENTITY")"
  chmod 700 "$(dirname "$IDENTITY")"
  if [[ ! -f "$IDENTITY" ]]; then
    printf 'Generating dedicated client key: %s\n' "$IDENTITY"
    ssh-keygen -q -t ed25519 -N '' -C "homelab-client" -f "$IDENTITY"
  elif [[ ! -f "$IDENTITY.pub" ]]; then
    ssh-keygen -y -f "$IDENTITY" > "$IDENTITY.pub"
  fi
  chmod 600 "$IDENTITY"
  chmod 644 "$IDENTITY.pub"
  install_public_key "$VPS_ALIAS"
  install_public_key "$CLIENT_ALIAS"
fi

printf '\nInstalled. Future connections are passwordless: ssh %s\n' "$CLIENT_ALIAS"

if ((WITH_ET)); then
  [[ "$(uname -s)" == "Darwin" ]] || die "SSH remains installed; automatic ET client setup requires macOS (or re-run with --without-et)"
  if ! command -v et >/dev/null 2>&1; then
    command -v brew >/dev/null 2>&1 || die "SSH remains installed; install Homebrew or re-run with --without-et"
    printf '\nInstalling Eternal Terminal with Homebrew...\n'
    brew install et
  fi
  command -v et >/dev/null 2>&1 || die "SSH remains installed, but the ET client was not found after installation"

  ET_BIN="$(command -v et)"
  WRAPPER_DIR="$(dirname "$ET_BIN")"
  if [[ ! -w "$WRAPPER_DIR" ]]; then
    WRAPPER_DIR="$HOME/.local/bin"
    mkdir -p "$WRAPPER_DIR"
    printf 'Note: %s is not on PATH; invoke the ET wrapper by its full path.\n' "$WRAPPER_DIR"
  fi
  ET_WRAPPER="$WRAPPER_DIR/$ET_ALIAS"
  if [[ -e "$ET_WRAPPER" ]] && ! grep -q '^# Managed by homelab-reverse-ssh$' "$ET_WRAPPER" 2>/dev/null; then
    die "SSH and ET remain installed, but $ET_WRAPPER already exists and was not overwritten"
  fi
  ET_WRAPPER_TMP="$TMP_DIR/$ET_ALIAS"
  cat > "$ET_WRAPPER_TMP" <<EOF
#!/usr/bin/env bash
# Managed by homelab-reverse-ssh
exec "$ET_BIN" "$CLIENT_ALIAS:$ET_REMOTE_PORT" --jport "$ET_PUBLIC_PORT" "\$@"
EOF
  install -m 755 "$ET_WRAPPER_TMP" "$ET_WRAPPER"
  printf 'Persistent terminal installed: %s\n' "$ET_WRAPPER"
fi
