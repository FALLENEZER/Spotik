# Multi-stage Ruby Backend Dockerfile for Spotik
# Migration from Laravel to Ruby with native WebSocket support

# Build stage
FROM ruby:3.2.0-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    postgresql-dev \
    git

# Set working directory
WORKDIR /app

# Copy Gemfile and install dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle config --global frozen 1 && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

# Development stage
FROM ruby:3.2.0-alpine AS development

# Install runtime and development dependencies
RUN apk add --no-cache \
    postgresql-dev \
    tzdata \
    curl \
    bash \
    git \
    less

# Set working directory
WORKDIR /app

# Copy gems from builder
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Copy application code
COPY . .

# Create necessary directories
RUN mkdir -p logs storage/tracks storage/temp tmp public

# Create non-root user
RUN addgroup -g 1000 -S spotik && \
    adduser -u 1000 -S spotik -G spotik

# Change ownership of app directory
RUN chown -R spotik:spotik /app

# Switch to non-root user
USER spotik

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Start server with development configuration
CMD ["ruby", "server.rb"]

# Production stage
FROM ruby:3.2.0-alpine AS production

# Install only runtime dependencies
RUN apk add --no-cache \
    postgresql-dev \
    tzdata \
    curl \
    ca-certificates

# Set working directory
WORKDIR /app

# Copy gems from builder (production only)
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Copy application code (excluding development files)
COPY --chown=1000:1000 app/ ./app/
COPY --chown=1000:1000 config/ ./config/
COPY --chown=1000:1000 public/ ./public/
COPY --chown=1000:1000 server.rb Gemfile Gemfile.lock ./

# Create necessary directories with proper permissions
RUN mkdir -p logs storage/tracks storage/temp tmp && \
    chown -R 1000:1000 logs storage tmp

# Create non-root user
RUN addgroup -g 1000 -S spotik && \
    adduser -u 1000 -S spotik -G spotik

# Switch to non-root user
USER spotik

# Expose port
EXPOSE 3000

# Health check with longer intervals for production
HEALTHCHECK --interval=60s --timeout=10s --start-period=60s --retries=5 \
    CMD curl -f http://localhost:3000/health || exit 1

# Production startup command
CMD ["ruby", "server.rb"]