# Stage 1: Build
FROM node:22-alpine AS builder

WORKDIR /app

COPY package*.json tsconfig.json ./
RUN npm install

COPY src/ ./src/
RUN npm run build


# Stage 2: Runtime
FROM node:22-alpine AS runtime

LABEL org.opencontainers.image.title="cloudflare-ddns"
LABEL org.opencontainers.image.description="Automatic Cloudflare DDNS updater — syncs A records when your public IPv4 changes"

WORKDIR /app

# Non-root user — create first, chown workdir + data dir, then switch before npm install
RUN addgroup -S ddns && adduser -S ddns -G ddns && chown ddns:ddns /app && mkdir -p /data && chown ddns:ddns /data
USER ddns
ENV HOME=/tmp

# Install only production deps (runs as ddns, so files are already owned correctly)
COPY --chown=ddns:ddns package*.json ./
RUN npm install --omit=dev --cache /tmp/.npm-cache && rm -rf /tmp/.npm-cache

# Copy compiled output
COPY --chown=ddns:ddns --from=builder /app/dist ./dist

# Persist state across restarts
VOLUME ["/data"]

CMD ["node", "dist/index.js"]
