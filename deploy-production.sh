#!/bin/bash

# Spotik Production Deployment Script
# This script handles the complete production deployment process

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.prod.yml"
ENV_FILE=".env.production"
BACKUP_DIR="./backups"
LOG_FILE="./deployment.log"

# Functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

# Pre-deployment checks
pre_deployment_checks() {
    log "Starting pre-deployment checks..."
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        error "Docker is not running. Please start Docker and try again."
    fi
    
    # Check if docker-compose is available
    if ! command -v docker-compose > /dev/null 2>&1; then
        error "docker-compose is not installed. Please install it and try again."
    fi
    
    # Check if production environment file exists
    if [ ! -f "$ENV_FILE" ]; then
        error "Production environment file ($ENV_FILE) not found. Please create it from .env.production.example"
    fi
    
    # Check if SSL certificates exist
    if [ ! -f "./docker/nginx/ssl/cert.pem" ] || [ ! -f "./docker/nginx/ssl/private.key" ]; then
        warning "SSL certificates not found. HTTPS will not work properly."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    success "Pre-deployment checks completed"
}

# Create backup
create_backup() {
    log "Creating backup..."
    
    mkdir -p "$BACKUP_DIR"
    BACKUP_NAME="backup_$(date +'%Y%m%d_%H%M%S')"
    
    # Backup database if running
    if docker-compose -f "$COMPOSE_FILE" ps postgres | grep -q "Up"; then
        log "Backing up database..."
        docker-compose -f "$COMPOSE_FILE" exec -T postgres pg_dump -U "${DB_USERNAME:-spotik_user}" "${DB_DATABASE:-spotik_prod}" > "$BACKUP_DIR/${BACKUP_NAME}_database.sql"
        success "Database backup created: $BACKUP_DIR/${BACKUP_NAME}_database.sql"
    fi
    
    # Backup volumes
    log "Backing up volumes..."
    docker run --rm \
        -v spotik_backend_storage:/data/storage \
        -v spotik_postgres_data:/data/postgres \
        -v "$PWD/$BACKUP_DIR":/backup \
        alpine tar czf "/backup/${BACKUP_NAME}_volumes.tar.gz" /data
    
    success "Volume backup created: $BACKUP_DIR/${BACKUP_NAME}_volumes.tar.gz"
}

# Build images
build_images() {
    log "Building Docker images..."
    
    # Build with no cache for production
    docker-compose -f "$COMPOSE_FILE" build --no-cache --parallel
    
    success "Docker images built successfully"
}

# Deploy services
deploy_services() {
    log "Deploying services..."
    
    # Stop existing services gracefully
    if docker-compose -f "$COMPOSE_FILE" ps | grep -q "Up"; then
        log "Stopping existing services..."
        docker-compose -f "$COMPOSE_FILE" down --timeout 30
    fi
    
    # Start services
    log "Starting services..."
    docker-compose -f "$COMPOSE_FILE" up -d
    
    success "Services deployed successfully"
}

# Wait for services to be healthy
wait_for_health() {
    log "Waiting for services to be healthy..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "Health check attempt $attempt/$max_attempts"
        
        # Check if all services are healthy
        local unhealthy_services=$(docker-compose -f "$COMPOSE_FILE" ps --filter "health=unhealthy" --format "table {{.Service}}" | tail -n +2)
        
        if [ -z "$unhealthy_services" ]; then
            success "All services are healthy"
            return 0
        fi
        
        log "Unhealthy services: $unhealthy_services"
        sleep 10
        ((attempt++))
    done
    
    error "Services failed to become healthy within the timeout period"
}

# Run post-deployment tasks
post_deployment_tasks() {
    log "Running post-deployment tasks..."
    
    # Run database migrations
    log "Running database migrations..."
    docker-compose -f "$COMPOSE_FILE" exec -T backend php artisan migrate --force
    
    # Clear and cache configuration
    log "Optimizing Laravel..."
    docker-compose -f "$COMPOSE_FILE" exec -T backend php artisan config:cache
    docker-compose -f "$COMPOSE_FILE" exec -T backend php artisan route:cache
    docker-compose -f "$COMPOSE_FILE" exec -T backend php artisan view:cache
    docker-compose -f "$COMPOSE_FILE" exec -T backend php artisan event:cache
    
    # Create storage link
    docker-compose -f "$COMPOSE_FILE" exec -T backend php artisan storage:link
    
    success "Post-deployment tasks completed"
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check API health
    local api_health=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/health || echo "000")
    if [ "$api_health" = "200" ]; then
        success "API health check passed"
    else
        error "API health check failed (HTTP $api_health)"
    fi
    
    # Check frontend
    local frontend_health=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/health || echo "000")
    if [ "$frontend_health" = "200" ]; then
        success "Frontend health check passed"
    else
        error "Frontend health check failed (HTTP $frontend_health)"
    fi
    
    success "Deployment verification completed"
}

# Cleanup old images and containers
cleanup() {
    log "Cleaning up old Docker resources..."
    
    # Remove unused images
    docker image prune -f
    
    # Remove unused volumes (be careful with this)
    # docker volume prune -f
    
    success "Cleanup completed"
}

# Main deployment function
main() {
    log "Starting Spotik production deployment..."
    
    # Load environment variables
    if [ -f "$ENV_FILE" ]; then
        export $(cat "$ENV_FILE" | grep -v '^#' | xargs)
    fi
    
    pre_deployment_checks
    
    # Ask for confirmation
    echo
    warning "This will deploy Spotik to production. This action will:"
    echo "  - Stop current services"
    echo "  - Create a backup"
    echo "  - Build new Docker images"
    echo "  - Deploy updated services"
    echo "  - Run database migrations"
    echo
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
    
    create_backup
    build_images
    deploy_services
    wait_for_health
    post_deployment_tasks
    verify_deployment
    cleanup
    
    success "Spotik production deployment completed successfully!"
    log "Deployment log saved to: $LOG_FILE"
    
    echo
    echo "Services are now running:"
    docker-compose -f "$COMPOSE_FILE" ps
    
    echo
    echo "Access your application at:"
    echo "  - Frontend: https://your-domain.com"
    echo "  - API: https://your-domain.com/api"
    echo "  - Health: https://your-domain.com/api/health"
}

# Handle script interruption
trap 'error "Deployment interrupted by user"' INT TERM

# Run main function
main "$@"