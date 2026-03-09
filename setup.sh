#!/usr/bin/env bash
set -e

# ─────────────────────────────────────────────
# mediamtx-ui — full setup script
# Run as root or with sudo privileges
# ─────────────────────────────────────────────

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
section() { echo -e "\n${BOLD}▶ $*${NC}"; }

# ─── Root check ──────────────────────────────
if [ "$EUID" -ne 0 ]; then
  error "Run as root: sudo bash setup.sh"
fi

# ─── Detect OS ───────────────────────────────
section "Detecting OS"
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_ID=$ID
  OS_VERSION=$VERSION_ID
  OS_CODENAME=${VERSION_CODENAME:-}
  info "Detected: $PRETTY_NAME"
else
  error "Cannot detect OS — /etc/os-release not found"
fi

case "$OS_ID" in
  ubuntu|debian|raspbian) ;;
  *) warn "Untested OS: $OS_ID. Continuing anyway..." ;;
esac

# ─── Docker ──────────────────────────────────
section "Docker"
if command -v docker &>/dev/null; then
  info "Docker already installed: $(docker --version)"
else
  info "Installing Docker..."
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
  rm /tmp/get-docker.sh

  # add current user to docker group (if not root login)
  REAL_USER="${SUDO_USER:-$USER}"
  if [ "$REAL_USER" != "root" ]; then
    usermod -aG docker "$REAL_USER"
    info "User '$REAL_USER' added to docker group (re-login required)"
  fi
  info "Docker installed: $(docker --version)"
fi

if ! command -v docker compose &>/dev/null; then
  info "Installing Docker Compose plugin..."
  apt-get install -y docker-compose-plugin
fi
info "Docker Compose: $(docker compose version)"

# ─── ffmpeg (bare metal, optional for Raspberry Pi) ──
section "ffmpeg (bare metal)"
if command -v ffmpeg &>/dev/null; then
  info "ffmpeg already installed: $(ffmpeg -version 2>&1 | head -1)"
else
  info "Installing ffmpeg..."
  apt-get install -y ffmpeg
  info "ffmpeg installed: $(ffmpeg -version 2>&1 | head -1)"
fi

# ─── Project config files ─────────────────────
section "Project config files"

if [ ! -f .env ]; then
  cp .env.default .env
  info "Created .env from .env.default"
else
  info ".env already exists — skipping"
fi

if [ ! -f config/mediamtx.yml ]; then
  cp config/mediamtx.default.yml config/mediamtx.yml
  info "Created config/mediamtx.yml"
else
  info "config/mediamtx.yml already exists — skipping"
fi

if [ ! -f config/auth.json ]; then
  cp config/auth.default.json config/auth.json
  info "Created config/auth.json (set your password hash!)"
else
  info "config/auth.json already exists — skipping"
fi

mkdir -p data media
[ ! -f data/cam1.json ] && echo '{}' > data/cam1.json && info "Created data/cam1.json"

# ─── Build Docker images ──────────────────────
section "Building Docker images"
docker compose build --no-cache
info "Docker images built"

# ─── Start services ───────────────────────────
section "Starting services"
docker compose up -d
info "All services started in background"

# ─── Enable Docker on boot ────────────────────
section "Enabling Docker on boot"
systemctl enable docker
info "Docker enabled on system boot"

# ─── Systemd service for auto-start ───────────
section "Creating systemd service"

APP_DIR="$(pwd)"

cat > /etc/systemd/system/mediamtx-ui.service <<EOF
[Unit]
Description=mediamtx-ui Docker Compose stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mediamtx-ui.service
info "mediamtx-ui.service enabled — will start automatically on boot"

# ─── Done ─────────────────────────────────────
section "Setup complete"
echo ""
echo -e "  ${BOLD}Generate password hash:${NC}"
echo -e "    docker compose run --rm mediamtxui node generate_auth.js"
echo -e "    → paste the hash into config/auth.json"
echo ""
echo -e "  ${BOLD}Service management:${NC}"
echo -e "    systemctl start mediamtx-ui    # start"
echo -e "    systemctl stop mediamtx-ui     # stop"
echo -e "    systemctl status mediamtx-ui   # status"
echo ""
echo -e "  ${BOLD}Web interface:${NC}  http://$(hostname -I | awk '{print $1}'):$(grep SERVER_PORT .env | cut -d= -f2)"
echo ""
