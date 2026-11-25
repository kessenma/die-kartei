# syntax=docker/dockerfile:1.6
# docs-site/Dockerfile: the static Die Kartei docs site.
#
# Build context is the REPOSITORY ROOT:
#   docker build -f docs-site/Dockerfile -t kartei-docs .
#   docker run --rm -p 8080:80 kartei-docs
#
# Output is plain HTML/CSS/JS served by nginx. There's no Node.js at runtime.

FROM node:22-slim AS builder
WORKDIR /site
COPY docs-site/package.json docs-site/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --no-audit --no-fund
COPY docs-site/ ./
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM nginx:stable-alpine AS runner
COPY docs-site/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /site/out /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO /dev/null http://127.0.0.1/ || exit 1
