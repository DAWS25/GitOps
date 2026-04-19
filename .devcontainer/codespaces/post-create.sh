#!/bin/bash
set -euo pipefail

LOG_FILE="/tmp/post-create.log"

log() {
    local msg="[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

log "========== post-create.sh started =========="
log "User: $(whoami) | Home: $HOME | PWD: $(pwd)"

# Source Nix environment (installed in Dockerfile)
if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi
export PATH="$HOME/.local/bin:$PATH"

# Devbox: install nix packages declared in devbox.json
log "--- Devbox install ---"
log "devbox version: $(devbox version)"
yes | devbox install
log "devbox install complete."

# Direnv: create .envrc for devbox integration
log "--- Direnv setup ---"
if ! grep -q 'devbox' .envrc 2>/dev/null; then
    echo 'eval "$(devbox generate direnv --print-envrc)"' > .envrc
fi
direnv allow .
log "Direnv configured."

# Docker group (Docker socket is provided by Codespaces/docker-in-docker feature)
log "--- Docker setup ---"
if command -v docker &> /dev/null; then
    if ! getent group docker > /dev/null 2>&1; then
        sudo groupadd docker
    fi
    sudo usermod -aG docker "${USER}"
    log "Docker group configured."
fi

# System Info
log "PWD: $(pwd)"

log "========== post-create.sh completed =========="
log "Log: $LOG_FILE"
