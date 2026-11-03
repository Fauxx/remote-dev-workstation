#!/usr/bin/env bash
# ==============================================================================
# Production Startup & Bootstrap Script: Remote Dev Workstation
# Target OS: Ubuntu 24.04 LTS (Noble Numbat, amd64)
# Project: Remote Dev Workstation (Fauxx/remote-dev-workstation)
# Author: Worker Subagent (Milestone 2 Implementation)
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. Output Redirection & Comprehensive Logging
# ------------------------------------------------------------------------------
LOG_FILE="/var/log/workstation-bootstrap.log"
mkdir -p "$(dirname "${LOG_FILE}")"
exec > >(tee -a "${LOG_FILE}") 2>&1
echo "=== Workstation bootstrap started at $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="

# Trap errors for transparent diagnostic reporting
trap 'echo "ERROR: Bootstrap script failed at line $LINENO on command: $BASH_COMMAND" | tee -a "${LOG_FILE}"' ERR

# Ensure backward-compatible symlink to /var/log/workstation-startup.log
ln -sf "${LOG_FILE}" /var/log/workstation-startup.log 2>/dev/null || true

TARGET_USER="ubuntu"
TARGET_HOME="/home/${TARGET_USER}"
WORKSPACE_DIR="${TARGET_HOME}/workspace"
REPO_DIR="${WORKSPACE_DIR}/FireMonitoringSystem"

export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# ------------------------------------------------------------------------------
# 2. Defensive System Readiness Loops
# ------------------------------------------------------------------------------
wait_for_network() {
    echo "--- Checking Network Connectivity ---"
    local delay=1
    local max_delay=16
    local max_attempts=12
    local attempt=1

    until curl -sI --connect-timeout 3 https://www.google.com >/dev/null 2>&1 || ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; do
        if [ "$attempt" -ge "$max_attempts" ]; then
            echo "ERROR: Network connectivity check failed after $attempt attempts." >&2
            return 1
        fi
        echo "Network unavailable (attempt $attempt/$max_attempts). Retrying in ${delay}s..."
        sleep "$delay"
        delay=$(( delay * 2 ))
        if [ "$delay" -gt "$max_delay" ]; then
            delay="$max_delay"
        fi
        attempt=$(( attempt + 1 ))
    done
    echo "Network is reachable and operational."
}

wait_for_apt() {
    echo "--- Checking Package Manager & cloud-init Locks ---"
    if command -v cloud-init >/dev/null 2>&1; then
        echo "Waiting for cloud-init status --wait..."
        cloud-init status --wait || true
    fi

    local max_wait=300
    local waited=0
    while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/lib/dpkg/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do
        if [ "$waited" -ge "$max_wait" ]; then
            echo "WARNING: dpkg/apt lock held for >${max_wait}s. Attempting to proceed..."
            break
        fi
        echo "dpkg/apt is locked by another process. Waiting 3s (waited ${waited}s)..."
        sleep 3
        waited=$(( waited + 3 ))
    done
    echo "dpkg/apt lock acquired and clear."
}

wait_for_network
wait_for_apt

# ------------------------------------------------------------------------------
# 3. 4GB Swapfile Configuration & Kernel Memory Tuning
# ------------------------------------------------------------------------------
setup_swap() {
    echo "--- Configuring 4GB Swapfile & Kernel Sysctl Parameters ---"
    if [ ! -f /swapfile ] || [ "$(stat -c %s /swapfile 2>/dev/null || echo 0)" -lt 4294967296 ]; then
        echo "Allocating 4GB swapfile..."
        swapoff /swapfile 2>/dev/null || true
        fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096 status=none
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
    else
        echo "Valid 4GB /swapfile already present."
        swapon /swapfile 2>/dev/null || true
    fi

    # Persist in /etc/fstab idempotently
    if ! grep -q '^/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    # Kernel virtual memory tuning for e2-medium (4GB RAM)
    cat << 'EOF' > /etc/sysctl.d/99-workstation.conf
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF
    sysctl -p /etc/sysctl.d/99-workstation.conf || true

    # Also maintain 99-workstation-swap.conf symlink/file for backward compatibility
    ln -sf /etc/sysctl.d/99-workstation.conf /etc/sysctl.d/99-workstation-swap.conf 2>/dev/null || true

    echo "Swap configuration verified:"
    swapon --show
    free -h
}
setup_swap

