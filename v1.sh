!/usr/bin/env bash
# ============================================================
# VantixShop Status — Production Installer
# Based on the supplied "New Folder" Flask project
# Developer: AashirwadGamerzz
# ============================================================

set -Eeuo pipefail

APP_NAME="VantixShop Status"
SERVICE_NAME="vantixshop-status"
INSTALL_DIR="/opt/vantixshop-status"
VENV_DIR="${INSTALL_DIR}/venv"
APP_DIR="${INSTALL_DIR}/app"
ENV_FILE="${APP_DIR}/.env"
LOG_DIR="/var/log/vantixshop-status"
PYTHON_BIN=""
PORT="${PORT:-5000}"
HOST="${HOST:-127.0.0.1}"

# GitHub source ZIP
DOWNLOAD_URL="https://drive.usercontent.google.com/download?id=1PQeyYG2a2a0kvf25cv-0Ys4IK82LR896&export=download&authuser=0"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

cleanup() {
    rm -f /tmp/vantixshop-status.zip 2>/dev/null || true
    rm -rf /tmp/vantixshop-status-src 2>/dev/null || true
}
trap cleanup EXIT

echo
echo -e "${CYAN}"
echo "============================================================"
echo "             VANTIXSHOP STATUS INSTALLER"
echo "             Real-Time Infrastructure Monitor"
echo "============================================================"
echo -e "${NC}"

# ------------------------------------------------------------
# Root
# ------------------------------------------------------------

[[ "${EUID}" -eq 0 ]] || die "Run this installer as root."

ok "Root access detected."

# ------------------------------------------------------------
# OS
# ------------------------------------------------------------

[[ -f /etc/os-release ]] || die "Unable to detect operating system."
source /etc/os-release

info "Operating System : ${PRETTY_NAME:-unknown}"
info "Architecture     : $(uname -m)"

# ------------------------------------------------------------
# Install system dependencies
# ------------------------------------------------------------

info "Checking system dependencies..."

install_deps() {
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y \
            python3 \
            python3-venv \
            python3-pip \
            curl \
            wget \
            unzip \
            ca-certificates
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y \
            python3 \
            python3-pip \
            curl \
            wget \
            unzip \
            ca-certificates
        python3 -m venv --help >/dev/null 2>&1 || \
            dnf install -y python3-virtualenv
    elif command -v yum >/dev/null 2>&1; then
        yum install -y \
            python3 \
            python3-pip \
            curl \
            wget \
            unzip \
            ca-certificates
    elif command -v apk >/dev/null 2>&1; then
        apk add \
            python3 \
            py3-pip \
            py3-virtualenv \
            curl \
            wget \
            unzip \
            ca-certificates
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm \
            python \
            python-pip \
            curl \
            wget \
            unzip \
            ca-certificates
    elif command -v zypper >/dev/null 2>&1; then
        zypper --non-interactive refresh
        zypper --non-interactive install \
            python3 \
            python3-pip \
            curl \
            wget \
            unzip \
            ca-certificates
    else
        die "Unsupported Linux package manager."
    fi
}

if ! command -v python3 >/dev/null 2>&1 || \
   ! command -v curl >/dev/null 2>&1 || \
   ! command -v unzip >/dev/null 2>&1; then
    install_deps
else
    ok "Basic dependencies are available."
fi

PYTHON_BIN="$(command -v python3)"
[[ -n "$PYTHON_BIN" ]] || die "python3 was not found."

PYTHON_VERSION="$("$PYTHON_BIN" --version 2>&1)"
info "Python: ${PYTHON_VERSION}"

# ------------------------------------------------------------
# Download project
# ------------------------------------------------------------

info "Downloading VantixShop Status..."

rm -f /tmp/vantixshop-status.zip
rm -rf /tmp/vantixshop-status-src

curl \
    --fail \
    --location \
    --retry 5 \
    --retry-delay 3 \
    --connect-timeout 15 \
    --max-time 600 \
    --output /tmp/vantixshop-status.zip \
    "${DOWNLOAD_URL}"

[[ -s /tmp/vantixshop-status.zip ]] || \
    die "Project download is empty."

file /tmp/vantixshop-status.zip | grep -Eiq 'Zip archive|archive' || \
    die "Downloaded project is not a valid ZIP archive."

mkdir -p /tmp/vantixshop-status-src
unzip -q /tmp/vantixshop-status.zip -d /tmp/vantixshop-status-src

SOURCE_DIR="$(find /tmp/vantixshop-status-src -mindepth 1 -maxdepth 1 -type d | head -n 1)"

[[ -n "${SOURCE_DIR}" ]] || die "Unable to locate extracted project."

[[ -f "${SOURCE_DIR}/app.py" ]] || die "app.py was not found in the project."
[[ -f "${SOURCE_DIR}/requirements.txt" ]] || die "requirements.txt was not found."
[[ -d "${SOURCE_DIR}/templates" ]] || die "templates directory was not found."
[[ -d "${SOURCE_DIR}/static" ]] || die "static directory was not found."

ok "Project structure validated."

# ------------------------------------------------------------
# Install application
# ------------------------------------------------------------

info "Preparing ${INSTALL_DIR}..."

mkdir -p "${INSTALL_DIR}" "${LOG_DIR}"

if [[ -d "${APP_DIR}" ]]; then
    warn "Existing installation detected."
    cp -a "${APP_DIR}" "${INSTALL_DIR}/app.backup.$(date +%Y%m%d-%H%M%S)"
fi

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}"

cp -a "${SOURCE_DIR}/." "${APP_DIR}/"

ok "Application files installed."

