# syntax=docker/dockerfile:1.7
# Vitan Paperclip overlay — pure upstream + extras (Gemini CLI, Hermes agent, tsx).
# Philosophy: clone paperclipai/paperclip at ${PAPERCLIP_REF}, build it EXACTLY as upstream does,
# then add only what Vitan's agents need on top. No wrapper, no bootstrap layer — those belong in
# deployment config, not the image.

ARG NODE_IMAGE=node:lts-trixie-slim
ARG PAPERCLIP_REPO=https://github.com/paperclipai/paperclip.git
ARG PAPERCLIP_REF=v2026.416.0

# ---- Stage 1: base (mirrors upstream base stage) ----
FROM ${NODE_IMAGE} AS base
ARG USER_UID=1000
ARG USER_GID=1000
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates gosu curl git wget ripgrep python3 python3-pip python3-venv \
  && rm -rf /var/lib/apt/lists/* \
  && corepack enable

# Align node user UID/GID with host defaults (upstream convention)
RUN usermod -u ${USER_UID} --non-unique node \
  && groupmod -g ${USER_GID} --non-unique node \
  && usermod -g ${USER_GID} -d /paperclip node

# ---- Stage 2: clone + build upstream paperclip ----
FROM base AS paperclip-build
ARG PAPERCLIP_REPO
ARG PAPERCLIP_REF
WORKDIR /src
RUN git clone --depth 1 --branch "${PAPERCLIP_REF}" "${PAPERCLIP_REPO}" .
RUN pnpm install --frozen-lockfile
RUN pnpm --filter @paperclipai/ui build
RUN pnpm --filter @paperclipai/plugin-sdk build
RUN pnpm --filter @paperclipai/server build
RUN test -f server/dist/index.js

# ---- Stage 3: production runtime ----
FROM base AS production
ARG USER_UID=1000
ARG USER_GID=1000
WORKDIR /app

# Copy the built Paperclip tree (owned by node)
COPY --chown=node:node --from=paperclip-build /src /app

# Upstream bakes claude-code, codex, opencode — do the same so parity holds.
# Vitan adds: Gemini CLI (BB/BS/HR/DPM/OC), tsx, Hermes Agent Python CLI (hermes_local adapter).
RUN npm install --global --omit=dev \
      @anthropic-ai/claude-code@latest \
      @openai/codex@latest \
      opencode-ai \
      @google/gemini-cli@0.38.1 \
      tsx \
  && pip install --break-system-packages git+https://github.com/NousResearch/hermes-agent.git \
  && mkdir -p /paperclip \
  && chown node:node /paperclip

# Upstream's entrypoint (handles UID/GID remap + volume chown then execs as node)
COPY --from=paperclip-build /src/scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENV NODE_ENV=production \
    HOME=/paperclip \
    HOST=0.0.0.0 \
    PORT=3100 \
    SERVE_UI=true \
    PAPERCLIP_HOME=/paperclip \
    PAPERCLIP_INSTANCE_ID=default \
    USER_UID=${USER_UID} \
    USER_GID=${USER_GID} \
    PAPERCLIP_CONFIG=/paperclip/instances/default/config.json \
    PAPERCLIP_DEPLOYMENT_MODE=authenticated \
    PAPERCLIP_DEPLOYMENT_EXPOSURE=private \
    OPENCODE_ALLOW_ALL_MODELS=true

VOLUME ["/paperclip"]
EXPOSE 3100
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["node", "/app/server/dist/index.js"]
