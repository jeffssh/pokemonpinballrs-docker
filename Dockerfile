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

# --- TAS / verification toolchain (added AFTER agbcc to keep that heavy ---
# --- layer cached) ---
# Two halves of the 1:1-matching workflow live here:
#
#   1. mGBA  — the reference GBA emulator. mgba-qt is the GUI you open over
#      XQuartz to watch frame-by-frame and weigh in on diffs; the headless
#      `mgba` Python bindings (installed below) load baserom.gba, write
#      emulator memory (force RNG spawns), step frames, and dump the native
#      240x160 framebuffer. mGBA has no movie-file format, so input is driven
#      programmatically (see pokemon-pinball-table/tools/gba/).
#
#   2. The Go/Ebiten recreation must also render headless IN this container so
#      its GBA-region output can be diffed against the emulator reference. That
#      needs the Go toolchain, Xvfb (Ebiten requires a GL context even
#      offscreen), and Ebiten's X11/GL build+runtime deps. These were
#      previously installed by hand in the running container (snapshot.sh
#      already assumes ~/.local/go + xvfb-run) and would vanish on a --build
#      recreate; baking them makes the verification workflow reproducible.
#
# python3-pil / python3-numpy are apt (clean, shared) for frame diffing and
# the existing tools/rip-*.py scripts; the venv below inherits them.
RUN apt-get update && apt-get install -y --no-install-recommends \
    mgba-qt \
    xvfb \
    xauth \
    libgl1-mesa-dri \
    libgl1-mesa-dev \
    libxcursor-dev \
    libxrandr-dev \
    libxinerama-dev \
    libxi-dev \
    libxxf86vm-dev \
    libasound2-dev \
    pkg-config \
    python3-pip \
    python3-venv \
    python3-pil \
    python3-numpy \
    && rm -rf /var/lib/apt/lists/*

# Create jeff user with matching host uid/gid.
# macOS staff gid=20 — create matching group. Keeps host file ownership
# correct on the bind-mounted pokepinballrs working tree (so host git works).
RUN groupadd -g 20 staff 2>/dev/null || true && \
    useradd -m -u 501 -g 20 -d /Users/jeff -s /bin/bash jeff && \
    echo "jeff ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/jeff && \
    chown -R 501:20 /opt/agbcc

# --- Go toolchain ---
# Installed to /Users/jeff/.local/go to match snapshot.sh and the recreation's
# CLAUDE.md ($HOME/.local/go/bin). dpkg arch (arm64|amd64) matches Go's tarball
# naming, so the same line builds correctly on both target platforms. >= the
# go.mod toolchain (1.23.2) so no on-build toolchain download is triggered.
ARG GO_VERSION=1.23.6
RUN arch="$(dpkg --print-architecture)" && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz" -o /tmp/go.tgz && \
    install -d -o 501 -g 20 /Users/jeff/.local && \
    tar -C /Users/jeff/.local -xzf /tmp/go.tgz && \
    rm /tmp/go.tgz && \
    chown -R 501:20 /Users/jeff/.local

# --- mGBA Python bindings (headless verification engine) ---
# Debian ships no python3-mgba, and bookworm's Python is externally-managed
# (PEP 668), so the bindings go in their own venv. --system-site-packages lets
# the harness import the apt-provided PIL/numpy too. The `mgba` wheel exposes
# memory read/WRITE via typed domain views (core.memory.iwram.u8[addr]=v),
# frame stepping, key input, and framebuffer dump — everything the harness needs.
RUN python3 -m venv --system-site-packages /opt/emu-venv && \
    /opt/emu-venv/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/emu-venv/bin/pip install --no-cache-dir mgba && \
    chown -R 501:20 /opt/emu-venv

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

# Go on PATH (matches snapshot.sh) + the mGBA venv first so bare `python3`
# resolves to the interpreter that can `import mgba` (and, via
# --system-site-packages, PIL/numpy for the existing tools/rip-*.py scripts).
ENV PATH="/Users/jeff/.local/go/bin:/opt/emu-venv/bin:${PATH}"

# Debian's /etc/profile UNCONDITIONALLY resets PATH for login shells, dropping
# the ENV above. Re-add the toolchain via profile.d so `bash -l` (snapshot.sh,
# agent shells) also finds go + the mGBA venv.
RUN printf '%s\n' \
    'case ":$PATH:" in' \
    '  *:/Users/jeff/.local/go/bin:*) ;;' \
    '  *) PATH="/Users/jeff/.local/go/bin:/opt/emu-venv/bin:$PATH"; export PATH ;;' \
    'esac' \
    > /etc/profile.d/10-pinball-toolchain.sh

USER jeff
RUN mkdir -p /Users/jeff/Documents/github/pokemonpinballrs-docker/pokepinballrs \
             /Users/jeff/Documents/github/pokemonpinballrs-docker/pokemon-pinball-table
WORKDIR /Users/jeff/Documents/github/pokemonpinballrs-docker/pokemon-pinball-table

ENTRYPOINT ["claude", "--dangerously-skip-permissions"]
