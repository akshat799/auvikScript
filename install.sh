#!/bin/bash

###############################################################################
# Unified Auvik‑Collector & NinjaOne setup script
# - Step 1 (optional): install NinjaOne agent only if it is not already present
# - Step 2: apt update/upgrade
# - Step 3: install Docker & Compose
# - Step 4: deploy Auvik collector (prompts ONLY for API key; username & domain
#           are hard‑coded)
# - Step 5: CIS‑level hardening scan & remediation with OpenSCAP
###############################################################################

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Please run with sudo." >&2
    exit 1
fi

DATE=$(date +%Y-%m-%d)
LOGFILE="/opt/unified-install-$DATE.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

run_cmd() {
    log "Running: $*"
    "$@" || {
        log "Command failed: $*"
        exit 1
    }
}

trap 'log "Script interrupted by user."; exit 1' INT

check_reboot() {
    if [ -f /var/run/reboot-required ]; then
        echo "A reboot is pending. Reboot now? (y/N)"; read -r resp
        [[ $resp =~ ^[Yy]$ ]] && reboot || echo "Continuing without reboot."
    fi
}

check_dependencies() {
    local deps=(apt wget dpkg docker docker-compose unzip oscap systemctl)
    for dep in "${deps[@]}"; do
        command -v "$dep" &>/dev/null || {
            log "Missing dependency: $dep"; exit 1; }
    done
}

###############################################################################
# Helper: detect if NinjaOne agent is present
###############################################################################

is_ninja_installed() {
    systemctl list-units --type=service | grep -qi "ninja.*agent" && return 0
    dpkg -l | grep -qi "ninjaone" && return 0
    return 1
}

###############################################################################
# Helper: install NinjaOne agent (architecture‑aware)
###############################################################################

install_ninja() {
    # Determine architecture & download URL
    local arch url pkg
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            url="https://app.ninjarmm.com/ws/api/v2/generic-installer/NinjaOneAgent-i64.deb"
            pkg="NinjaOneAgent-i64.deb";;
        arm64|aarch64)
            url="https://app.ninjarmm.com/ws/api/v2/generic-installer/NinjaOneAgent-arm64.deb"
            pkg="NinjaOneAgent-arm64.deb";;
        *) log "Unsupported architecture: $arch"; exit 1;;
    esac

    log "Detected architecture: $arch"
    log "Downloading NinjaOne agent…"
    run_cmd wget -q --show-progress -O "$pkg" "$url"

    TOKENID="${TOKENID:-$NINJA_TOKEN_ID}"
    [ -z "$TOKENID" ] && { log "Token ID cannot be empty"; exit 1; }

    log "Installing NinjaOne agent…"
    run_cmd sudo TOKENID="$TOKENID" dpkg -i "$pkg"
    log "NinjaOne agent installation finished."
}

###############################################################################
# Step 1: (optional) Setup NinjaOne agent
###############################################################################
step1() {
    check_reboot
    if is_ninja_installed; then
        log "NinjaOne agent already installed – skipping Step 1."
    else
        log "NinjaOne agent not found – running Step 1."
        install_ninja
    fi
}

###############################################################################
# Step 2: System update & upgrade
###############################################################################
step2() {
    check_reboot
    log "STEP 2: Updating package lists & upgrading…"
    run_cmd sudo apt update
    run_cmd sudo apt upgrade -y
    log "STEP 2 completed."
}

###############################################################################
# Step 3: Docker & Compose
###############################################################################
step3() {
    check_reboot
    log "STEP 3: Installing Docker & Compose…"
    run_cmd sudo apt update
    run_cmd sudo apt install -y docker.io docker-compose
    run_cmd sudo systemctl enable --now docker
    log "STEP 3 completed."
}

