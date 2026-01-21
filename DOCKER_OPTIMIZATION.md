# Docker Configuration Optimization

This document outlines the optimizations made to the Spotik application's Docker configuration for production readiness.

## Overview

The Docker setup has been optimized with the following improvements:

1. **Multi-stage builds** for smaller production images
2. **Security enhancements** with non-root users
3. **Resource management** with limits and reservations
4. **Health checks** for all services
5. **Logging configuration** for production monitoring
6. **Build optimization** with caching and .dockerignore files

## Architecture

### Development Environment
- **Backend**: Laravel 12 with PHP-FPM running on port 9000
- **Frontend**: Vue.js development server on port 3000
- **WebSocket**: Laravel Reverb on port 8080
- **Database**: PostgreSQL 15 on port 5432
- **Cache**: Redis 7 on port 6379

### Production Environment
- **Nginx**: Reverse proxy with SSL termination (ports 80/443)
- **Backend**: Optimized Laravel with supervisor managing processes
- **Frontend**: Static files served by Nginx
- **WebSocket**: Laravel Reverb with production configuration
- **Queue Worker**: Dedicated container for background jobs
- **Database**: PostgreSQL with backup volume
- **Cache**: Redis with persistence and memory limits

## Optimizations Implemented

### 1. Multi-stage Dockerfiles

#### Backend Dockerfile
- **Base stage**: Common PHP extensions and dependencies
- **Development stage**: Includes dev dependencies and debugging tools
- **Production stage**: Optimized with Laravel caching and supervisor

Key optimizations:
- Single RUN command for package installation to reduce layers
- Build dependencies removed after compilation
- Composer cache mounting for faster builds
- Non-root user (www) for security
- Health checks for container monitoring

#### Frontend Dockerfile
- **Base stage**: Node.js with security tools (dumb-init)
- **Development stage**: Full development environment
- **Build stage**: Application compilation
- **Production stage**: Nginx serving static files

Key optimizations:
- npm cache mounting for faster builds
- Non-root nginx user
- Optimized nginx configuration
- Health check endpoints

### 2. Security Enhancements

#### Container Security
- Non-root users in all containers
- `no-new-privileges` security option
- Minimal base images (Alpine Linux)
- Read-only volumes where appropriate
- Secure environment variable handling

#### Database Security
- SCRAM-SHA-256 authentication
- Password-protected Redis
- Isolated network communication
- Encrypted sessions and cookies

### 3. Resource Management

#### Memory Limits
- **PostgreSQL**: 512M-1G (dev-prod)
- **Redis**: 256M-512M with LRU eviction
- **Backend**: 512M-1G for PHP processes
- **Frontend**: 256M for static serving
- **Queue Worker**: 512M for background jobs

#### CPU Limits
- Proportional CPU allocation based on service requirements
- Reserved resources for critical services
- Burst capacity for peak loads

### 4. Health Checks

All services include comprehensive health checks:

#### Backend Health Check
- Endpoint: `http://localhost:9000/ping`
- Checks: PHP-FPM process status
- Interval: 30s with 60s startup period

#### Frontend Health Check
- Endpoint: `http://localhost:8080/health`
- Checks: Nginx process and static file serving
- Interval: 30s with 30s startup period

#### Database Health Check
- Command: `pg_isready` with connection test
- Interval: 10s with 30s startup period

#### Redis Health Check
- Command: `redis-cli ping`
- Interval: 10s with 10s startup period

### 5. Logging Configuration

#### Production Logging
- JSON file driver with rotation (10MB, 3 files)
- Centralized log collection ready
- Error-level logging for production
- Separate log volumes for persistence

#### Log Locations
- **Backend**: `/var/www/html/storage/logs`
- **Nginx**: `/var/log/nginx`
- **Supervisor**: `/var/log/supervisor`

### 6. Build Optimization

