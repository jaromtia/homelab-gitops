#!/bin/bash
# Cloudflare Tunnel Validation Script
# This script validates the tunnel configuration and tests connectivity

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/config/cloudflared/config.yml"
CREDENTIALS_FILE="$PROJECT_ROOT/config/cloudflared/credentials.json"
ENV_FILE="$PROJECT_ROOT/.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() { echo -e "${BLUE}[$(date '+%H:%M:%S')] $1${NC}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
error() { echo -e "${RED}✗ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

# Load environment variables
load_env() {
    if [ -f "$ENV_FILE" ]; then
        set -a
        source "$ENV_FILE"
        set +a
        success "Environment variables loaded"
    else
        warning ".env file not found"
        return 1
    fi
}

# Check if Docker is running
check_docker() {
    log "Checking Docker status..."
    if ! docker info > /dev/null 2>&1; then
        error "Docker is not running or not accessible"
        return 1
    fi
    success "Docker is running"
}

# Check if cloudflared CLI is available
check_cloudflared_cli() {
    log "Checking cloudflared CLI..."
    if command -v cloudflared > /dev/null 2>&1; then
        local version=$(cloudflared --version 2>&1 | head -1)
        success "cloudflared CLI available: $version"
    else
        warning "cloudflared CLI not found (optional for validation)"
    fi
}

# Validate configuration files
validate_config_files() {
    log "Validating configuration files..."
    
    # Check config.yml
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Configuration file not found: $CONFIG_FILE"
        return 1
    fi
    success "Configuration file exists"
    
    # Check for placeholder values
    if grep -q "YOUR_TUNNEL_ID" "$CONFIG_FILE"; then
        warning "Configuration contains placeholder tunnel ID"
    else
        success "Tunnel ID configured"
    fi
    
    # Check credentials file
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        warning "Credentials file not found: $CREDENTIALS_FILE"
        echo "  This is normal if using tunnel tokens instead of credentials"
    else
        success "Credentials file exists"
        
        # Validate JSON format
        if python3 -m json.tool "$CREDENTIALS_FILE" > /dev/null 2>&1; then
            success "Credentials file is valid JSON"
        else
            error "Credentials file contains invalid JSON"
            return 1
        fi
    fi
}

# Validate environment configuration
validate_environment() {
    log "Validating environment configuration..."
    
    if [ -z "$DOMAIN" ]; then
        error "DOMAIN environment variable not set"
        return 1
    fi
    success "Domain configured: $DOMAIN"
    
    # Check domain format
    if [[ "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        success "Domain format is valid"
    else
        warning "Domain format may be invalid: $DOMAIN"
    fi
}

# Test Docker Compose configuration
test_docker_compose() {
    log "Testing Docker Compose configuration..."
    
    cd "$PROJECT_ROOT"
    
    # Validate compose file
    if docker-compose config > /dev/null 2>&1; then
        success "Docker Compose configuration is valid"
    else
        error "Docker Compose configuration is invalid"
        return 1
    fi
    
    # Check if cloudflared service is defined
    if docker-compose config | grep -q "cloudflared:"; then
        success "Cloudflared service is defined"
    else
        error "Cloudflared service not found in docker-compose.yml"
        return 1
    fi
}

# Test tunnel configuration syntax
test_tunnel_config() {
    log "Testing tunnel configuration syntax..."
    
    if command -v cloudflared > /dev/null 2>&1; then
        if cloudflared tunnel ingress validate "$CONFIG_FILE" > /dev/null 2>&1; then
            success "Tunnel configuration syntax is valid"
        else
            error "Tunnel configuration syntax is invalid"
            return 1
        fi
    else
        warning "Cannot validate tunnel syntax (cloudflared CLI not available)"
    fi
}

# Check network connectivity
test_network_connectivity() {
    log "Testing network connectivity..."
    
    # Test internet connectivity
    if curl -s --max-time 10 https://www.cloudflare.com > /dev/null; then
        success "Internet connectivity available"
    else
        error "No internet connectivity"
        return 1
    fi
    
    # Test Cloudflare API connectivity
    if curl -s --max-time 10 https://api.cloudflare.com/client/v4/user/tokens/verify > /dev/null; then
        success "Cloudflare API is accessible"
    else
        warning "Cloudflare API may not be accessible"
    fi
}

# Test Docker services
test_docker_services() {
    log "Testing Docker services..."
    
    cd "$PROJECT_ROOT"
    
    # Check if services are running
    local running_services=$(docker-compose ps --services --filter "status=running" 2>/dev/null | wc -l)
    
    if [ "$running_services" -gt 0 ]; then
        success "$running_services Docker services are running"
        
        # Check specific services that cloudflared depends on
        local required_services=("dashy" "grafana" "prometheus" "portainer")
        for service in "${required_services[@]}"; do
            if docker-compose ps "$service" 2>/dev/null | grep -q "Up"; then
                success "$service is running"
            else
                warning "$service is not running (cloudflared dependency)"
            fi
        done
    else
        warning "No Docker services are currently running"
    fi
}

# Test cloudflared container if running
test_cloudflared_container() {
    log "Testing cloudflared container..."
    
    if docker ps --format "{{.Names}}" | grep -q "^cloudflared$"; then
        success "Cloudflared container is running"
        
        # Test health check
        local health_status=$(docker inspect cloudflared --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
        case "$health_status" in
            "healthy")
                success "Cloudflared container is healthy"
                ;;
            "unhealthy")
                error "Cloudflared container is unhealthy"
                ;;
            "starting")
                warning "Cloudflared container is starting"
                ;;
            *)
                warning "Cloudflared container health status unknown"
                ;;
        esac
        
        # Test metrics endpoint
        if docker exec cloudflared wget -qO- http://localhost:8080/metrics > /dev/null 2>&1; then
            success "Metrics endpoint is accessible"
        else
            warning "Metrics endpoint is not accessible"
        fi
        
    else
        warning "Cloudflared container is not running"
    fi
}

