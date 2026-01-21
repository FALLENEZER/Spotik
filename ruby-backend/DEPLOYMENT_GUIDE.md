# Ruby Backend Migration - Deployment Guide

## Overview

This guide provides comprehensive instructions for deploying the Ruby Backend Migration for the Spotik collaborative music streaming application. The Ruby backend replaces the Laravel backend while maintaining full API compatibility and improving WebSocket performance.

**Migration Status: ✅ PRODUCTION READY**

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [System Requirements](#system-requirements)
3. [Pre-Deployment Checklist](#pre-deployment-checklist)
4. [Deployment Methods](#deployment-methods)
5. [Configuration Management](#configuration-management)
6. [Database Migration](#database-migration)
7. [Performance Optimization](#performance-optimization)
8. [Monitoring and Health Checks](#monitoring-and-health-checks)
9. [Security Configuration](#security-configuration)
10. [Troubleshooting](#troubleshooting)
11. [Rollback Procedures](#rollback-procedures)

## Prerequisites

### Required Software
- **Ruby**: 3.2+ (recommended: 3.2.0)
- **PostgreSQL**: 12+ (existing database compatible)
- **Docker**: 20.10+ (for containerized deployment)
- **Docker Compose**: 2.0+ (for orchestration)
- **Git**: For source code management

### System Access
- SSH access to production servers
- Database administrator credentials
- SSL certificates for HTTPS
- Domain name configuration

### Migration Validation
Before deployment, ensure the following validations have passed:
- ✅ All property-based tests passing
- ✅ Compatibility tests with Laravel system
- ✅ Load testing completed successfully
- ✅ Security validation passed
- ✅ Performance benchmarks met

## System Requirements

### Minimum Production Requirements
- **CPU**: 4 cores (2.4GHz+)
- **RAM**: 8GB (16GB recommended)
- **Storage**: 100GB SSD (for application and logs)
- **Network**: 1Gbps connection
- **OS**: Ubuntu 20.04+ / CentOS 8+ / RHEL 8+

### Recommended Production Requirements
- **CPU**: 8 cores (3.0GHz+)
- **RAM**: 32GB
- **Storage**: 500GB NVMe SSD
- **Network**: 10Gbps connection
- **Load Balancer**: For high availability

### Database Requirements
- **PostgreSQL**: 12+ with existing Spotik schema
- **Connection Pool**: pgbouncer recommended
- **Backup Strategy**: Automated daily backups
- **Replication**: Master-slave setup for high availability

## Pre-Deployment Checklist

### ✅ Code Preparation
- [ ] Latest Ruby backend code pulled from repository
- [ ] All dependencies installed and verified
- [ ] Configuration files prepared for production environment
- [ ] SSL certificates obtained and configured
- [ ] Environment variables documented and secured

### ✅ Infrastructure Preparation
- [ ] Production servers provisioned and configured
- [ ] Database server accessible and optimized
- [ ] Load balancer configured (if applicable)
- [ ] Monitoring systems prepared
- [ ] Backup systems configured

### ✅ Testing Validation
- [ ] All unit tests passing
- [ ] All property-based tests passing
- [ ] Integration tests completed successfully
- [ ] Load testing results acceptable
- [ ] Security scan completed
- [ ] Performance benchmarks met

### ✅ Migration Planning
- [ ] Maintenance window scheduled
- [ ] Rollback plan prepared and tested
- [ ] Team notifications sent
- [ ] Monitoring alerts configured
- [ ] Post-deployment validation plan ready

## Deployment Methods

### Method 1: Docker Containerized Deployment (Recommended)

#### Step 1: Prepare Environment
```bash
# Clone the repository
git clone <repository-url>
cd ruby-backend

# Create production environment file
cp .env.example .env.production
```

#### Step 2: Configure Production Environment
Edit `.env.production`:
```bash
# Application Configuration
APP_ENV=production
APP_DEBUG=false
APP_NAME="Spotik Ruby Backend"
SERVER_HOST=0.0.0.0
SERVER_PORT=3000
SERVER_THREADS=8
SERVER_WORKERS=4

# Database Configuration
DATABASE_URL=postgresql://username:password@host:5432/spotik_production
DB_POOL_SIZE=20
DB_TIMEOUT=5000

# Security Configuration
JWT_SECRET=your-super-secure-jwt-secret-key-here
JWT_TTL=3600

# Performance Configuration
PERFORMANCE_MONITORING_ENABLED=true
CACHE_ENABLED=true
WEBSOCKET_PING_INTERVAL=30

# File Storage Configuration
STORAGE_PATH=/app/storage
UPLOAD_MAX_SIZE=50MB

# Logging Configuration
LOG_LEVEL=info
LOG_ROTATION=daily
```

#### Step 3: Build and Deploy
```bash
# Build production image
docker build -t spotik-ruby-backend:production .

# Start services with production configuration
docker-compose -f docker-compose.prod.yml up -d

# Verify deployment
docker-compose -f docker-compose.prod.yml ps
```

#### Step 4: Validate Deployment
```bash
# Run system validation
ruby scripts/system_validation.rb --url http://localhost:3000

# Run health checks
curl http://localhost:3000/health
curl http://localhost:3000/ready
curl http://localhost:3000/live
```

### Method 2: Direct Server Deployment

#### Step 1: Server Preparation
```bash
# Install Ruby 3.2+
sudo apt update
sudo apt install -y ruby3.2 ruby3.2-dev build-essential

# Install bundler
gem install bundler

# Create application user
sudo useradd -m -s /bin/bash spotik
sudo mkdir -p /opt/spotik
sudo chown spotik:spotik /opt/spotik
```

#### Step 2: Application Deployment
```bash
# Switch to application user
sudo su - spotik

# Clone and setup application
cd /opt/spotik
git clone <repository-url> ruby-backend
cd ruby-backend

# Install dependencies
bundle install --deployment --without development test

# Configure environment
cp .env.example .env.production
# Edit .env.production with production values

# Set up systemd service
sudo cp scripts/spotik-ruby-backend.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable spotik-ruby-backend
```

#### Step 3: Start Services
```bash
# Start the service
sudo systemctl start spotik-ruby-backend

# Check status
sudo systemctl status spotik-ruby-backend

# View logs
sudo journalctl -u spotik-ruby-backend -f
```

### Method 3: Kubernetes Deployment

#### Step 1: Prepare Kubernetes Manifests
```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spotik-ruby-backend
  labels:
    app: spotik-ruby-backend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: spotik-ruby-backend
  template:
    metadata:
      labels:
        app: spotik-ruby-backend
    spec:
      containers:
      - name: ruby-backend
        image: spotik-ruby-backend:production
        ports:
        - containerPort: 3000
        env:
        - name: APP_ENV
          value: "production"
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: spotik-secrets
              key: database-url
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: spotik-secrets
              key: jwt-secret
        livenessProbe:
          httpGet:
            path: /live
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "4Gi"
            cpu: "2000m"
```

#### Step 2: Deploy to Kubernetes
```bash
# Create namespace
kubectl create namespace spotik

# Create secrets
kubectl create secret generic spotik-secrets \
  --from-literal=database-url="postgresql://..." \
  --from-literal=jwt-secret="your-jwt-secret" \
  -n spotik

# Deploy application
kubectl apply -f k8s/ -n spotik

# Check deployment status
kubectl get pods -n spotik
kubectl get services -n spotik
```

## Configuration Management

### Environment Variables

#### Required Configuration
```bash
# Core Application
APP_ENV=production
APP_DEBUG=false
APP_NAME="Spotik Ruby Backend"
SERVER_HOST=0.0.0.0
SERVER_PORT=3000

# Database
DATABASE_URL=postgresql://user:pass@host:port/database
DB_POOL_SIZE=20
DB_TIMEOUT=5000

# Security
JWT_SECRET=your-secure-secret-key
JWT_TTL=3600

# Performance
SERVER_THREADS=8
SERVER_WORKERS=4
PERFORMANCE_MONITORING_ENABLED=true
```

#### Optional Configuration
```bash
# Caching
CACHE_ENABLED=true
CACHE_TTL=3600

# WebSocket
WEBSOCKET_PING_INTERVAL=30
WEBSOCKET_TIMEOUT=60

# File Storage
STORAGE_PATH=/app/storage
UPLOAD_MAX_SIZE=50MB

# Logging
LOG_LEVEL=info
LOG_ROTATION=daily
LOG_MAX_SIZE=100MB
```

### Configuration Validation
```bash
# Validate configuration before deployment
ruby scripts/validate_config.rb --env production

# Test configuration loading
ruby -e "
require_relative 'config/settings'
puts 'Configuration loaded successfully'
puts 'Environment: ' + SpotikConfig::Settings.app_env
puts 'Database configured: ' + (SpotikConfig::Settings.database_url ? 'Yes' : 'No')
"
```

## Database Migration

### Pre-Migration Steps

#### 1. Backup Existing Database
```bash
# Create full database backup
pg_dump -h localhost -U postgres -d spotik_production > spotik_backup_$(date +%Y%m%d_%H%M%S).sql

# Verify backup
pg_restore --list spotik_backup_*.sql
```

#### 2. Validate Schema Compatibility
```bash
# Run schema validation
ruby scripts/validate_database_schema.rb --database spotik_production

# Check for any required schema updates
ruby scripts/check_schema_compatibility.rb
```

### Migration Process

#### 1. Test Database Connection
```bash
# Test Ruby backend database connectivity
ruby -e "
require_relative 'config/database'
puts 'Testing database connection...'
db = SpotikConfig::Database.connection
puts 'Connection successful!'
puts 'Tables found: ' + db.tables.length.to_s
"
```

#### 2. Validate Data Integrity
```bash
# Run data integrity checks
ruby scripts/validate_data_integrity.rb

# Check for any data inconsistencies
ruby scripts/check_referential_integrity.rb
```

#### 3. Performance Optimization
```bash
# Apply performance indexes (if not already applied)
ruby scripts/apply_performance_indexes.rb

# Update database statistics
psql -d spotik_production -c "ANALYZE;"
```

### Post-Migration Validation
```bash
# Verify all tables are accessible
ruby scripts/test_database_operations.rb

# Run compatibility tests
ruby scripts/test_laravel_compatibility.rb

# Performance benchmark
ruby scripts/benchmark_database_performance.rb
```

## Performance Optimization

### Server Configuration

#### Ruby Server Optimization
```bash
# Optimal server configuration for production
export SERVER_THREADS=8        # CPU cores * 2
export SERVER_WORKERS=4        # CPU cores / 2
export DB_POOL_SIZE=20         # Threads * Workers / 2
export WEBSOCKET_PING_INTERVAL=30
```

#### System-Level Optimization
```bash
# Increase file descriptor limits
echo "spotik soft nofile 65536" >> /etc/security/limits.conf
echo "spotik hard nofile 65536" >> /etc/security/limits.conf

# Optimize TCP settings for WebSocket connections
echo "net.core.somaxconn = 65536" >> /etc/sysctl.conf
echo "net.ipv4.tcp_max_syn_backlog = 65536" >> /etc/sysctl.conf
sysctl -p
```

### Database Optimization

#### PostgreSQL Configuration
```sql
-- Optimize PostgreSQL for Ruby backend
ALTER SYSTEM SET shared_buffers = '4GB';
ALTER SYSTEM SET effective_cache_size = '12GB';
ALTER SYSTEM SET maintenance_work_mem = '1GB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET wal_buffers = '16MB';
ALTER SYSTEM SET default_statistics_target = 100;
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET effective_io_concurrency = 200;

-- Reload configuration
SELECT pg_reload_conf();
```

#### Connection Pooling with pgbouncer
```ini
# /etc/pgbouncer/pgbouncer.ini
[databases]
spotik_production = host=localhost port=5432 dbname=spotik_production

[pgbouncer]
listen_port = 6432
listen_addr = 127.0.0.1
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
server_reset_query = DISCARD ALL
max_client_conn = 1000
default_pool_size = 20
reserve_pool_size = 5
```

### Load Testing and Benchmarking
```bash
# Run comprehensive load test
ruby scripts/load_test.rb --concurrent 100 --operations 20 --duration 300

# Benchmark specific operations
ruby scripts/benchmark_operations.rb

# WebSocket performance test
ruby scripts/websocket_load_test.rb --connections 500
```

## Monitoring and Health Checks

### Health Check Endpoints

#### Basic Health Checks
```bash
# Basic server health
curl http://localhost:3000/health

# Database health
curl http://localhost:3000/health/database

# Configuration health
curl http://localhost:3000/health/configuration

# Performance health
curl http://localhost:3000/health/performance
```

#### Kubernetes Probes
```yaml
livenessProbe:
  httpGet:
    path: /live
    port: 3000
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /ready
    port: 3000
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
```

### Monitoring Setup

#### Prometheus Metrics (Optional)
```ruby
# Add to Gemfile for Prometheus integration
gem 'prometheus-client'

# Metrics endpoint
GET /metrics
```

#### Log Monitoring
```bash
# Configure log aggregation
# Logs are written to STDOUT in production for container compatibility

# For file-based logging:
LOG_FILE=/var/log/spotik/ruby-backend.log
LOG_ROTATION=daily
LOG_MAX_SIZE=100MB
```

#### Performance Monitoring
```bash
# Built-in performance monitoring endpoints
curl http://localhost:3000/api/performance/dashboard
curl http://localhost:3000/api/performance/metrics
curl http://localhost:3000/api/performance/health
```

### Alerting Configuration

#### Critical Alerts
- Server down (health check failures)
- Database connectivity issues
- High error rates (>5%)
- High response times (>500ms average)
- Memory usage >80%
- CPU usage >90%

#### Warning Alerts
- Response times >200ms average
- Memory usage >60%
- CPU usage >70%
- WebSocket connection failures
- Authentication failures spike

## Security Configuration

### SSL/TLS Configuration

#### Nginx Reverse Proxy (Recommended)
```nginx
# /etc/nginx/sites-available/spotik-ruby-backend
server {
    listen 443 ssl http2;
    server_name api.spotik.com;

    ssl_certificate /path/to/ssl/certificate.crt;
    ssl_certificate_key /path/to/ssl/private.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # WebSocket support
    location /ws {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }
}
```

### Security Headers
```ruby
# Security headers are automatically added by the Ruby backend
# Additional headers can be configured in the reverse proxy

# Content Security Policy
add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'";

# Security headers
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
```

### Firewall Configuration
```bash
# UFW firewall rules
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP (redirect to HTTPS)
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 5432/tcp  # PostgreSQL (if external)
sudo ufw enable

# Restrict database access
sudo ufw allow from 10.0.0.0/8 to any port 5432  # Internal network only
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Server Won't Start
```bash
# Check configuration
ruby scripts/validate_config.rb

# Check database connectivity
ruby scripts/test_database_connection.rb

# Check logs
tail -f /var/log/spotik/ruby-backend.log

# Check system resources
free -h
df -h
```

#### 2. Database Connection Issues
```bash
# Test database connection manually
psql -h localhost -U spotik_user -d spotik_production

# Check connection pool status
curl http://localhost:3000/health/database

# Verify database configuration
ruby -e "
require_relative 'config/database'
puts SpotikConfig::Database.connection_info
"
```

#### 3. WebSocket Connection Problems
```bash
# Test WebSocket endpoint
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" http://localhost:3000/ws

# Check WebSocket configuration
curl http://localhost:3000/api/websocket/status

# Monitor WebSocket connections
ruby scripts/monitor_websockets.rb
```

#### 4. Performance Issues
```bash
# Check system resources
top
htop
iotop

# Monitor database performance
ruby scripts/monitor_database_performance.rb

# Check for slow queries
tail -f /var/log/postgresql/postgresql-*.log | grep "slow query"

# Performance profiling
ruby scripts/profile_performance.rb
```

#### 5. Authentication Issues
```bash
# Test JWT token generation
ruby scripts/test_jwt_tokens.rb

# Verify authentication endpoints
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password"}'

# Check authentication configuration
ruby scripts/validate_auth_config.rb
```

### Log Analysis

#### Important Log Locations
```bash
# Application logs (Docker)
docker logs spotik-ruby-backend

# Application logs (systemd)
journalctl -u spotik-ruby-backend -f

# Nginx logs
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log

# PostgreSQL logs
tail -f /var/log/postgresql/postgresql-*.log
```

#### Log Analysis Commands
```bash
# Find errors in logs
grep -i error /var/log/spotik/ruby-backend.log

# Monitor response times
grep "response_time" /var/log/spotik/ruby-backend.log | tail -100

# Check authentication failures
grep "authentication.*failed" /var/log/spotik/ruby-backend.log

# Monitor WebSocket connections
grep "websocket" /var/log/spotik/ruby-backend.log | tail -50
```

## Rollback Procedures

### Emergency Rollback Plan

#### 1. Immediate Rollback (< 5 minutes)
```bash
# If using Docker
docker-compose -f docker-compose.prod.yml down
docker-compose -f docker-compose.laravel.yml up -d

# If using systemd
sudo systemctl stop spotik-ruby-backend
sudo systemctl start spotik-laravel-backend

# Update load balancer/reverse proxy
# Point traffic back to Laravel backend
```

#### 2. Database Rollback (if needed)
```bash
# Only if database changes were made
# Restore from backup
pg_restore -h localhost -U postgres -d spotik_production spotik_backup_YYYYMMDD_HHMMSS.sql

# Verify data integrity
ruby scripts/validate_data_integrity.rb --system laravel
```

#### 3. DNS/Load Balancer Rollback
```bash
# Update DNS records (if changed)
# Update load balancer configuration
# Verify traffic routing

# Test Laravel backend functionality
curl http://localhost:8000/api/health
```

### Rollback Validation
```bash
# Verify Laravel backend is working
php artisan health:check

# Test critical functionality
php artisan test --filter=CriticalTest

# Monitor error rates
tail -f /var/log/laravel/laravel.log
```

### Post-Rollback Actions
1. **Incident Report**: Document what went wrong
2. **Root Cause Analysis**: Identify the cause of the rollback
3. **Fix Planning**: Plan fixes for the identified issues
4. **Testing**: Ensure fixes are thoroughly tested
5. **Re-deployment Planning**: Plan the next deployment attempt

## Post-Deployment Validation

### Immediate Validation (0-15 minutes)
```bash
# 1. Health checks
curl http://localhost:3000/health
curl http://localhost:3000/ready
curl http://localhost:3000/live

# 2. API functionality
curl http://localhost:3000/api/auth/login -X POST \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password"}'

# 3. WebSocket connectivity
ruby scripts/test_websocket_connection.rb

# 4. Database connectivity
curl http://localhost:3000/health/database
```

### Extended Validation (15-60 minutes)
```bash
# 1. Load testing
ruby scripts/load_test.rb --concurrent 50 --duration 300

# 2. Integration testing
ruby scripts/run_integration_tests.rb

# 3. Performance monitoring
ruby scripts/monitor_performance.rb --duration 3600

# 4. Error rate monitoring
ruby scripts/monitor_error_rates.rb
```

### Long-term Monitoring (1+ hours)
- Monitor application metrics
- Check error rates and response times
- Verify WebSocket connection stability
- Monitor database performance
- Check memory and CPU usage trends

## Support and Maintenance

### Regular Maintenance Tasks

#### Daily
- Check application health status
- Monitor error rates and response times
- Review application logs for issues
- Verify backup completion

#### Weekly
- Review performance metrics
- Check database performance
- Update security patches
- Review monitoring alerts

#### Monthly
- Performance optimization review
- Security audit
- Capacity planning review
- Disaster recovery testing

### Getting Help

#### Documentation
- [Ruby Backend API Documentation](./API_DOCUMENTATION.md)
- [Configuration Reference](./CONFIGURATION.md)
- [Troubleshooting Guide](./TROUBLESHOOTING.md)

#### Support Contacts
- **Development Team**: dev-team@company.com
- **DevOps Team**: devops@company.com
- **Emergency Contact**: on-call@company.com

#### Monitoring Dashboards
- Application Health: http://monitoring.company.com/spotik-ruby
- Database Performance: http://monitoring.company.com/database
- Infrastructure Metrics: http://monitoring.company.com/infrastructure

---

## Conclusion

This deployment guide provides comprehensive instructions for successfully deploying the Ruby Backend Migration. The migration maintains full compatibility with the existing Laravel system while providing improved WebSocket performance and better resource utilization.

**Key Success Factors:**
- ✅ Thorough pre-deployment testing
- ✅ Proper configuration management
- ✅ Comprehensive monitoring setup
- ✅ Well-defined rollback procedures
- ✅ Post-deployment validation

For additional support or questions, please contact the development team or refer to the troubleshooting documentation.

**Deployment Status: 🚀 READY FOR PRODUCTION**