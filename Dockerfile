# syntax=docker/dockerfile:1
FROM ghcr.io/astral-sh/uv:0.12.13@sha256:b485bd65cc2cf1c9a93b3554012c9c3778cf7b1b5fd3d3096ce9e1226c97e1e6 AS uv
FROM node:22-trixie-slim@sha256:7b8a0c89c54499bee567618f96578e1a12a800f062fbdbfd1fb6a443fa6f6284

ARG OPENCODE_VERSION=1.18.29
ARG PNPM_VERSION=12.4.1
ARG HOST_UID=1000
ARG HOST_GID=1000

# Debian supplies signed security updates on rebuild. Base images and npm
# tools are pinned; installed Debian package versions are recorded for audits.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates git gh curl wget jq bash openssh-client ripgrep fd-find \
      unzip zip tar xz-utils build-essential pkg-config python3 python3-venv \
      openjdk-21-jdk-headless maven procps iproute2 less \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && mkdir -p /usr/local/share/opencode-stack \
    && dpkg-query -W > /usr/local/share/opencode-stack/debian-packages.tsv \
    && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /uvx /usr/local/bin/
# npm selects OpenCode's official glibc binary for this platform. No frameworks
# or credentials belong in the image, and nothing is installed at startup.
RUN npm install --global "opencode-ai@${OPENCODE_VERSION}" "pnpm@${PNPM_VERSION}" \
    && npm cache clean --force

# Reuse the official Node image's account instead of assuming UID 1000 is free.
RUN test "$HOST_UID" -gt 0 && test "$HOST_GID" -gt 0 \
    && groupmod --new-name opencode --gid "$HOST_GID" node \
    && usermod --login opencode --uid "$HOST_UID" --gid "$HOST_GID" \
         --home /home/opencode --shell /bin/bash node \
    && install -d -m 0700 -o "$HOST_UID" -g "$HOST_GID" /home/opencode /tmp/opencode \
    && install -d -o "$HOST_UID" -g "$HOST_GID" \
         /home/opencode/.config /home/opencode/.config/opencode /home/opencode/.cache \
         /home/opencode/.local /home/opencode/.local/share /home/opencode/.local/state \
         /home/opencode/.local/share/opencode /home/opencode/.local/state/opencode

ENV HOME=/home/opencode \
    SHELL=/bin/bash \
    LANG=C.UTF-8 \
    BUN_RUNTIME_TRANSPILER_CACHE_PATH=0
COPY --chmod=755 scripts/container-entrypoint.sh /usr/local/bin/workstation-entrypoint
COPY --chmod=755 scripts/toolchain-check.sh /usr/local/bin/toolchain-check
COPY --chmod=755 scripts/browser-check.py /usr/local/bin/browser-check
USER ${HOST_UID}:${HOST_GID}
WORKDIR /home/opencode
ENTRYPOINT ["workstation-entrypoint"]
CMD ["serve", "--hostname", "0.0.0.0", "--port", "4096"]