# Test DNS resolution
test_dns_resolution() {
    log "Testing DNS resolution..."
    
    if [ -n "$DOMAIN" ]; then
        local test_domains=("$DOMAIN" "dashboard.$DOMAIN" "grafana.$DOMAIN")
        
        for domain in "${test_domains[@]}"; do
            if nslookup "$domain" > /dev/null 2>&1; then
                success "$domain resolves"
            else
                warning "$domain does not resolve (DNS may not be configured yet)"
            fi
        done
    else
        warning "Cannot test DNS resolution (DOMAIN not set)"
    fi
}

# Generate summary report
generate_summary() {
    echo
    echo "=================================="
    echo "TUNNEL VALIDATION SUMMARY"
    echo "=================================="
    echo
    
    if [ -n "$DOMAIN" ]; then
        echo "Domain: $DOMAIN"
        echo
        echo "Expected service URLs:"
        echo "  • Main Dashboard: https://$DOMAIN"
        echo "  • Grafana: https://grafana.$DOMAIN"
        echo "  • Prometheus: https://prometheus.$DOMAIN"
        echo "  • Portainer: https://portainer.$DOMAIN"
        echo "  • File Browser: https://files.$DOMAIN"
        echo "  • Bookmarks: https://bookmarks.$DOMAIN"
        echo "  • Budget: https://budget.$DOMAIN"
        echo "  • Backup: https://backup.$DOMAIN"
        echo
    fi
    
    echo "Next steps:"
    echo "1. If validation passed, start services: docker-compose up -d"
    echo "2. Monitor tunnel status: docker logs -f cloudflared"
    echo "3. Test service access through your configured domain"
    echo "4. Check tunnel health: docker exec cloudflared /etc/cloudflared/healthcheck.sh"
}

# Main validation function
main() {
    echo "Cloudflare Tunnel Configuration Validation"
    echo "=========================================="
    echo
    
    local exit_code=0
    
    # Run all validation tests
    load_env || exit_code=1
    check_docker || exit_code=1
    check_cloudflared_cli
    validate_config_files || exit_code=1
    validate_environment || exit_code=1
    test_docker_compose || exit_code=1
    test_tunnel_config || exit_code=1
    test_network_connectivity || exit_code=1
    test_docker_services
    test_cloudflared_container
    test_dns_resolution
    
    generate_summary
    
    if [ $exit_code -eq 0 ]; then
        echo
        success "Validation completed successfully!"
    else
        echo
        error "Validation completed with errors. Please fix the issues above."
    fi
    
    exit $exit_code
}

# Execute main function
main "$@"