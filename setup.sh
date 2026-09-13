#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

VPS_HOST=""
VPS_USER=""
ADMIN_PORT=22
PUBLIC_PORT=""
REMOTE_PORT=22022
TUNNEL_USER="homelab-tunnel"
HOMELAB_USER="${SUDO_USER:-${USER:-}}"
CLIENT_ALIAS="homelab"
VPS_ALIAS="homelab-vps"
IDENTITY_PATH=""
ADMIN_IDENTITY_PATH=""
WITH_ET=1
ET_PUBLIC_PORT=2022
ET_REMOTE_PORT=22023
ET_LOCAL_PORT=2022

usage() {
  cat <<'EOF'
Usage:
  ./setup.sh --vps-host HOST --vps-user USER [options]

Options:
  --vps-host HOST        VPS IP or DNS name (required)
  --vps-user USER        Existing VPS sudo-capable user (required)
  --admin-port PORT      Existing VPS SSH port (default: 22)
  --public-port PORT     Final SSH port for tunnel/client (default: admin port)
  --remote-port PORT     VPS loopback reverse port (default: 22022)
  --tunnel-user USER     Restricted VPS tunnel user (default: homelab-tunnel)
  --homelab-user USER    Final Home Lab login user (default: current user)
  --identity PATH        Tunnel private key (default: ~/.ssh/homelab_reverse_tunnel)
  --admin-identity PATH  Home Lab key for VPS setup (default: ~/.ssh/homelab_vps_admin_ed25519)
  --alias NAME           Client Home Lab alias (default: homelab)
  --vps-alias NAME       Client VPS alias (default: homelab-vps)
  --et-public-port PORT  Public ET jump-server port (default: 2022)
  --et-remote-port PORT  VPS loopback ET reverse port (default: 22023)
  --without-et           Skip Eternal Terminal setup (enabled by default)
  -h, --help             Show this help
EOF
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '\n==> %s\n' "$*"; }

valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && ((1 <= 10#$1 && 10#$1 <= 65535)); }
valid_name() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }
valid_alias() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }
valid_host() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; }

while (($#)); do
  case "$1" in
    --vps-host) VPS_HOST="${2:-}"; shift 2 ;;
    --vps-user) VPS_USER="${2:-}"; shift 2 ;;
    --admin-port) ADMIN_PORT="${2:-}"; shift 2 ;;
    --public-port) PUBLIC_PORT="${2:-}"; shift 2 ;;
    --remote-port) REMOTE_PORT="${2:-}"; shift 2 ;;
    --tunnel-user) TUNNEL_USER="${2:-}"; shift 2 ;;
    --homelab-user) HOMELAB_USER="${2:-}"; shift 2 ;;
    --identity) IDENTITY_PATH="${2:-}"; shift 2 ;;
    --admin-identity) ADMIN_IDENTITY_PATH="${2:-}"; shift 2 ;;
    --alias) CLIENT_ALIAS="${2:-}"; shift 2 ;;
    --vps-alias) VPS_ALIAS="${2:-}"; shift 2 ;;
    --et-public-port) ET_PUBLIC_PORT="${2:-}"; shift 2 ;;
    --et-remote-port) ET_REMOTE_PORT="${2:-}"; shift 2 ;;
    --without-et) WITH_ET=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "$VPS_HOST" ]] || die "--vps-host is required"
[[ -n "$VPS_USER" ]] || die "--vps-user is required"
[[ -n "$HOMELAB_USER" ]] || die "Could not determine Home Lab user; pass --homelab-user"
valid_host "$VPS_HOST" || die "Invalid --vps-host: $VPS_HOST (use an IPv4 address or DNS name)"
valid_name "$VPS_USER" || die "Invalid --vps-user: $VPS_USER"
PUBLIC_PORT="${PUBLIC_PORT:-$ADMIN_PORT}"
valid_port "$ADMIN_PORT" || die "Invalid --admin-port: $ADMIN_PORT"
valid_port "$PUBLIC_PORT" || die "Invalid --public-port: $PUBLIC_PORT"
valid_port "$REMOTE_PORT" || die "Invalid --remote-port: $REMOTE_PORT"
valid_name "$TUNNEL_USER" || die "Invalid --tunnel-user: $TUNNEL_USER"
valid_name "$HOMELAB_USER" || die "Invalid --homelab-user: $HOMELAB_USER"
valid_alias "$CLIENT_ALIAS" || die "Invalid --alias: $CLIENT_ALIAS"
valid_alias "$VPS_ALIAS" || die "Invalid --vps-alias: $VPS_ALIAS"
if ((WITH_ET)); then
  valid_port "$ET_PUBLIC_PORT" || die "Invalid --et-public-port: $ET_PUBLIC_PORT"
  valid_port "$ET_REMOTE_PORT" || die "Invalid --et-remote-port: $ET_REMOTE_PORT"
  [[ "$ET_PUBLIC_PORT" != "$PUBLIC_PORT" ]] || die "ET and SSH public ports must differ"
  [[ "$ET_PUBLIC_PORT" != "$REMOTE_PORT" ]] || die "ET public port conflicts with the SSH reverse port"
  [[ "$ET_REMOTE_PORT" != "$PUBLIC_PORT" ]] || die "ET reverse port conflicts with the SSH public port"
  [[ "$ET_REMOTE_PORT" != "$REMOTE_PORT" ]] || die "ET and SSH reverse ports must differ"
  [[ "$ET_REMOTE_PORT" != "$ET_PUBLIC_PORT" ]] || die "ET public and reverse ports must differ"