# ------------------------------------------------------------
# Python virtual environment
# ------------------------------------------------------------

info "Creating Python virtual environment..."

if ! "${PYTHON_BIN}" -m venv "${VENV_DIR}" >/dev/null 2>&1; then
    warn "Python venv module is missing. Attempting package installation..."
    install_deps
    "${PYTHON_BIN}" -m venv "${VENV_DIR}" || \
        die "Unable to create Python virtual environment."
fi

"${VENV_DIR}/bin/python" -m pip install --upgrade pip setuptools wheel

info "Installing Python requirements..."

"${VENV_DIR}/bin/pip" install -r "${APP_DIR}/requirements.txt"

ok "Flask and python-dotenv installed."

# ------------------------------------------------------------
# Environment
# ------------------------------------------------------------

info "Preparing environment configuration..."

if [[ ! -f "${ENV_FILE}" ]]; then
    SECRET_KEY="$("${VENV_DIR}/bin/python" -c 'import secrets; print(secrets.token_hex(32))')"
    ADMIN_PASSWORD="$("${VENV_DIR}/bin/python" -c 'import secrets; print(secrets.token_urlsafe(18))')"

    cat > "${ENV_FILE}" <<EOF
ADMIN_USERNAME=admin
ADMIN_PASSWORD=${ADMIN_PASSWORD}
SECRET_KEY=${SECRET_KEY}
FLASK_ENV=production
HOST=${HOST}
PORT=${PORT}
EOF

    chmod 600 "${ENV_FILE}"

    echo
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${WHITE} ADMIN LOGIN CREATED${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo "Username : admin"
    echo "Password : ${ADMIN_PASSWORD}"
    echo
    echo "Save this password. It will not be displayed again."
    echo -e "${GREEN}============================================================${NC}"
    echo
else
    warn ".env already exists; keeping existing configuration."
fi

# ------------------------------------------------------------
# Application permissions
# ------------------------------------------------------------

info "Applying permissions..."

chown -R root:root "${INSTALL_DIR}"
chmod 755 "${INSTALL_DIR}"
chmod 755 "${APP_DIR}"
chmod 600 "${ENV_FILE}"

# SQLite database directory will be created by app.py.
mkdir -p "${APP_DIR}/database"
chmod 750 "${APP_DIR}/database"

# ------------------------------------------------------------
# systemd
# ------------------------------------------------------------

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then

    info "Creating systemd service..."

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=${APP_NAME}
Documentation=VantixShop Status
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}

EnvironmentFile=${ENV_FILE}

ExecStart=${VENV_DIR}/bin/python ${APP_DIR}/app.py

Restart=always
RestartSec=5

User=root
Group=root

TimeoutStartSec=30
TimeoutStopSec=30

NoNewPrivileges=true
PrivateTmp=true

StandardOutput=append:${LOG_DIR}/app.log
StandardError=append:${LOG_DIR}/error.log

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "/etc/systemd/system/${SERVICE_NAME}.service"

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1

    info "Starting ${APP_NAME}..."

    systemctl restart "${SERVICE_NAME}"

    sleep 5

    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        ok "${APP_NAME} service is ONLINE."
    else
        echo
        systemctl status "${SERVICE_NAME}" --no-pager --full || true
        echo
        die "Service failed to start. Check ${LOG_DIR}/error.log"
    fi

else
    warn "systemd is not available."
    warn "The application files were installed, but automatic service management is unavailable."
fi

# ------------------------------------------------------------
# Local status test
# ------------------------------------------------------------

info "Checking application..."

STATUS="OFFLINE"

if command -v curl >/dev/null 2>&1; then
    if curl -fsS --max-time 10 \
        "http://${HOST}:${PORT}/" >/dev/null 2>&1; then
        STATUS="ONLINE"
    fi
fi

# ------------------------------------------------------------
# Firewall
# ------------------------------------------------------------

if command -v ufw >/dev/null 2>&1; then
    ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
    ok "UFW rule checked for TCP ${PORT}."
fi

if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    ok "firewalld rule checked for TCP ${PORT}."
fi

# ------------------------------------------------------------
# Final
# ------------------------------------------------------------

echo
echo -e "${GREEN}"
echo "============================================================"
echo "              INSTALLATION COMPLETE"
echo "============================================================"
echo -e "${NC}"

echo "Application       : ${APP_NAME}"
echo "Status            : ${STATUS}"
echo "Install Directory : ${INSTALL_DIR}"
echo "Application       : ${APP_DIR}"
echo "Virtualenv        : ${VENV_DIR}"
echo "Service           : ${SERVICE_NAME}"
echo "Host              : ${HOST}"
echo "Port              : ${PORT}"
echo "Local URL         : http://${HOST}:${PORT}"
echo "Database          : ${APP_DIR}/database/status.db"
echo "Logs              : ${LOG_DIR}/"
echo
echo "Service commands:"
echo "  Start   : systemctl start ${SERVICE_NAME}"
echo "  Stop    : systemctl stop ${SERVICE_NAME}"
echo "  Restart : systemctl restart ${SERVICE_NAME}"
echo "  Status  : systemctl status ${SERVICE_NAME}"
echo
echo "Live logs:"
echo "  journalctl -u ${SERVICE_NAME} -f"
echo "  tail -f ${LOG_DIR}/app.log"
echo
echo "============================================================"

if [[ "${STATUS}" == "ONLINE" ]]; then
    ok "${APP_NAME} is running."
else
    warn "Installation completed, but the HTTP status check is OFFLINE."
    warn "Check: journalctl -u ${SERVICE_NAME} -n 100 --no-pager"
fi