###############################################################################
# Step 4: Deploy Auvik collector (Docker)
###############################################################################
step4() {
    check_reboot
    log "STEP 4: Configuring Auvik collector…"

    AUVIK_API_KEY="${AUVIK_API_KEY:-$AUVIK_API_KEY}"
    [ -z "$AUVIK_API_KEY" ] && { log "API key cannot be empty"; exit 1; }

    local COLLECTOR_DIR="/opt/auvik"
    run_cmd sudo mkdir -p "$COLLECTOR_DIR"

    cat <<EOF | sudo tee "$COLLECTOR_DIR/docker-compose.yml" >/dev/null
services:
  collector:
    image: auviknetworks/collector:latest
    container_name: "auvik-collector"
    hostname: "auvik-collector"
    environment:
      AUVIK_USERNAME: auvikcollector@verticomm.com
      AUVIK_API_KEY: ${AUVIK_API_KEY}
      AUVIK_DOMAIN_PREFIX: verticomm
    cap_add:
      - NET_ADMIN
    volumes:
      - './config/:/config/'
      - './etc/auvik/:/etc/auvik/'
      - './logs/:/usr/share/agent/logs/'
    restart: unless-stopped
EOF

    log "Auvik docker‑compose file written to $COLLECTOR_DIR." 
    log "STEP 4 completed. Run 'docker compose up -d' inside $COLLECTOR_DIR to start the collector."
}

###############################################################################
# Step 5: CIS hardening with OpenSCAP
###############################################################################
step5() {
    check_reboot
    log "STEP 5: Hardening with OpenSCAP…"

    WORK_DIR="/opt/ssg-nightly-$DATE"
    SSG_URL="https://nightly.link/ComplianceAsCode/content/workflows/nightly_build/master/Nightly%20Build.zip"

    run_cmd sudo apt update
    run_cmd sudo apt install -y openscap-scanner openscap-utils unzip wget

    run_cmd mkdir -p "$WORK_DIR"
    run_cmd chmod a+rx "$WORK_DIR"
    run_cmd sudo chown -R "$SUDO_USER:$SUDO_USER" "$WORK_DIR"
    cd "$WORK_DIR" || exit 1

    [ ! -f nightly.zip ] && run_cmd wget -O nightly.zip "$SSG_URL"
    [ ! -f "Nightly Build.zip" ] && run_cmd unzip -o nightly.zip

    SSG_ZIP=$(find . -name 'scap-security-guide-*.zip' | head -n1)
    [ ! -f "$SSG_ZIP" ] && { log "Extracting Nightly Build.zip…"; run_cmd unzip -o "Nightly Build.zip"; SSG_ZIP=$(find . -name 'scap-security-guide-*.zip' | head -n1); }

    [ -z "$SSG_ZIP" ] && { log "No SSG ZIP found"; exit 1; }
    [ ! -f ssg-ubuntu2404-ds.xml ] && run_cmd unzip -o "$SSG_ZIP"

    SSG_XML=$(find . -name 'ssg-ubuntu2404-ds.xml' | head -n1)
    [ -z "$SSG_XML" ] && { log "Ubuntu 24.04 XCCDF not found"; exit 1; }

    log "Running baseline scan… (no remediation)"
    oscap xccdf eval \
        --profile xccdf_org.ssgproject.content_profile_cis_level1_server \
        --report "report-before-$DATE.html" \
        "$SSG_XML" || log "Initial scan completed with warnings/errors."

    log "Running remediation scan…"
    oscap xccdf eval --remediate \
        --profile xccdf_org.ssgproject.content_profile_cis_level1_server \
        --report "report-after-$DATE.html" \
        "$SSG_XML" || log "Remediation scan completed with warnings/errors."

    run_cmd sudo chown -R "$SUDO_USER:$SUDO_USER" "$WORK_DIR"
    log "STEP 5 completed. Reports saved in $WORK_DIR." 
}

###############################################################################
# Run all steps
###############################################################################
run_all() {
    step1
    step2
    step3
    step4
    step5
}

###############################################################################
# Main menu
###############################################################################
check_dependencies
log "Script started."

echo "Select an option:"
echo "1) Run all steps"
echo "2) Run Step 1 only (Setup/confirm NinjaOne)"
echo "3) Run Step 2 only (System update/upgrade)"
echo "4) Run Step 3 only (Install Docker & Compose)"
echo "5) Run Step 4 only (Deploy Auvik collector)"
echo "6) Run Step 5 only (OpenSCAP hardening)"
read -rp "Enter your choice [1-6]: " choice

case $choice in
    1) run_all ;;
    2) step1 ;;
    3) step2 ;;
    4) step3 ;;
    5) step4 ;;
    6) step5 ;;
    *) log "Invalid option."; exit 1 ;;
esac

log "Script completed."