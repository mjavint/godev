# syntax=docker/dockerfile:1

# =============================================================================
# Imagen de desarrollo (Dev Container)
# Go + Node.js + pnpm + PostgreSQL client sobre Debian bookworm-slim,
# en paridad con la imagen de producción (debian) y con CI.
# =============================================================================

# --- Versiones ---------------------------------------------------------------
# GO_VERSION: versión exacta; se toma el SDK de la imagen oficial (misma
# arquitectura que el build). Mantener alineada con CI y con go.mod.
ARG GO_VERSION=1.27.4
# NODE_MAJOR: LTS. Se resuelve el último parche disponible en build.
ARG NODE_MAJOR=24

# SDK de Go desde la imagen oficial: evita descargar de dl.google.com (que en
# algunas redes/VPN responde 404) y no requiere verificar checksum a mano.
FROM golang:${GO_VERSION}-bookworm AS go-sdk

FROM debian:bookworm-slim

ARG NODE_MAJOR=24
# TARGETARCH lo inyecta BuildKit (amd64/arm64); hay fallback vía dpkg.
ARG TARGETARCH

# --- Usuario de desarrollo ---------------------------------------------------
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    SHELL=/usr/bin/zsh \
    HISTFILE=/commandhistory/.zsh_history \
    GOPATH=/home/${USERNAME}/go \
    GOMODCACHE=/home/${USERNAME}/go/pkg/mod \
    GOCACHE=/home/${USERNAME}/.cache/go-build \
    PNPM_HOME=/home/${USERNAME}/.local/share/pnpm \
    NPM_CONFIG_CACHE=/home/${USERNAME}/.cache/npm \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    PATH=/usr/local/go/bin:/home/${USERNAME}/go/bin:/home/${USERNAME}/.local/share/pnpm:/home/${USERNAME}/.opencode/bin:${PATH}

