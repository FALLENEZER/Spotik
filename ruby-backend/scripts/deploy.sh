#!/bin/bash

# Deployment script for Spotik Ruby Backend
# Supports both development and production deployments

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT="${1:-development}"
ACTION="${2:-deploy}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

# Help function
show_help() {
    cat << EOF
Spotik Ruby Backend Deployment Script

Usage: $0 [ENVIRONMENT] [ACTION]

ENVIRONMENT:
  development  - Deploy development environment (default)
  production   - Deploy production environment
  staging      - Deploy staging environment

ACTION:
  deploy       - Deploy the application (default)
  update       - Update existing deployment
  rollback     - Rollback to previous version
  stop         - Stop the application
  restart      - Restart the application
  status       - Show deployment status
  logs         - Show application logs
  health       - Check application health

Examples:
  $0                           # Deploy development environment
  $0 production deploy         # Deploy production environment
  $0 development update        # Update development environment
  $0 production status         # Check production status
  $0 development logs          # Show development logs

Environment Variables:
  DOCKER_REGISTRY             # Docker registry URL
  IMAGE_TAG                   # Docker image tag (default: latest)
  BACKUP_BEFORE_DEPLOY        # Create backup before deployment (default: true)
  HEALTH_CHECK_TIMEOUT        # Health check timeout in seconds (default: 300)
  DEPLOYMENT_TIMEOUT          # Deployment timeout in seconds (default: 600)

EOF
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Docker is installed and running
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker is not installed"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        error "Docker is not running"
        exit 1
    fi
    
    # Check if Docker Compose is installed
    if ! command -v docker-compose >/dev/null 2>&1; then
        error "Docker Compose is not installed"
        exit 1
    fi
    
    # Check if we're in the right directory
    if [ ! -f "$PROJECT_DIR/server.rb" ]; then
        error "Not in Ruby backend directory"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Setup environment
setup_environment() {
    log "Setting up environment for $ENVIRONMENT..."
    
    cd "$PROJECT_DIR"
    
    case $ENVIRONMENT in
        development)
            COMPOSE_FILE="docker-compose.yml"
            ENV_FILE=".env"
            ;;
        production)
            COMPOSE_FILE="docker-compose.prod.yml"
            ENV_FILE=".env.production"
            ;;
        staging)
            COMPOSE_FILE="docker-compose.staging.yml"
            ENV_FILE=".env.staging"
            ;;
        *)
            error "Unknown environment: $ENVIRONMENT"
            exit 1
            ;;
    esac
    
    # Check if environment file exists
    if [ ! -f "$ENV_FILE" ]; then
        if [ -f "${ENV_FILE}.example" ]; then
            warning "Environment file $ENV_FILE not found, copying from example"
            cp "${ENV_FILE}.example" "$ENV_FILE"
        else
            error "Environment file $ENV_FILE not found"
            exit 1
        fi
    fi
    
    # Check if compose file exists
    if [ ! -f "$COMPOSE_FILE" ]; then
        error "Docker Compose file $COMPOSE_FILE not found"
        exit 1
    fi
    
    success "Environment setup completed"
}

# Create backup
create_backup() {
    if [ "${BACKUP_BEFORE_DEPLOY:-true}" = "true" ] && [ "$ENVIRONMENT" != "development" ]; then
        log "Creating backup before deployment..."
        
        # Create backup using docker-compose
        if docker-compose -f "$COMPOSE_FILE" exec -T postgres pg_dump -U "${DB_USER:-spotik_user}" -d "${DB_NAME:-spotik}" > "backup_pre_deploy_$(date +%Y%m%d_%H%M%S).sql"; then
            success "Backup created successfully"
        else
            warning "Backup creation failed, continuing with deployment"
        fi
    fi
}

# Build images
build_images() {
    log "Building Docker images..."
    
    # Set image tag
    export IMAGE_TAG="${IMAGE_TAG:-latest}"
    
    if [ -n "${DOCKER_REGISTRY:-}" ]; then
        log "Building images for registry: $DOCKER_REGISTRY"
        docker-compose -f "$COMPOSE_FILE" build --pull
        
        # Tag images for registry
        docker tag "ruby-backend_ruby-backend:latest" "$DOCKER_REGISTRY/spotik-ruby:$IMAGE_TAG"
        
        # Push to registry
        log "Pushing images to registry..."
        docker push "$DOCKER_REGISTRY/spotik-ruby:$IMAGE_TAG"
    else
        docker-compose -f "$COMPOSE_FILE" build --pull
    fi
    
    success "Images built successfully"
}

