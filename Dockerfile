FROM debian:bookworm-slim

# Arguments for user setup
ARG GO_VERSION=1.26.0
ARG TARGETARCH
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000

# Setup environment variables first
ENV PATH="/usr/local/go/bin:/go/bin:${PATH}" \
    GOPATH="/go" \
    GOMODCACHE="/go/pkg/mod" \
    GOCACHE="/home/${USERNAME}/.cache/go-build" \
    PNPM_HOME="/home/${USERNAME}/.local/share/pnpm" \
    PNPM_STORE_DIR="/home/${USERNAME}/.local/share/pnpm/store" \
    NPM_CONFIG_CACHE="/home/${USERNAME}/.cache/npm" \
    HISTFILE="/commandhistory/.zsh_history" \
    SHELL=/usr/bin/zsh \
    LANG=en_US.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

# -----------------------------
# Root: system packages (APT)
# -----------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg git zsh make jq vim unzip lsb-release zoxide openssh-client \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------
# Root: PostgreSQL client from PGDG
# ---------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# ------------------------
# Root: Node.js runtime
# ------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# ------------------------
# Root: Go + Go dev tools
# ------------------------
RUN --mount=type=cache,target=/go/pkg/mod,sharing=locked \
    --mount=type=cache,target=/home/${USERNAME}/.cache/go-build,sharing=locked \
    mkdir -p /go/bin /go/src /go/pkg \
    && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" -o /tmp/go.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz \
    && go install golang.org/x/tools/gopls@latest \
    && go install github.com/go-delve/delve/cmd/dlv@latest \
    && go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

# -------------------------------------------
# Root: user, workspace and shared directories
# -------------------------------------------
RUN groupadd --gid "${USER_GID}" "${USERNAME}" \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" -m "${USERNAME}" \
    && chsh -s /usr/bin/zsh "${USERNAME}" \
    && mkdir -p \
    /home/${USERNAME}/.config/opencode \
    /home/${USERNAME}/.cache/go-build \
    /home/${USERNAME}/.cache/npm \
    /home/${USERNAME}/.local/share/pnpm/store \
    /workspace/frontend/node_modules \
    /commandhistory \
    && chown -R "${USERNAME}:${USERNAME}" /go /home/${USERNAME} /workspace /commandhistory

# --------------------------------
# Root: global zsh base settings
# --------------------------------
RUN printf '%s\n' \
    '' \
    '# Configuración compartida de historial de zsh' \
    'export HISTFILE=/commandhistory/.zsh_history' \
    'HISTSIZE=10000' \
    'SAVEHIST=10000' \
    'setopt APPEND_HISTORY' \
    'setopt INC_APPEND_HISTORY' \
    'setopt SHARE_HISTORY' \
    'setopt HIST_IGNORE_DUPS' \
    'setopt HIST_SAVE_NO_DUPS' \
    >> /etc/zsh/zshrc

USER ${USERNAME}
WORKDIR /workspace

# -------------------------------
# User: CLI tools and shell setup
# -------------------------------
# Install OpenCode CLI
RUN curl -fsSL https://opencode.ai/install | bash

# Setup pnpm in user scope
RUN corepack prepare pnpm@latest --activate \
    && pnpm --version >/dev/null

# Instalar Oh My Zsh y plugins en una sola capa
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions \
    && git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting \
    && git clone --depth=1 https://github.com/zsh-users/zsh-completions.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-completions \
    && git clone --depth=1 https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search

RUN sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions sudo zsh-history-substring-search)/' ~/.zshrc \
    && echo '\n# Inicializar zoxide' >> "$HOME/.zshrc" \
    && echo 'eval "$(zoxide init zsh)"' >> "$HOME/.zshrc" \
    && touch "/commandhistory/.zsh_history"

ENV PATH="/home/${USERNAME}/.config/opencode/bin:${PATH}"