#### .dockerignore Files
- Exclude unnecessary files from build context
- Reduce build time and image size
- Separate ignore files for backend and frontend

#### Caching Strategy
- Composer cache mounting for PHP dependencies
- npm cache mounting for Node.js dependencies
- Layer optimization with dependency installation first

## Environment Configuration

### Development Environment Variables
```bash
# Application
APP_ENV=local
APP_DEBUG=true

# Database
DB_HOST=postgres
DB_DATABASE=spotik
DB_USERNAME=spotik_user
DB_PASSWORD=spotik_password

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
```

### Production Environment Variables
```bash
# Application
APP_ENV=production
APP_DEBUG=false
APP_KEY=base64:your-32-character-secret-key

# Security
SESSION_SECURE_COOKIE=true
SESSION_SAME_SITE=strict
SESSION_ENCRYPT=true

# Performance
OCTANE_SERVER=swoole
OCTANE_HTTPS=true
```

## Deployment Commands

### Development Deployment
```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Scale services
docker-compose up -d --scale queue=2
```

### Production Deployment
```bash
# Build and start production services
docker-compose -f docker-compose.prod.yml up -d --build

# Monitor health
docker-compose -f docker-compose.prod.yml ps

# View production logs
docker-compose -f docker-compose.prod.yml logs -f --tail=100
```

## Monitoring and Maintenance

### Health Check Monitoring
```bash
# Check all service health
docker-compose ps

# Manual health check
curl http://localhost:8000/api/health
curl http://localhost:3000/health
```

### Resource Monitoring
```bash
# Container resource usage
docker stats

# Disk usage
docker system df

# Clean up unused resources
docker system prune -a
```

### Backup Procedures
```bash
# Database backup
docker-compose exec postgres pg_dump -U spotik_user spotik > backup.sql

# Volume backup
docker run --rm -v spotik_postgres_data:/data -v $(pwd):/backup alpine tar czf /backup/postgres_backup.tar.gz /data
```

## Performance Tuning

### PHP-FPM Configuration
- Dynamic process management
- 50 max children for production
- Request termination timeout: 300s
- Slow log monitoring enabled

### Nginx Configuration
- Gzip compression enabled
- Static asset caching (1 year)
- Rate limiting for API endpoints
- SSL/TLS optimization

### Redis Configuration
- Memory limit with LRU eviction
- Persistence enabled (AOF)
- Connection pooling optimized

### PostgreSQL Configuration
- Shared buffers optimized
- Connection limits configured
- Query performance monitoring

## Security Considerations

### Network Security
- Isolated Docker network
- No unnecessary port exposure
- Internal service communication

### Data Security
- Encrypted environment variables
- Secure session handling
- File upload validation
- SQL injection prevention

### Container Security
- Regular base image updates
- Vulnerability scanning
- Minimal attack surface
- Security headers enabled

## Troubleshooting

### Common Issues

#### Build Failures
```bash
# Clear build cache
docker builder prune -a

# Rebuild without cache
docker-compose build --no-cache
```

#### Health Check Failures
```bash
# Check container logs
docker-compose logs [service_name]

# Execute commands in container
docker-compose exec [service_name] sh
```

#### Performance Issues
```bash
# Monitor resource usage
docker stats

# Check service dependencies
docker-compose ps
```

### Debug Commands
```bash
# Enter container shell
docker-compose exec backend sh
docker-compose exec frontend sh

# Check service connectivity
docker-compose exec backend ping postgres
docker-compose exec backend ping redis
```

## Future Improvements

1. **Container Orchestration**: Kubernetes deployment manifests
2. **Monitoring**: Prometheus and Grafana integration
3. **Logging**: ELK stack integration
4. **Security**: Vulnerability scanning automation
5. **Performance**: CDN integration for static assets
6. **Backup**: Automated backup and restore procedures
7. **Scaling**: Horizontal scaling configuration
8. **CI/CD**: Automated testing and deployment pipelines