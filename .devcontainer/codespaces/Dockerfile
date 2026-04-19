FROM mcr.microsoft.com/devcontainers/base:bookworm

# System dependencies (direnv, iputils-ping)
RUN apt-get update && apt-get install -y --no-install-recommends \
    direnv \
    iputils-ping \
    python3-full \
    python3-pip \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Install livereload
RUN pip3 install --no-cache-dir --break-system-packages livereload

# Prepare Nix store for vscode user
RUN mkdir -p /nix && chown -R vscode:vscode /nix

USER vscode

# Install Nix (single-user, no daemon — appropriate for containers)
RUN curl -L https://nixos.org/nix/install | sh -s -- --no-daemon

# Install devbox
ENV PATH="/home/vscode/.local/bin:/home/vscode/.nix-profile/bin:${PATH}"
RUN curl -fsSL https://get.jetify.com/devbox | bash -s -- --force

# Shell integration: nix, direnv
RUN { \
      echo ''; \
      echo '# Nix'; \
      echo '[ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ] && . "$HOME/.nix-profile/etc/profile.d/nix.sh"'; \
      echo ''; \
      echo '# Direnv'; \
      echo 'eval "$(direnv hook bash)"'; \
    } >> "$HOME/.bashrc"

USER root
