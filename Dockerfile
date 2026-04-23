# Build upstream Paperclip from a pinned ref.
FROM node:22-bookworm AS paperclip-build
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
               ca-certificates \
                          curl \
                                     git \
                                         && rm -rf /var/lib/apt/lists/*
                                         RUN corepack enable

                                         ARG PAPERCLIP_REPO=https://github.com/paperclipai/paperclip.git
                                         ARG PAPERCLIP_REF=v2026.416.0

                                         WORKDIR /paperclip
                                         RUN git clone --depth 1 --branch "${PAPERCLIP_REF}" "${PAPERCLIP_REPO}" .
                                         RUN pnpm install --frozen-lockfile
                                         RUN pnpm --filter @paperclipai/ui build
                                         RUN pnpm --filter @paperclipai/plugin-sdk build
                                         RUN pnpm --filter @paperclipai/server build
                                         RUN test -f server/dist/index.js

                                         # Runtime image (direct Paperclip server, no wrapper).
                                         FROM node:22-bookworm
                                         ENV NODE_ENV=production

                                         RUN apt-get update \
                                             && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
                                                        ca-certificates \
                                                                   curl \
                                                                              gosu \
                                                                                         git \
                                                                                                    ripgrep \
                                                                                                               python3 \
                                                                                                                          python3-pip \
                                                                                                                                     python3-venv \
                                                                                                                                         && rm -rf /var/lib/apt/lists/*
                                                                                                                                         RUN corepack enable
                                                                                                                                         
                                                                                                                                         # Install Hermes Agent CLI from GitHub source (not on PyPI).
                                                                                                                                         RUN pip install --break-system-packages git+https://github.com/NousResearch/hermes-agent.git
                                                                                                                                         
                                                                                                                                         WORKDIR /app
                                                                                                                                         # Use --chown to set ownership during COPY (avoids memory-heavy chown -R)
                                                                                                                                         COPY --from=paperclip-build --chown=node:node /paperclip /app
                                                                                                                                         
                                                                                                                                         WORKDIR /wrapper
                                                                                                                                         COPY --chown=node:node package.json /wrapper/package.json
                                                                                                                                         RUN npm install --omit=dev && npm cache clean --force
                                                                                                                                         COPY --chown=node:node src /wrapper/src
                                                                                                                                         COPY --chown=node:node scripts/entrypoint.sh /wrapper/entrypoint.sh
                                                                                                                                         COPY --chown=node:node scripts/bootstrap-ceo.mjs /wrapper/template/bootstrap-ceo.mjs
                                                                                                                                         RUN chmod +x /wrapper/entrypoint.sh
                                                                                                                                         
                                                                                                                                         # Optional local adapters/tools parity with upstream Dockerfile.
                                                                                                                                         RUN npm install --global --omit=dev @anthropic-ai/claude-code@latest @openai/codex@latest opencode-ai
                                                                                                                                         RUN npm install --global --omit=dev @google/gemini-cli@0.38.1
                                                                                                                                         RUN npm install --global --omit=dev tsx
                                                                                                                                         RUN mkdir -p /paperclip && chown node:node /paperclip
                                                                                                                                         
                                                                                                                                         # Railway sets PORT at runtime and this process binds to it.
                                                                                                                                         # Entrypoint runs as root, fixes /paperclip volume permissions, then execs as node.
                                                                                                                                         EXPOSE 3100
                                                                                                                                         ENTRYPOINT ["/wrapper/entrypoint.sh"]
                                                                                                                                         CMD ["node", "/wrapper/src/server.js"]
