FROM debian:bookworm

# --- System deps for a pret-style GBA decomp ---
# build-essential/g++  : agbcc + the C++ `preproc` tool
# binutils/gcc-arm...   : arm-none-eabi assembler/linker (devkitARM alternative,
#                         per INSTALL.md, for Linux)
# libpng-dev            : gbagfx graphics tooling
# jq, python3           : helper scripts
# git, ca-certificates  : repo + agbcc clone
# ripgrep, sudo         : agent ergonomics
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    binutils-arm-none-eabi \
    gcc-arm-none-eabi \
    libpng-dev \
    libnewlib-arm-none-eabi \
    make \
    git \
    jq \
    python3 \
    ripgrep \
    ca-certificates \
    curl \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Node.js (just enough to install claude-code)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# --- Prebuild agbcc into the image ---
# The heavy compile bakes into this layer (cached across rebuilds).
# install.sh copies bin/lib/include into a project at runtime — that step
# can't run here because the project is a runtime-mounted volume, so it
# runs once on container start (see start.sh). The built tree + its
# install.sh persist at /opt/agbcc.
RUN git clone --depth 1 https://github.com/pret/agbcc /opt/agbcc && \
    cd /opt/agbcc && ./build.sh

# Create jeff user with matching host uid/gid.
# macOS staff gid=20 — create matching group. Keeps host file ownership
# correct on the bind-mounted pokepinballrs working tree (so host git works).
RUN groupadd -g 20 staff 2>/dev/null || true && \
    useradd -m -u 501 -g 20 -d /Users/jeff -s /bin/bash jeff && \
    echo "jeff ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/jeff && \
    chown -R 501:20 /opt/agbcc

# Docker Desktop's macOS file sharing presents the bind-mounted repo as
# root-owned to the container, so git's dubious-ownership guard would
# refuse it and ignore .git/config (no identity -> can't commit). Trust
# exactly this one path, system-wide and durable (survives container
# recreate). autoSetupMerge=false trims spurious .git/config writes that
# would otherwise warn against the read-only config mount.
RUN git config --system --add safe.directory /Users/jeff/Documents/github/pokemonpinballrs-docker/pokepinballrs && \
    git config --system --add safe.directory /Users/jeff/Documents/github/pokemonpinballrs-docker/pokemon-pinball-table && \
    git config --system branch.autoSetupMerge false

# Disable auto-updater and telemetry in container
ENV DISABLE_AUTOUPDATER=1
ENV DISABLE_TELEMETRY=1

# Use system ripgrep
ENV USE_BUILTIN_RIPGREP=0

USER jeff
RUN mkdir -p /Users/jeff/Documents/github/pokemonpinballrs-docker/pokepinballrs \
             /Users/jeff/Documents/github/pokemonpinballrs-docker/pokemon-pinball-table
WORKDIR /Users/jeff/Documents/github/pokemonpinballrs-docker/pokepinballrs

ENTRYPOINT ["claude", "--dangerously-skip-permissions"]
