# Docker Containerization for Spotik Ruby Backend

This document describes the complete Docker containerization setup for the Spotik Ruby Backend, providing both development and production environments with comprehensive tooling and monitoring.

## Overview

The Docker setup includes:

- **Multi-stage Dockerfile** with development and production targets
- **Development environment** with hot reloading and debugging tools
- **Production environment** with Nginx reverse proxy and monitoring
- **Database management** with automated backups and development tools
- **Log aggregation** with Fluent Bit
- **Health checks** and monitoring endpoints
- **Security hardening** with non-root users and resource limits

## Quick Start

### Development Environment

```bash
# Setup environment files
make setup-env

# Start development environment
make dev

# View logs
make dev-logs

# Access development tools
make dev-tools
```

The development environment will be available at:
- Ruby Backend: http://localhost:3000
- Health Check: http://localhost:3000/health
- pgAdmin: http://localhost:5050 (admin@spotik.local / admin123)
- Redis Commander: http://localhost:8081
- Log Viewer: http://localhost:9999

### Production Environment

```bash
# Configure production environment
cp .env.production .env.prod
# Edit .env.prod with your production settings

# Start production environment
make prod

# Scale backend instances
make prod-scale REPLICAS=3
```

## Architecture

### Development Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Ruby Backend  │    │   PostgreSQL    │    │     Redis       │
│   (Port 3000)   │◄──►│   (Port 5433)   │    │   (Port 6380)   │
│                 │    │                 │    │                 │
│  Hot Reloading  │    │  Dev Database   │    │    Caching      │
│   Debug Mode    │    │   Test Data     │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ▲                       ▲                       ▲
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│    pgAdmin      │    │ Redis Commander │    │     Dozzle      │
│  (Port 5050)    │    │   (Port 8081)   │    │   (Port 9999)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Production Architecture

```
                    ┌─────────────────┐
                    │      Nginx      │
                    │  (Ports 80/443) │
                    │  Load Balancer  │
                    └─────────┬───────┘
                              │
                    ┌─────────▼───────┐
                    │  Ruby Backend   │
                    │   (Replicated)  │
                    │  Health Checks  │
                    └─────────┬───────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
┌───────▼───────┐    ┌────────▼────────┐    ┌──────▼──────┐
│  PostgreSQL   │    │     Redis       │    │ Fluent Bit  │
│   + Backup    │    │   (Secured)     │    │Log Aggreg.  │
└───────────────┘    └─────────────────┘    └─────────────┘
```

## Configuration

### Environment Variables

#### Development (.env)
```bash
APP_ENV=development
APP_DEBUG=true
DB_HOST=postgres
DB_NAME=spotik_development
LOG_LEVEL=debug
```

#### Production (.env.production)
```bash
APP_ENV=production
APP_DEBUG=false
DB_HOST=postgres
DB_NAME=spotik_production
LOG_LEVEL=info
JWT_SECRET=your_secure_secret_here
```

### Docker Compose Files

- `docker-compose.yml` - Base development configuration
- `docker-compose.override.yml` - Development overrides (auto-loaded)
- `docker-compose.prod.yml` - Production configuration

## Services

### Ruby Backend

**Development Features:**
- Hot reloading with `rerun` gem
- Debug port exposure (9229)
- Volume mounting for live code changes
- Development gems included

**Production Features:**
- Multi-stage build for smaller image
- Non-root user execution
- Resource limits and health checks
- Optimized for performance

### PostgreSQL Database

**Development:**
- Exposed port (5433) for direct access
- Test data initialization
- Development-specific indexes
- Query logging enabled

**Production:**
- Internal network only
- Automated backups with retention
- Performance tuning
- Connection pooling

### Nginx (Production Only)

- SSL/TLS termination
- Load balancing across backend instances
- Static file serving
- Rate limiting and security headers
- WebSocket proxy support

### Redis

- Caching layer (optional)
- Session storage
- Development tools integration

### Monitoring and Logging

- **Fluent Bit**: Log aggregation and forwarding
- **Health Checks**: Comprehensive health monitoring
- **Backup Service**: Automated database backups
- **Resource Monitoring**: CPU and memory limits

## Development Workflow

### Starting Development

```bash
# Clone and setup
git clone <repository>
cd ruby-backend

# Setup environment
make setup-env

# Start development environment
make dev

# View logs
make dev-logs

# Open shell in container
make dev-shell
```

### Development Tools

```bash
# Start development tools
make dev-tools

# Access pgAdmin
open http://localhost:5050

# Access Redis Commander
open http://localhost:8081

# View logs with Dozzle
open http://localhost:9999
```

### Testing

```bash
# Run all tests
make test

# Run unit tests only
make test-unit

# Run property-based tests
make test-property

# Generate coverage report
make test-coverage
```

### Database Management

```bash
# Reset development data
make db-reset-dev

# Generate test data
make db-generate-test-data ROOM_ID=dev-room-1 COUNT=10

# Access database shell
make dev-db-shell
```

## Production Deployment

