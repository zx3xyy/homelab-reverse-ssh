#!/usr/bin/env bash
set -Eeuo pipefail

BIND_IP=""
PORT=2022
OPEN_FIREWALL=0
STATE_DIR="/etc/homelab-reverse-ssh"
CONFIG_PATH="$STATE_DIR/et.cfg"
MARKER_PATH="$STATE_DIR/et-managed"
UNIT_NAME="homelab-reverse-ssh-etserver"
UNIT_PATH="/etc/systemd/system/$UNIT_NAME.service"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '==> %s\n' "$*"; }
valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && ((1 <= 10#$1 && 10#$1 <= 65535)); }

usage() {
  cat <<'EOF'
Usage:
  sudo install-et-server.sh --bind-ip IP [options]

Options:
  --bind-ip IP       Listen address: 127.0.0.1 or 0.0.0.0 (required)
  --port PORT        Eternal Terminal port (default: 2022)
  --open-firewall    Open PORT in UFW when UFW is active
EOF
}

while (($#)); do
  case "$1" in
    --bind-ip) BIND_IP="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --open-firewall) OPEN_FIREWALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ "$EUID" -eq 0 ]] || die "Run as root"
[[ "$BIND_IP" == "127.0.0.1" || "$BIND_IP" == "0.0.0.0" ]] || die "--bind-ip must be 127.0.0.1 or 0.0.0.0"
valid_port "$PORT" || die "Invalid --port: $PORT"

install_et_package() {
  local os_id codename

  # shellcheck source=/dev/null
  source /etc/os-release
  os_id="${ID:-}"
  codename="${VERSION_CODENAME:-}"
  [[ -n "$codename" ]] || die "Could not determine the OS codename"

  export DEBIAN_FRONTEND=noninteractive
  case "$os_id" in
    ubuntu)
      apt-get update -qq
      apt-get install -y -qq ca-certificates software-properties-common
      add-apt-repository -y ppa:jgmath2000/et
      apt-get update -qq
      apt-get install -y -qq et
      ;;
    debian)
      apt-get update -qq
      apt-get install -y -qq ca-certificates curl
      install -d -m 755 /etc/apt/keyrings
      curl -fsSL https://github.com/MisterTea/debian-et/raw/master/et.gpg \
        -o /etc/apt/keyrings/et.gpg
      chmod 644 /etc/apt/keyrings/et.gpg
      printf 'deb [signed-by=/etc/apt/keyrings/et.gpg] https://mistertea.github.io/debian-et/debian-source/ %s main\n' \
        "$codename" > /etc/apt/sources.list.d/et.list
      apt-get update -qq
      apt-get install -y -qq et
      ;;
    *)
      die "Automatic Eternal Terminal installation supports Ubuntu and Debian only"
      ;;
  esac
}

install -d -m 755 "$STATE_DIR"
MANAGED=0
if [[ -f "$MARKER_PATH" ]]; then
  MANAGED=1
elif ! command -v etserver >/dev/null 2>&1; then
  log "Installing Eternal Terminal"
  install_et_package
  touch "$MARKER_PATH"
  chmod 644 "$MARKER_PATH"
  MANAGED=1
fi

command -v etserver >/dev/null 2>&1 || die "etserver was not installed"
if ! command -v ss >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq iproute2
fi

if ((MANAGED)); then
  ETSERVER_BIN="$(command -v etserver)"
  cat > "$CONFIG_PATH" <<EOF
; Managed by homelab-reverse-ssh.
[Networking]
port = $PORT
bind_ip = $BIND_IP

[Debug]
verbose = 0
silent = 0
telemetry = false
logdirectory = /tmp
EOF
  chmod 644 "$CONFIG_PATH"

  cat > "$UNIT_PATH" <<EOF
[Unit]
Description=Eternal Terminal server for homelab-reverse-ssh
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=$ETSERVER_BIN --cfgfile=$CONFIG_PATH --logtostdout
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

  systemctl disable --now et.service >/dev/null 2>&1 || true
  systemctl daemon-reload
  systemctl enable "$UNIT_NAME"
  systemctl restart "$UNIT_NAME"
else
  log "Using the existing unmanaged Eternal Terminal installation"
fi

listener_ready() {
  if [[ "$BIND_IP" == "127.0.0.1" ]]; then
    ss -H -ltn "sport = :$PORT" 2>/dev/null | awk '$4 ~ /^127[.]0[.]0[.]1:/ {found=1} END {exit !found}'
  else
    ss -H -ltn "sport = :$PORT" 2>/dev/null | awk '$4 ~ /^0[.]0[.]0[.]0:/ || $4 ~ /^\[::\]:/ {found=1} END {exit !found}'
  fi
}

for _ in {1..10}; do
  if listener_ready; then
    break
  fi
  sleep 1
done
listener_ready || die "No Eternal Terminal server is listening on $BIND_IP:$PORT"

if ((OPEN_FIREWALL)) && command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q '^Status: active'; then
  ufw allow "$PORT/tcp" comment 'Eternal Terminal' >/dev/null
fi

log "Eternal Terminal is listening on $BIND_IP:$PORT"