# ------------------------------------------------------------------------------
# 4. Essential Base Packages & CLI Tools
# ------------------------------------------------------------------------------
setup_base_packages() {
    echo "--- Installing Essential Packages & Prerequisites ---"
    wait_for_apt
    apt-get update -y
    apt-get install -y ${APT_OPTS} mosh tmux python3 python3-pip python3-venv git curl jq build-essential htop ripgrep ca-certificates gnupg psmisc python3-dev wget
}
setup_base_packages

# ------------------------------------------------------------------------------
# 5. Secret Manager REST API Integration
# ------------------------------------------------------------------------------
get_secret() {
    local secret_id="$1"
    local TOKEN
    TOKEN=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" 2>/dev/null | jq -r .access_token)
    local PROJECT_ID
    PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/project/project-id" 2>/dev/null || true)

    if [ -n "${TOKEN:-}" ] && [ -n "${PROJECT_ID:-}" ]; then
        curl -sf -H "Authorization: Bearer ${TOKEN}" \
            "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/${secret_id}/versions/latest:access" 2>/dev/null \
            | jq -r '.payload.data // empty' | base64 -d 2>/dev/null || true
    fi
}

fetch_secret() {
    get_secret "$1"
}

# ------------------------------------------------------------------------------
# 6. Tailscale Installation & Zero-Trust Tailscale SSH
# ------------------------------------------------------------------------------
setup_tailscale() {
    echo "--- Installing & Configuring Tailscale with Tailscale SSH ---"
    if ! command -v tailscale >/dev/null 2>&1; then
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    systemctl enable --now tailscaled

    # Retrieve Tailscale auth key dynamically from Secret Manager or instance attributes
    TAILSCALE_KEY=$(get_secret "tailscale-auth-key")
    if [ -z "${TAILSCALE_KEY:-}" ]; then
        TAILSCALE_KEY=$(curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/tailscale-authkey" 2>/dev/null || true)
    fi

    if [ -n "${TAILSCALE_KEY:-}" ]; then
        echo "Connecting workstation node to Tailnet..."
        tailscale up --authkey="${TAILSCALE_KEY}" --ssh --hostname=cloud-workstation --accept-routes
    else
        echo "WARNING: No Tailscale authkey provided (tailscale-auth-key secret absent). Tailscale daemon active; run 'tailscale up --ssh' manually to join."
    fi
}
setup_tailscale

# ------------------------------------------------------------------------------
# 7. Mosh & Safe tmux Auto-Attach Configuration
# ------------------------------------------------------------------------------
setup_terminal_experience() {
    echo "--- Configuring tmux Configuration & Safe Interactive Auto-Attach ---"
    cat << 'EOF' > "${TARGET_HOME}/.tmux.conf"
set -g mouse on
set -g history-limit 50000
set -g default-terminal "screen-256color"
set -g status-style bg=colour235,fg=colour136
set -g status-left '#[fg=green][#S] '
set -g status-right '#[fg=yellow]%Y-%m-%d %H:%M '
setw -g mode-keys vi
EOF

    local bashrc_file="${TARGET_HOME}/.bashrc"
    local guard="# --- Workstation Interactive tmux Auto-Attach ---"
    if ! grep -qF "${guard}" "${bashrc_file}"; then
        cat << 'EOF' >> "${bashrc_file}"

# --- Workstation Interactive tmux Auto-Attach ---
if [ -t 0 ] && [ -z "$TMUX" ] && [ -z "$SSH_ORIGINAL_COMMAND" ] && [ -z "$VSCODE_IPC_HOOK_CLI" ]; then
    if command -v tmux >/dev/null 2>&1; then
        exec tmux new-session -A -s main
    fi
fi
EOF
    fi
}
setup_terminal_experience

# ------------------------------------------------------------------------------
# 8. GitHub Credentials & Identity Pre-Seeding
# ------------------------------------------------------------------------------
setup_github_credentials() {
    echo "--- Pre-Seeding GitHub SSH Keys & CLI Credentials ---"
    mkdir -p -m 700 "${TARGET_HOME}/.ssh"

    # Pre-seed GitHub known_hosts with timeout tolerance
    ssh-keyscan github.com || true
    ssh-keyscan -t ed25519,rsa github.com >> "${TARGET_HOME}/.ssh/known_hosts" 2>/dev/null || true
    chmod 644 "${TARGET_HOME}/.ssh/known_hosts"

    # Retrieve and write SSH private key
    SSH_KEY=$(get_secret "github-ssh-private-key")
    if [ -n "$SSH_KEY" ]; then
        echo "$SSH_KEY" > "${TARGET_HOME}/.ssh/id_ed25519"
        chmod 600 "${TARGET_HOME}/.ssh/id_ed25519"
        ssh-keygen -y -f "${TARGET_HOME}/.ssh/id_ed25519" > "${TARGET_HOME}/.ssh/id_ed25519.pub" 2>/dev/null || true
        chmod 644 "${TARGET_HOME}/.ssh/id_ed25519.pub"
        echo "GitHub SSH private key installed successfully."
    else
        echo "NOTICE: github-ssh-private-key secret empty or absent; skipping private key injection."
    fi

    # Set git global identity for developer commits
    su - "${TARGET_USER}" -c 'git config --global user.name "Zet Donaue Samson"'
    su - "${TARGET_USER}" -c 'git config --global user.email "zetsamson@gmail.com"'
    su - "${TARGET_USER}" -c 'git config --global init.defaultBranch main'

    # Install GitHub CLI (gh)
    if ! command -v gh >/dev/null 2>&1; then
        echo "Installing GitHub CLI (gh)..."
        mkdir -p -m 755 /etc/apt/keyrings
        wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
        chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list
        wait_for_apt
        apt-get update -y
        apt-get install -y ${APT_OPTS} gh
    fi

    # Authenticate GitHub CLI via PAT
    GH_TOKEN=$(get_secret "github-pat-token")
    if [ -n "$GH_TOKEN" ] && command -v gh >/dev/null 2>&1; then
        echo "Authenticating GitHub CLI..."
        echo "$GH_TOKEN" | su - "${TARGET_USER}" -c "gh auth login --with-token" || true
        su - "${TARGET_USER}" -c "gh auth setup-git" || true
    else
        echo "NOTICE: github-pat-token secret empty or gh CLI not ready; skipping CLI login."
    fi
}
setup_github_credentials

# ------------------------------------------------------------------------------
# 9. Developer Toolchain: Node.js 22 LTS, Python 3, & Antigravity CLI (agy)
# ------------------------------------------------------------------------------
setup_toolchain() {
    echo "--- Installing NodeSource Node.js 22 LTS & Antigravity CLI ---"

    # Node.js 22 LTS via NodeSource (setup_22.x / node_22.x)
    if ! command -v node >/dev/null 2>&1; then
        echo "Installing Node.js 22 LTS via NodeSource (node_22.x)..."
        wait_for_apt
        curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
        wait_for_apt
        apt-get install -y ${APT_OPTS} nodejs
    fi

    # Antigravity CLI (agy v1.4.12)
    if ! command -v agy >/dev/null 2>&1; then
        echo "Installing Antigravity CLI (agy)..."
        curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- -d /usr/local/bin
        chmod +x /usr/local/bin/agy
        chmod +x agy 2>/dev/null || true
    fi
}
setup_toolchain

# ------------------------------------------------------------------------------
# 10. Cloned FireMonitoringSystem Repository
# ------------------------------------------------------------------------------
setup_project_repo() {
    echo "--- Setting up Workspace & Cloning FireMonitoringSystem ---"
    mkdir -p "${WORKSPACE_DIR}"

    if [ -d "${REPO_DIR}"/.git ]; then
        echo "FireMonitoringSystem repository already exists at ${REPO_DIR}; pulling latest changes..."
        su - "${TARGET_USER}" -c "cd ${REPO_DIR} && git fetch --all"
    else
        echo "Cloning FireMonitoringSystem repository from GitHub..."
        su - "${TARGET_USER}" -c "git clone https://github.com/Fauxx/FireMonitoringSystem.git ${REPO_DIR}"
        if [ -f "${TARGET_HOME}/.ssh/id_ed25519" ]; then
            su - "${TARGET_USER}" -c "cd ${REPO_DIR} && git remote set-url --push origin git@github.com:Fauxx/FireMonitoringSystem.git"
        fi
    fi
}
setup_project_repo

# ------------------------------------------------------------------------------
# 11. Final Permissions Normalization
# ------------------------------------------------------------------------------
normalize_permissions() {
    echo "--- Normalizing Permissions for User ${TARGET_USER} ---"
    chown -R ubuntu:ubuntu "${TARGET_HOME}"
    echo "Permissions normalized for /home/ubuntu."
}
normalize_permissions

echo "=== Workstation bootstrap completed successfully at $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="
exit 0
