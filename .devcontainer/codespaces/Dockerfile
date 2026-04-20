FROM mcr.microsoft.com/devcontainers/base:bookworm

# System dependencies (direnv, iputils-ping)
RUN apt-get update && apt-get install -y --no-install-recommends \
    direnv \
    iputils-ping \
    python3-full \
    python3-pip \
    nodejs \
    npm \
    gh \
    && rm -rf /var/lib/apt/lists/*

# Install livereload
RUN pip3 install --no-cache-dir --break-system-packages livereload

# Install AWS CLI v2
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscli.zip \
    && unzip -q /tmp/awscli.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscli.zip

# Install AWS CDK
RUN npm install -g aws-cdk

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
