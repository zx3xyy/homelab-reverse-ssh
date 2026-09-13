#!/usr/bin/env bash
set -Eeuo pipefail

TUNNEL_USER="homelab-tunnel"
PUBLIC_SSH_PORT=22
REMOTE_PORT=22022
PUBLIC_KEY_B64=""
WITH_ET=0
ET_PUBLIC_PORT=2022
ET_REMOTE_PORT=22023
ET_INSTALLER=""
DROPIN="/etc/ssh/sshd_config.d/90-homelab-reverse-ssh.conf"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '==> %s\n' "$*"; }
valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && ((1 <= 10#$1 && 10#$1 <= 65535)); }
valid_name() { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }

while (($#)); do
  case "$1" in
    --tunnel-user) TUNNEL_USER="${2:-}"; shift 2 ;;
    --public-ssh-port) PUBLIC_SSH_PORT="${2:-}"; shift 2 ;;
    --remote-port) REMOTE_PORT="${2:-}"; shift 2 ;;
    --public-key-b64) PUBLIC_KEY_B64="${2:-}"; shift 2 ;;
    --with-et) WITH_ET=1; shift ;;
    --et-public-port) ET_PUBLIC_PORT="${2:-}"; shift 2 ;;
    --et-remote-port) ET_REMOTE_PORT="${2:-}"; shift 2 ;;
    --et-installer) ET_INSTALLER="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: sudo install-vps.sh --public-key-b64 BASE64 [--tunnel-user USER] [--public-ssh-port PORT] [--remote-port PORT] [--with-et --et-installer PATH]"
      exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ "$EUID" -eq 0 ]] || die "Run as root"
valid_name "$TUNNEL_USER" || die "Invalid tunnel user"
valid_port "$PUBLIC_SSH_PORT" || die "Invalid public SSH port"
valid_port "$REMOTE_PORT" || die "Invalid remote port"
[[ -n "$PUBLIC_KEY_B64" ]] || die "--public-key-b64 is required"
if ((WITH_ET)); then
  valid_port "$ET_PUBLIC_PORT" || die "Invalid ET public port"
  valid_port "$ET_REMOTE_PORT" || die "Invalid ET remote port"
  [[ -f "$ET_INSTALLER" ]] || die "--et-installer must point to the uploaded ET installer"
  [[ "$ET_PUBLIC_PORT" != "$PUBLIC_SSH_PORT" ]] || die "ET and SSH public ports must differ"
  [[ "$ET_PUBLIC_PORT" != "$REMOTE_PORT" ]] || die "ET public port conflicts with the SSH reverse port"
  [[ "$ET_REMOTE_PORT" != "$PUBLIC_SSH_PORT" ]] || die "ET reverse port conflicts with the SSH public port"
  [[ "$ET_REMOTE_PORT" != "$REMOTE_PORT" ]] || die "ET and SSH reverse ports must differ"
  [[ "$ET_REMOTE_PORT" != "$ET_PUBLIC_PORT" ]] || die "ET public and reverse ports must differ"
fi

PUBKEY="$(printf '%s' "$PUBLIC_KEY_B64" | base64 -d 2>/dev/null)" || die "Invalid base64 public key"
[[ "$PUBKEY" == ssh-ed25519\ * || "$PUBKEY" == sk-ssh-ed25519@openssh.com\ * ]] || die "Only Ed25519 public keys are accepted"
[[ "$PUBKEY" != *$'\n'* && "$PUBKEY" != *$'\r'* ]] || die "Public key must be a single line"

export DEBIAN_FRONTEND=noninteractive
if ! command -v sshd >/dev/null || ! command -v ss >/dev/null; then
  apt-get update -qq
  apt-get install -y -qq openssh-server iproute2
fi

port_used_by_non_sshd() {
  ss -H -ltnp 2>/dev/null | awk -v p=":$1" '$4 ~ (p "$") && $0 !~ /sshd/ {found=1} END {exit !found}'
}
if port_used_by_non_sshd "$PUBLIC_SSH_PORT"; then
  die "TCP port $PUBLIC_SSH_PORT is already occupied by a non-sshd service"