# -----------------------------------------------------------------------------
# Root: paquetes del sistema + cliente PostgreSQL 17 (repo PGDG)
#
# Una sola capa APT para no repetir `apt-get update` tres veces.
# Se fija postgresql-client-17 para que coincida con el servidor de desarrollo.
# -----------------------------------------------------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg git zsh make jq vim unzip less \
    sudo openssh-client procps xz-utils zoxide locales; \
    sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen; \
    locale-gen en_US.UTF-8; \
    install -d /usr/share/postgresql-common/pgdg; \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc; \
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends postgresql-client-17; \
    rm -rf /var/lib/apt/lists/*; \
    psql --version

# -----------------------------------------------------------------------------
# Root: Node.js LTS (binario oficial + verificación de checksum)
# Evita el repo de terceros (NodeSource) y el `curl | bash`.
# -----------------------------------------------------------------------------
RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
    amd64) node_arch=x64 ;; \
    arm64) node_arch=arm64 ;; \
    *) echo "Arquitectura no soportada: $arch" >&2; exit 1 ;; \
    esac; \
    base="https://nodejs.org/dist/latest-v${NODE_MAJOR}.x"; \
    curl -fsSL "${base}/SHASUMS256.txt" -o /tmp/SHASUMS256.txt; \
    line="$(awk -v s="linux-${node_arch}.tar.xz" '$2 ~ s"$" {print; exit}' /tmp/SHASUMS256.txt)"; \
    [ -n "$line" ] || { echo "No se encontró el tarball de Node para ${node_arch}" >&2; exit 1; }; \
    file="${line##* }"; \
    cd /tmp; \
    curl -fsSL "${base}/${file}" -o "/tmp/${file}"; \
    echo "$line" | sha256sum -c -; \
    tar -xJf "/tmp/${file}" -C /usr/local --strip-components=1 --no-same-owner; \
    rm -f "/tmp/${file}" /tmp/SHASUMS256.txt; \
    node --version; \
    npm --version; \
    corepack enable --install-directory /usr/local/bin

# -----------------------------------------------------------------------------
# Root: Go SDK + herramientas de desarrollo
# El SDK se copia de la etapa go-sdk; las herramientas se instalan en
# /usr/local/bin (GOBIN) para que estén en el PATH del usuario. El usuario
# sigue usando $GOPATH/bin para futuros `go install`.
# -----------------------------------------------------------------------------
COPY --from=go-sdk /usr/local/go /usr/local/go

RUN --mount=type=cache,target=/home/${USERNAME}/go/pkg/mod,sharing=locked \
    --mount=type=cache,target=/home/${USERNAME}/.cache/go-build,sharing=locked \
    set -eux; \
    go version; \
    export GOFLAGS="-trimpath"; \
    GOBIN=/usr/local/bin go install -ldflags="-s -w" golang.org/x/tools/gopls@latest; \
    GOBIN=/usr/local/bin go install -ldflags="-s -w" github.com/go-delve/delve/cmd/dlv@latest; \
    GOBIN=/usr/local/bin go install -ldflags="-s -w" github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest; \
    gopls version; \
    dlv version; \
    golangci-lint --version

# -----------------------------------------------------------------------------
# Root: usuario, workspace y directorios compartidos
# -----------------------------------------------------------------------------
RUN set -eux; \
    groupadd --gid "${USER_GID}" "${USERNAME}"; \
    useradd --uid "${USER_UID}" --gid "${USER_GID}" -m -s /usr/bin/zsh "${USERNAME}"; \
    mkdir -p \
    /home/${USERNAME}/.config/opencode \
    /home/${USERNAME}/.cache/go-build \
    /home/${USERNAME}/.cache/npm \
    /home/${USERNAME}/.local/share/pnpm/store \
    /home/${USERNAME}/go/pkg/mod \
    /home/${USERNAME}/go/bin \
    /workspace/frontend/node_modules \
    /commandhistory; \
    printf 'store-dir=/home/%s/.local/share/pnpm/store\n' "${USERNAME}" > /home/${USERNAME}/.npmrc; \
    echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME}; \
    chmod 0440 /etc/sudoers.d/${USERNAME}; \
    chown -R "${USERNAME}:${USERNAME}" /home/${USERNAME} /workspace /commandhistory

# -----------------------------------------------------------------------------
# Root: historial de zsh + PATH para shells de login
# /etc/profile (Debian) redefine PATH y deja fuera las rutas del toolchain;
# estos dos hooks las restauran para shells de login e interactivos.
# -----------------------------------------------------------------------------
RUN printf '%s\n' \
    'export PATH="/usr/local/go/bin:$HOME/go/bin:$HOME/.local/share/pnpm:$HOME/.opencode/bin:$PATH"' \
    > /etc/profile.d/00-dev-toolchain.sh \
    && chmod 0644 /etc/profile.d/00-dev-toolchain.sh \
    && printf '%s\n' \
    '' \
    '# Toolchain (Go, pnpm, opencode) para shells interactivos' \
    'export PATH="/usr/local/go/bin:$HOME/go/bin:$HOME/.local/share/pnpm:$HOME/.opencode/bin:$PATH"' \
    '' \
    '# Historial compartido entre contenedores' \
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

# -----------------------------------------------------------------------------
# Usuario: OpenCode CLI
# El instalador vive en ~/.opencode/bin (ya está en PATH).
# -----------------------------------------------------------------------------
RUN set -eux; \
    curl -fsSL https://opencode.ai/v2/install -o /tmp/opencode-install.sh; \
    bash /tmp/opencode-install.sh --no-modify-path; \
    rm -f /tmp/opencode-install.sh; \
    test -x "${HOME}/.opencode/bin/opencode"

# -----------------------------------------------------------------------------
# Usuario: Oh My Zsh + plugins + zoxide
# -----------------------------------------------------------------------------
RUN set -eux; \
    curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o /tmp/omz-install.sh; \
    sh /tmp/omz-install.sh --unattended; \
    rm -f /tmp/omz-install.sh; \
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"; \
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"; \
    git clone --depth=1 https://github.com/zsh-users/zsh-completions.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-completions"; \
    git clone --depth=1 https://github.com/zsh-users/zsh-history-substring-search "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-history-substring-search"; \
    sed -i 's/^plugins=(git)$/plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions sudo zsh-history-substring-search)/' "$HOME/.zshrc"; \
    printf '\n# zoxide\neval "$(zoxide init zsh)"\n\n# Overlay opcional montado desde el host (.devcontainer/devcontainer.json)\n[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"\n' >> "$HOME/.zshrc"; \
    touch /commandhistory/.zsh_history

# -----------------------------------------------------------------------------
# Smoke test: falla el build si falta alguna herramienta clave
# -----------------------------------------------------------------------------
RUN set -eux; \
    go version; \
    node --version; \
    psql --version; \
    zsh --version