### Prerequisites

1. Configure production environment:
```bash
cp .env.production .env.prod
# Edit .env.prod with production values
```

2. Setup SSL certificates (if using HTTPS):
```bash
mkdir -p docker/nginx/ssl
# Copy your SSL certificates
```

### Deployment Steps

```bash
# Build production images
make prod-build

# Start production environment
make prod

# Scale backend instances
make prod-scale REPLICAS=3

# Monitor deployment
make prod-logs
```

### Production Monitoring

```bash
# Check service health
make health

# Monitor resource usage
make monitor

# View real-time logs
make monitor-logs

# Create database backup
make db-backup
```

## Security Features

### Container Security

- **Non-root users**: All containers run as non-privileged users
- **Read-only filesystems**: Where applicable
- **Resource limits**: CPU and memory constraints
- **Security options**: `no-new-privileges` enabled
- **Network isolation**: Services communicate through internal networks

### Application Security

- **JWT token validation**: Secure authentication
- **Rate limiting**: API endpoint protection
- **CORS configuration**: Cross-origin request control
- **Security headers**: XSS, CSRF, and clickjacking protection
- **Input validation**: Request parameter sanitization

### Database Security

- **Connection encryption**: SSL/TLS for database connections
- **User privileges**: Minimal required permissions
- **Backup encryption**: Encrypted backup storage
- **Network isolation**: Database not exposed externally

## Monitoring and Alerting

### Health Checks

The application provides multiple health check endpoints:

- `/health` - Comprehensive health check
- `/health/database` - Database connectivity
- `/health/configuration` - Configuration validation
- `/health/storage` - File system health
- `/ready` - Kubernetes readiness probe
- `/live` - Kubernetes liveness probe

### Metrics Collection

- **Performance monitoring**: Request/response times
- **Resource usage**: Memory and CPU utilization
- **Error tracking**: Application and system errors
- **WebSocket metrics**: Connection counts and activity

### Log Aggregation

Fluent Bit collects and forwards logs from:
- Ruby application logs
- Nginx access and error logs
- System logs
- Database logs

## Backup and Recovery

### Automated Backups

- **Daily backups**: Automated PostgreSQL dumps
- **Retention policy**: Configurable retention period
- **Compression**: Gzip compression for storage efficiency
- **Verification**: Backup integrity checks

### Backup Commands

```bash
# Create manual backup
make db-backup

# Restore from backup
make db-restore BACKUP_FILE=backup_20231201_120000.sql.gz

# List available backups
docker-compose exec postgres-backup ls -la /backups/
```

## Troubleshooting

### Common Issues

#### Container Won't Start

```bash
# Check container logs
make logs

# Check service status
make status

# Rebuild containers
make build
```

#### Database Connection Issues

```bash
# Check database health
make health

# Access database shell
make dev-db-shell

# Reset database
make db-reset-dev
```

#### Performance Issues

```bash
# Monitor resource usage
make monitor

# Check application logs
make dev-logs

# Scale backend instances
make prod-scale REPLICAS=4
```

### Debug Commands

```bash
# Open shell in container
make shell

# Check container processes
docker-compose exec ruby-backend ps aux

# Check network connectivity
docker-compose exec ruby-backend ping postgres

# View container resource usage
docker stats
```

## Maintenance

### Regular Maintenance Tasks

```bash
# Update images
make update

# Clean unused resources
make prune

# Security scan
make security-scan

# Backup database
make db-backup
```

### Scaling

```bash
# Scale backend horizontally
make prod-scale REPLICAS=5

# Monitor scaled deployment
make monitor

# Check load distribution
make prod-logs
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Deploy Ruby Backend

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build and test
        run: |
          cd ruby-backend
          make build
          make test
      
      - name: Deploy to production
        run: |
          cd ruby-backend
          make prod-build
          make prod
```

### Docker Registry

```bash
# Tag images for registry
docker tag ruby-backend_ruby-backend:latest your-registry/spotik-ruby:latest

# Push to registry
docker push your-registry/spotik-ruby:latest

# Deploy from registry
docker-compose -f docker-compose.prod.yml pull
docker-compose -f docker-compose.prod.yml up -d
```

## Performance Optimization

### Production Optimizations

- **Multi-stage builds**: Smaller production images
- **Connection pooling**: Database connection optimization
- **Caching**: Redis caching layer
- **Load balancing**: Nginx upstream configuration
- **Resource limits**: Optimal CPU and memory allocation

### Monitoring Performance

```bash
# Real-time resource monitoring
make monitor

# Application performance metrics
curl http://localhost:3000/api/monitoring/performance

# Database performance
make dev-db-shell
# Then: SELECT * FROM pg_stat_activity;
```

## Support and Documentation

- **Health Checks**: http://localhost:3000/health
- **API Documentation**: http://localhost:3000/api
- **Logs**: `make logs` or `make dev-logs`
- **Monitoring**: Use development tools or production monitoring stack

For additional support, check the application logs and health check endpoints for detailed error information.