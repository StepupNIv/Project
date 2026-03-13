# ─── Stage 1: Dependencies ───────────────────────────────────────────────────
FROM node:18-alpine AS deps
LABEL maintainer="devops-team"

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install production dependencies only
RUN npm ci --only=production && npm cache clean --force

# ─── Stage 2: Builder ────────────────────────────────────────────────────────
FROM node:18-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci && npm cache clean --force

COPY . .

# Run linting and tests during build (optional - CI can skip with --build-arg SKIP_TESTS=true)
ARG SKIP_TESTS=false
RUN if [ "$SKIP_TESTS" = "false" ]; then npm run lint || true; fi

# ─── Stage 3: Production Runner ──────────────────────────────────────────────
FROM node:18-alpine AS runner

# Security: create non-root user
RUN addgroup -g 1001 -S appgroup && \
    adduser  -u 1001 -S appuser -G appgroup

WORKDIR /app

# Copy production deps from deps stage
COPY --from=deps --chown=appuser:appgroup /app/node_modules ./node_modules

# Copy application source
COPY --chown=appuser:appgroup . .

# Remove dev files
RUN rm -f .env .env.* *.test.js

# Use non-root user
USER appuser

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Environment defaults
ENV NODE_ENV=production \
    PORT=3000

# Start application
CMD ["node", "src/index.js"]
