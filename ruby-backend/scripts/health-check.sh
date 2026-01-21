#!/bin/bash

# Health check script for Spotik Ruby Backend
# This script performs comprehensive health checks for container orchestration

set -e

# Configuration
HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-http://localhost:3000/health}"
TIMEOUT="${HEALTH_TIMEOUT:-10}"
RETRIES="${HEALTH_RETRIES:-3}"
VERBOSE="${HEALTH_VERBOSE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    if [ "$VERBOSE" = "true" ]; then
        echo -e "${2:-$NC}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
    fi
}

# Error function
error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

# Success function
success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

# Warning function
warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if curl is available
check_curl() {
    if ! command -v curl >/dev/null 2>&1; then
        error "curl is not available"
        return 1
    fi
    return 0
}

# Check if the application is responding
check_application() {
    local attempt=1
    
    log "Checking application health at $HEALTH_ENDPOINT" "$YELLOW"
    
    while [ $attempt -le $RETRIES ]; do
        log "Attempt $attempt/$RETRIES"
        
        if response=$(curl -s -f --max-time $TIMEOUT "$HEALTH_ENDPOINT" 2>/dev/null); then
            log "Application responded successfully"
            
            # Parse JSON response if possible
            if command -v jq >/dev/null 2>&1; then
                status=$(echo "$response" | jq -r '.status // "unknown"')
                message=$(echo "$response" | jq -r '.message // "No message"')
                
                log "Status: $status"
                log "Message: $message"
                
                if [ "$status" = "healthy" ] || [ "$status" = "ok" ]; then
                    success "Application is healthy"
                    return 0
                else
                    warning "Application status: $status - $message"
                fi
            else
                # Basic check without jq
                if echo "$response" | grep -q '"status".*"healthy"' || echo "$response" | grep -q '"status".*"ok"'; then
                    success "Application is healthy"
                    return 0
                fi
            fi
        else
            log "Application health check failed (attempt $attempt)"
        fi
        
        if [ $attempt -lt $RETRIES ]; then
            log "Waiting 2 seconds before retry..."
            sleep 2
        fi
        
        attempt=$((attempt + 1))
    done
    
    error "Application health check failed after $RETRIES attempts"
    return 1
}

# Check database connectivity (if endpoint available)
check_database() {
    local db_endpoint="${HEALTH_ENDPOINT%/health}/health/database"
    
    log "Checking database health at $db_endpoint" "$YELLOW"
    
    if response=$(curl -s -f --max-time $TIMEOUT "$db_endpoint" 2>/dev/null); then
        if command -v jq >/dev/null 2>&1; then
            status=$(echo "$response" | jq -r '.database.status // "unknown"')
            if [ "$status" = "connected" ] || [ "$status" = "healthy" ]; then
                success "Database is healthy"
                return 0
            else
                warning "Database status: $status"
                return 1
            fi
        else
            if echo "$response" | grep -q '"status".*"connected"' || echo "$response" | grep -q '"status".*"healthy"'; then
                success "Database is healthy"
                return 0
            fi
        fi
    fi
    
    warning "Database health check failed or not available"
    return 1
}

# Check WebSocket support (if endpoint available)
check_websocket() {
    local ws_endpoint="${HEALTH_ENDPOINT%/health}/api/websocket/status"
    
    log "Checking WebSocket support at $ws_endpoint" "$YELLOW"
    
    if response=$(curl -s -f --max-time $TIMEOUT "$ws_endpoint" 2>/dev/null); then
        if command -v jq >/dev/null 2>&1; then
            enabled=$(echo "$response" | jq -r '.websocket_enabled // false')
            if [ "$enabled" = "true" ]; then
                success "WebSocket support is enabled"
                return 0
            else
                warning "WebSocket support is disabled"
                return 1
            fi
        else
            if echo "$response" | grep -q '"websocket_enabled".*true'; then
                success "WebSocket support is enabled"
                return 0
            fi
        fi
    fi
    
    warning "WebSocket status check failed or not available"
    return 1
}

# Check disk space
check_disk_space() {
    log "Checking disk space" "$YELLOW"
    
    # Check available disk space (require at least 100MB free)
    available_kb=$(df /app 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    available_mb=$((available_kb / 1024))
    
    if [ "$available_mb" -gt 100 ]; then
        success "Disk space is sufficient (${available_mb}MB available)"
        return 0
    else
        warning "Low disk space: ${available_mb}MB available"
        return 1
    fi
}

# Check memory usage
check_memory() {
    log "Checking memory usage" "$YELLOW"
    
    if [ -f /proc/meminfo ]; then
        mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}' || grep MemFree /proc/meminfo | awk '{print $2}')
        
        if [ "$mem_total" -gt 0 ] && [ "$mem_available" -gt 0 ]; then
            mem_usage_percent=$(( (mem_total - mem_available) * 100 / mem_total ))
            
            if [ "$mem_usage_percent" -lt 90 ]; then
                success "Memory usage is acceptable (${mem_usage_percent}%)"
                return 0
            else
                warning "High memory usage: ${mem_usage_percent}%"
                return 1
            fi
        fi
    fi
    
    warning "Memory check failed or not available"
    return 1
}

# Check process
check_process() {
    log "Checking Ruby process" "$YELLOW"
    
    if pgrep -f "ruby.*server.rb" >/dev/null 2>&1; then
        success "Ruby server process is running"
        return 0
    else
        error "Ruby server process not found"
        return 1
    fi
}

# Main health check function
main() {
    local exit_code=0
    local checks_passed=0
    local checks_total=0
    
    log "Starting health check..." "$GREEN"
    
    # Essential checks (must pass)
    essential_checks=(
        "check_curl"
        "check_application"
        "check_process"
    )
    
    # Optional checks (warnings only)
    optional_checks=(
        "check_database"
        "check_websocket"
        "check_disk_space"
        "check_memory"
    )
    
    # Run essential checks
    for check in "${essential_checks[@]}"; do
        checks_total=$((checks_total + 1))
        if $check; then
            checks_passed=$((checks_passed + 1))
        else
            exit_code=1
        fi
    done
    
    # Run optional checks (don't affect exit code)
    for check in "${optional_checks[@]}"; do
        checks_total=$((checks_total + 1))
        if $check; then
            checks_passed=$((checks_passed + 1))
        fi
    done
    
    # Summary
    log "Health check completed: $checks_passed/$checks_total checks passed" "$GREEN"
    
    if [ $exit_code -eq 0 ]; then
        success "Health check PASSED"
    else
        error "Health check FAILED"
    fi
    
    return $exit_code
}

# Handle command line arguments
case "${1:-}" in
    --verbose|-v)
        HEALTH_VERBOSE=true
        shift
        ;;
    --help|-h)
        echo "Usage: $0 [--verbose|-v] [--help|-h]"
        echo ""
        echo "Environment variables:"
        echo "  HEALTH_ENDPOINT   - Health check endpoint (default: http://localhost:3000/health)"
        echo "  HEALTH_TIMEOUT    - Request timeout in seconds (default: 10)"
        echo "  HEALTH_RETRIES    - Number of retries (default: 3)"
        echo "  HEALTH_VERBOSE    - Enable verbose output (default: false)"
        exit 0
        ;;
esac

# Run main function
main "$@"