fi
if port_used_by_non_sshd "$REMOTE_PORT"; then
  die "TCP port $REMOTE_PORT is already occupied by a non-sshd service"
fi
if ((WITH_ET)) && port_used_by_non_sshd "$ET_REMOTE_PORT"; then
  die "TCP port $ET_REMOTE_PORT is already occupied by a non-sshd service"
fi

if ((WITH_ET)); then
  log "Installing the Eternal Terminal jump server"
  bash "$ET_INSTALLER" --bind-ip 0.0.0.0 --port "$ET_PUBLIC_PORT" --open-firewall
fi

if ! id "$TUNNEL_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$TUNNEL_USER"
fi
USER_HOME="$(getent passwd "$TUNNEL_USER" | cut -d: -f6)"
install -d -m 700 -o "$TUNNEL_USER" -g "$TUNNEL_USER" "$USER_HOME/.ssh"
AUTHORIZED_KEYS="$USER_HOME/.ssh/authorized_keys"
KEY_MATERIAL="${PUBKEY#* }"
KEY_MATERIAL="${KEY_MATERIAL%% *}"

touch "$AUTHORIZED_KEYS"
if [[ -s "$AUTHORIZED_KEYS" ]]; then
  awk -v key="$KEY_MATERIAL" 'index($0, key) == 0' "$AUTHORIZED_KEYS" > "$AUTHORIZED_KEYS.tmp"
  mv "$AUTHORIZED_KEYS.tmp" "$AUTHORIZED_KEYS"
fi
KEY_OPTIONS="restrict,port-forwarding,permitlisten=\"localhost:$REMOTE_PORT\""
if ((WITH_ET)); then
  KEY_OPTIONS+=",permitlisten=\"localhost:$ET_REMOTE_PORT\""
fi
printf '%s %s\n' "$KEY_OPTIONS" "$PUBKEY" >> "$AUTHORIZED_KEYS"
chown "$TUNNEL_USER:$TUNNEL_USER" "$AUTHORIZED_KEYS"
chmod 600 "$AUTHORIZED_KEYS"

install -d -m 755 /etc/ssh/sshd_config.d
BACKUP=""
if [[ -f "$DROPIN" ]]; then
  BACKUP="$(mktemp)"
  cp -a "$DROPIN" "$BACKUP"
fi
cleanup_on_error() {
  rc=$?
  if ((rc != 0)); then
    if [[ -n "$BACKUP" ]]; then cp -a "$BACKUP" "$DROPIN"; else rm -f "$DROPIN"; fi
  fi
  [[ -z "$BACKUP" ]] || rm -f "$BACKUP"
  exit "$rc"
}
trap cleanup_on_error EXIT

CURRENT_PORT=0
if sshd -T 2>/dev/null | awk -v p="$PUBLIC_SSH_PORT" '$1 == "port" && $2 == p {found=1} END {exit !found}'; then
  CURRENT_PORT=1
fi
PERMIT_LISTEN="localhost:$REMOTE_PORT"
if ((WITH_ET)); then
  PERMIT_LISTEN+=" localhost:$ET_REMOTE_PORT"
fi

{
cat <<EOF
# Managed by homelab-reverse-ssh. Re-run setup.sh to change.
EOF
if ((CURRENT_PORT == 0)); then
  printf 'Port %s\n\n' "$PUBLIC_SSH_PORT"
fi
cat <<EOF
Match User $TUNNEL_USER
    AuthenticationMethods publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PubkeyAuthentication yes
    AllowTcpForwarding remote
    GatewayPorts no
    X11Forwarding no
    AllowAgentForwarding no
    PermitTTY no
    PermitListen $PERMIT_LISTEN
    MaxSessions 0

Match all
EOF
} > "$DROPIN"

sshd -t || die "New sshd configuration is invalid; rolling back"

if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q '^Status: active'; then
  ufw allow "$PUBLIC_SSH_PORT/tcp" comment 'homelab reverse SSH' >/dev/null
fi

systemctl enable --now ssh
systemctl reload ssh

trap - EXIT
[[ -z "$BACKUP" ]] || rm -f "$BACKUP"
log "VPS relay ready: SSH port $PUBLIC_SSH_PORT, loopback reverse port $REMOTE_PORT, user $TUNNEL_USER"