fi

for cmd in ssh scp ssh-keygen sudo base64 getent; do
  command -v "$cmd" >/dev/null || die "Missing command: $cmd"
done
[[ -f "$SCRIPT_DIR/scripts/install-vps.sh" ]] || die "Missing scripts/install-vps.sh"
[[ -x "$SCRIPT_DIR/scripts/bootstrap-key.sh" ]] || die "Missing scripts/bootstrap-key.sh"
[[ -x "$SCRIPT_DIR/scripts/install-et-server.sh" ]] || die "Missing scripts/install-et-server.sh"

USER_HOME="$(getent passwd "$HOMELAB_USER" | cut -d: -f6)"
[[ -n "$USER_HOME" && -d "$USER_HOME" ]] || die "Home directory not found for $HOMELAB_USER"
IDENTITY_PATH="${IDENTITY_PATH:-$USER_HOME/.ssh/homelab_reverse_tunnel}"
ADMIN_IDENTITY_PATH="${ADMIN_IDENTITY_PATH:-$USER_HOME/.ssh/homelab_vps_admin_ed25519}"
[[ "$IDENTITY_PATH" = /* ]] || die "--identity must be an absolute path"
[[ ! "$IDENTITY_PATH" =~ [[:space:]] ]] || die "--identity cannot contain whitespace"
[[ "$ADMIN_IDENTITY_PATH" = /* ]] || die "--admin-identity must be an absolute path"
[[ ! "$ADMIN_IDENTITY_PATH" =~ [[:space:]] ]] || die "--admin-identity cannot contain whitespace"

mkdir -p "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"
chown "$HOMELAB_USER":"$(id -gn "$HOMELAB_USER")" "$USER_HOME/.ssh"

log "Ensuring passwordless Home Lab access to the VPS"
BOOTSTRAP_ARGS=(
  --host "$VPS_HOST"
  --user "$VPS_USER"
  --port "$ADMIN_PORT"
  --identity "$ADMIN_IDENTITY_PATH"
)
if [[ "$EUID" -eq 0 && "$HOMELAB_USER" != root ]]; then
  sudo -u "$HOMELAB_USER" env HOME="$USER_HOME" \
    "$SCRIPT_DIR/scripts/bootstrap-key.sh" "${BOOTSTRAP_ARGS[@]}"
else
  "$SCRIPT_DIR/scripts/bootstrap-key.sh" "${BOOTSTRAP_ARGS[@]}"
fi

SSH_ADMIN=(ssh -p "$ADMIN_PORT" -i "$ADMIN_IDENTITY_PATH" -o IdentitiesOnly=yes -o ServerAliveInterval=15 -o ConnectTimeout=15)
SCP_ADMIN=(scp -P "$ADMIN_PORT" -i "$ADMIN_IDENTITY_PATH" -o IdentitiesOnly=yes)
VPS_TARGET="$VPS_USER@$VPS_HOST"

log "Checking the existing VPS login and recording its host key"
"${SSH_ADMIN[@]}" "$VPS_TARGET" true

if [[ ! -f "$IDENTITY_PATH" ]]; then
  ssh-keygen -q -t ed25519 -N '' -C "homelab-reverse-tunnel@$(hostname)" -f "$IDENTITY_PATH"
  chown "$HOMELAB_USER":"$(id -gn "$HOMELAB_USER")" "$IDENTITY_PATH" "$IDENTITY_PATH.pub"
fi
chmod 600 "$IDENTITY_PATH"
chmod 644 "$IDENTITY_PATH.pub"

PUBKEY_B64="$(base64 < "$IDENTITY_PATH.pub" | tr -d '\n')"
REMOTE_INSTALLER="/tmp/homelab-reverse-ssh-install-vps.$$"
REMOTE_ET_INSTALLER="/tmp/homelab-reverse-ssh-install-et.$$"

log "Installing the restricted relay configuration on the VPS"
"${SCP_ADMIN[@]}" "$SCRIPT_DIR/scripts/install-vps.sh" "$VPS_USER@$VPS_HOST:$REMOTE_INSTALLER"
if ((WITH_ET)); then
  "${SCP_ADMIN[@]}" "$SCRIPT_DIR/scripts/install-et-server.sh" "$VPS_USER@$VPS_HOST:$REMOTE_ET_INSTALLER"
fi
REMOTE_ARGS=(
  "$REMOTE_INSTALLER"
  --tunnel-user "$TUNNEL_USER"
  --public-ssh-port "$PUBLIC_PORT"
  --remote-port "$REMOTE_PORT"
  --public-key-b64 "$PUBKEY_B64"
)
if ((WITH_ET)); then
  REMOTE_ARGS+=(
    --with-et
    --et-public-port "$ET_PUBLIC_PORT"
    --et-remote-port "$ET_REMOTE_PORT"
    --et-installer "$REMOTE_ET_INSTALLER"
  )
fi
printf -v REMOTE_CMD '%q ' "${REMOTE_ARGS[@]}"
"${SSH_ADMIN[@]}" -t "$VPS_TARGET" "sudo bash $REMOTE_CMD; rc=\$?; rm -f $(printf '%q' "$REMOTE_INSTALLER") $(printf '%q' "$REMOTE_ET_INSTALLER"); exit \$rc"

log "Pinning the VPS host key for port $PUBLIC_PORT"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT
KNOWN_FROM_ADMIN="$TMP_DIR/admin_known_hosts"
SCANNED_PUBLIC="$TMP_DIR/public_known_hosts"
ADMIN_LOOKUP="$VPS_HOST"
[[ "$ADMIN_PORT" == 22 ]] || ADMIN_LOOKUP="[$VPS_HOST]:$ADMIN_PORT"
ssh-keygen -F "$ADMIN_LOOKUP" -f "$USER_HOME/.ssh/known_hosts" 2>/dev/null | grep -v '^#' > "$KNOWN_FROM_ADMIN" || true
[[ -s "$KNOWN_FROM_ADMIN" ]] || die "Could not find the trusted VPS host key in $USER_HOME/.ssh/known_hosts"
ssh-keyscan -T 10 -p "$PUBLIC_PORT" "$VPS_HOST" 2>/dev/null > "$SCANNED_PUBLIC"
[[ -s "$SCANNED_PUBLIC" ]] || die "Could not read the VPS host key on port $PUBLIC_PORT; check cloud firewall rules"

trusted_fingerprints() {
  ssh-keygen -lf "$1" -E sha256 2>/dev/null | awk '{print $2}' | sort -u
}
if ! comm -12 <(trusted_fingerprints "$KNOWN_FROM_ADMIN") <(trusted_fingerprints "$SCANNED_PUBLIC") | grep -q .; then
  die "Host key on port $PUBLIC_PORT does not match the already trusted VPS host key"
fi

LOCAL_CONFIG_DIR="/etc/homelab-reverse-ssh"
UNIT_PATH="/etc/systemd/system/homelab-reverse-ssh.service"
sudo install -d -m 755 "$LOCAL_CONFIG_DIR"
sudo install -m 644 "$SCANNED_PUBLIC" "$LOCAL_CONFIG_DIR/known_hosts"

log "Installing autossh and the boot-persistent systemd service"
if ! command -v autossh >/dev/null || ! command -v sshd >/dev/null; then
  sudo env DEBIAN_FRONTEND=noninteractive apt-get update -qq
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq autossh openssh-server
fi

AUTOSSH_BIN="$(command -v autossh)"
UNIT_TMP="$TMP_DIR/homelab-reverse-ssh.service"
cat > "$UNIT_TMP" <<EOF
[Unit]
Description=Persistent Home Lab reverse SSH tunnel
Documentation=https://man.openbsd.org/ssh
Wants=network-online.target
After=network-online.target ssh.service
StartLimitIntervalSec=0

[Service]
Type=simple
User=$HOMELAB_USER
Environment=AUTOSSH_GATETIME=0
ExecStart=$AUTOSSH_BIN -M 0 -N -T -p $PUBLIC_PORT -i $IDENTITY_PATH -o BatchMode=yes -o IdentitiesOnly=yes -o UserKnownHostsFile=$LOCAL_CONFIG_DIR/known_hosts -o StrictHostKeyChecking=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ConnectTimeout=10 -o ExitOnForwardFailure=yes -R localhost:$REMOTE_PORT:localhost:22 $TUNNEL_USER@$VPS_HOST
Restart=always
RestartSec=5s
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=full
ProtectHome=read-only

[Install]
WantedBy=multi-user.target
EOF
sudo install -m 644 "$UNIT_TMP" "$UNIT_PATH"
sudo systemctl daemon-reload
sudo systemctl enable --now ssh
sudo systemctl enable --now homelab-reverse-ssh

TUNNEL_READY=0
for _ in {1..10}; do
  if "${SSH_ADMIN[@]}" "$VPS_TARGET" "ss -H -ltn 'sport = :$REMOTE_PORT' | grep -q ."; then
    TUNNEL_READY=1
    break
  fi
  sleep 1
done
if ((TUNNEL_READY == 0)); then
  sudo systemctl status --no-pager homelab-reverse-ssh || true
  die "Tunnel did not open VPS localhost:$REMOTE_PORT"
fi

if ((WITH_ET)); then
  log "Installing Eternal Terminal on the Home Lab"
  sudo "$SCRIPT_DIR/scripts/install-et-server.sh" --bind-ip 127.0.0.1 --port "$ET_LOCAL_PORT"

  ET_TUNNEL_UNIT_PATH="/etc/systemd/system/homelab-reverse-ssh-et-tunnel.service"
  ET_TUNNEL_UNIT_TMP="$TMP_DIR/homelab-reverse-ssh-et-tunnel.service"
  cat > "$ET_TUNNEL_UNIT_TMP" <<EOF
[Unit]
Description=Persistent Eternal Terminal reverse tunnel
Documentation=https://github.com/MisterTea/EternalTerminal
Wants=network-online.target
After=network-online.target homelab-reverse-ssh-etserver.service
StartLimitIntervalSec=0

[Service]
Type=simple
User=$HOMELAB_USER
Environment=AUTOSSH_GATETIME=0
ExecStart=$AUTOSSH_BIN -M 0 -N -T -p $PUBLIC_PORT -i $IDENTITY_PATH -o BatchMode=yes -o IdentitiesOnly=yes -o UserKnownHostsFile=$LOCAL_CONFIG_DIR/known_hosts -o StrictHostKeyChecking=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ConnectTimeout=10 -o ExitOnForwardFailure=yes -R localhost:$ET_REMOTE_PORT:localhost:$ET_LOCAL_PORT $TUNNEL_USER@$VPS_HOST
Restart=always
RestartSec=5s
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=full
ProtectHome=read-only

[Install]
WantedBy=multi-user.target
EOF
  sudo install -m 644 "$ET_TUNNEL_UNIT_TMP" "$ET_TUNNEL_UNIT_PATH"
  sudo systemctl daemon-reload
  sudo systemctl enable homelab-reverse-ssh-et-tunnel
  sudo systemctl restart homelab-reverse-ssh-et-tunnel

  ET_TUNNEL_READY=0
  for _ in {1..10}; do
    if "${SSH_ADMIN[@]}" "$VPS_TARGET" "ss -H -ltn 'sport = :$ET_REMOTE_PORT' | grep -q ."; then
      ET_TUNNEL_READY=1
      break
    fi
    sleep 1
  done
  if ((ET_TUNNEL_READY == 0)); then
    sudo systemctl status --no-pager homelab-reverse-ssh-et-tunnel || true
    die "ET tunnel did not open VPS localhost:$ET_REMOTE_PORT"
  fi
fi

log "Setup complete"
printf 'Tunnel: %s@%s:%s -> VPS localhost:%s\n' "$TUNNEL_USER" "$VPS_HOST" "$PUBLIC_PORT" "$REMOTE_PORT"
printf '\nOn the laptop, clone this repository and run:\n'
CLIENT_INSTALL_ARGS=(
  ./install-client.sh
  --vps-host "$VPS_HOST"
  --vps-user "$VPS_USER"
  --homelab-user "$HOMELAB_USER"
  --public-port "$PUBLIC_PORT"
  --remote-port "$REMOTE_PORT"
  --alias "$CLIENT_ALIAS"
  --vps-alias "$VPS_ALIAS"
)
if ((WITH_ET)); then
  CLIENT_INSTALL_ARGS+=(--et-public-port "$ET_PUBLIC_PORT" --et-remote-port "$ET_REMOTE_PORT")
else
  CLIENT_INSTALL_ARGS+=(--without-et)
fi
printf '  '
printf '%q ' "${CLIENT_INSTALL_ARGS[@]}"
printf '\n'
printf '  ssh %s\n' "$CLIENT_ALIAS"
if ((WITH_ET)); then
  printf '  %s-et\n' "$CLIENT_ALIAS"
fi
