# Multi-stage Dockerfile for Vue.js frontend

# Base Node.js image
FROM node:20-alpine as base

# Install dumb-init for proper signal handling
RUN apk add --no-cache dumb-init

# Create non-root user (node user already exists in node:alpine)
RUN deluser --remove-home node || true && \
    addgroup -g 1000 -S appuser && \
    adduser -u 1000 -S appuser -G appuser

# Set working directory
WORKDIR /app

# Copy package files first for better caching
COPY --chown=appuser:appuser package*.json ./

# Development stage
FROM base as development

# Install all dependencies with caching
RUN --mount=type=cache,target=/root/.npm \
    npm ci --only=production=false

# Copy source code
COPY --chown=appuser:appuser . .

# Switch to non-root user
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000 || exit 1

# Expose port
EXPOSE 3000

# Start development server with proper signal handling
ENTRYPOINT ["dumb-init", "--"]
CMD ["npm", "run", "dev"]

# Build stage
FROM base as build

# Install all dependencies with caching
RUN --mount=type=cache,target=/root/.npm \
    npm ci

# Copy source code
COPY --chown=appuser:appuser . .

# Build the application
RUN npm run build

# Production stage
FROM nginx:1.25-alpine as production

# Install dumb-init for proper signal handling
RUN apk add --no-cache dumb-init

# Create non-root user for nginx
RUN addgroup -g 1000 -S nginx && \
    adduser -u 1000 -S nginx -G nginx

# Copy built application from build stage
COPY --from=build --chown=nginx:nginx /app/dist /usr/share/nginx/html

# Copy nginx configuration
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# Create nginx directories and set permissions
RUN mkdir -p /var/cache/nginx /var/log/nginx /var/run \
    && chown -R nginx:nginx /var/cache/nginx /var/log/nginx /var/run /usr/share/nginx/html \
    && chmod -R 755 /var/cache/nginx /var/log/nginx /var/run

# Switch to non-root user
USER nginx

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080 || exit 1

# Expose port
EXPOSE 8080

# Start nginx with proper signal handling
ENTRYPOINT ["dumb-init", "--"]
CMD ["nginx", "-g", "daemon off;"]