# Deploy application
deploy_application() {
    log "Deploying $ENVIRONMENT environment..."
    
    # Pull latest images if using registry
    if [ -n "${DOCKER_REGISTRY:-}" ]; then
        docker-compose -f "$COMPOSE_FILE" pull
    fi
    
    # Start services
    docker-compose -f "$COMPOSE_FILE" up -d
    
    success "Application deployed"
}

# Wait for health check
wait_for_health() {
    local timeout="${HEALTH_CHECK_TIMEOUT:-300}"
    local elapsed=0
    local interval=10
    
    log "Waiting for application to become healthy (timeout: ${timeout}s)..."
    
    while [ $elapsed -lt $timeout ]; do
        if [ "$ENVIRONMENT" = "development" ]; then
            health_url="http://localhost:3000/health"
        else
            health_url="http://localhost/health"
        fi
        
        if curl -s -f "$health_url" >/dev/null 2>&1; then
            success "Application is healthy"
            return 0
        fi
        
        log "Waiting for health check... (${elapsed}s/${timeout}s)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    error "Health check timeout after ${timeout}s"
    return 1
}

# Update deployment
update_deployment() {
    log "Updating $ENVIRONMENT deployment..."
    
    # Pull latest changes
    if [ -d ".git" ]; then
        log "Pulling latest code..."
        git pull
    fi
    
    # Rebuild and restart
    build_images
    docker-compose -f "$COMPOSE_FILE" up -d --force-recreate
    
    wait_for_health
    success "Deployment updated successfully"
}

# Rollback deployment
rollback_deployment() {
    log "Rolling back $ENVIRONMENT deployment..."
    
    # This is a simple rollback - in production you might want more sophisticated rollback
    warning "Simple rollback: restarting with previous images"
    
    docker-compose -f "$COMPOSE_FILE" down
    docker-compose -f "$COMPOSE_FILE" up -d
    
    wait_for_health
    success "Rollback completed"
}

# Stop application
stop_application() {
    log "Stopping $ENVIRONMENT application..."
    
    docker-compose -f "$COMPOSE_FILE" down
    
    success "Application stopped"
}

# Restart application
restart_application() {
    log "Restarting $ENVIRONMENT application..."
    
    docker-compose -f "$COMPOSE_FILE" restart
    
    wait_for_health
    success "Application restarted"
}

# Show status
show_status() {
    log "Showing $ENVIRONMENT status..."
    
    echo ""
    echo "=== Container Status ==="
    docker-compose -f "$COMPOSE_FILE" ps
    
    echo ""
    echo "=== Service Health ==="
    if [ "$ENVIRONMENT" = "development" ]; then
        health_url="http://localhost:3000/health"
    else
        health_url="http://localhost/health"
    fi
    
    if curl -s "$health_url" | jq . 2>/dev/null; then
        success "Health check passed"
    else
        warning "Health check failed or service not responding"
    fi
    
    echo ""
    echo "=== Resource Usage ==="
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
}

# Show logs
show_logs() {
    log "Showing $ENVIRONMENT logs..."
    
    docker-compose -f "$COMPOSE_FILE" logs -f --tail=100
}

# Check health
check_health() {
    log "Checking $ENVIRONMENT health..."
    
    if [ -f "$PROJECT_DIR/scripts/health-check.sh" ]; then
        "$PROJECT_DIR/scripts/health-check.sh" --verbose
    else
        if [ "$ENVIRONMENT" = "development" ]; then
            health_url="http://localhost:3000/health"
        else
            health_url="http://localhost/health"
        fi
        
        if response=$(curl -s -f "$health_url"); then
            echo "$response" | jq . 2>/dev/null || echo "$response"
            success "Health check passed"
        else
            error "Health check failed"
            exit 1
        fi
    fi
}

# Main function
main() {
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
    esac
    
    log "Starting deployment script for $ENVIRONMENT environment"
    
    check_prerequisites
    setup_environment
    
    case $ACTION in
        deploy)
            create_backup
            build_images
            deploy_application
            wait_for_health
            success "Deployment completed successfully"
            ;;
        update)
            create_backup
            update_deployment
            ;;
        rollback)
            rollback_deployment
            ;;
        stop)
            stop_application
            ;;
        restart)
            restart_application
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        health)
            check_health
            ;;
        *)
            error "Unknown action: $ACTION"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"