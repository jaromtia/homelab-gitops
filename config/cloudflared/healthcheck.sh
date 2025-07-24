#!/bin/sh
# Cloudflare Tunnel Health Check Script
# This script performs comprehensive health checks for the cloudflared tunnel service
# including process status, metrics endpoint, configuration validation, and tunnel connectivity

set -e

# Configuration
METRICS_URL="http://localhost:8080/metrics"
CONFIG_FILE="/etc/cloudflared/config.yml"
CREDENTIALS_FILE="/etc/cloudflared/credentials.json"
LOG_FILE="/var/log/cloudflared.log"
TIMEOUT=10

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [HEALTHCHECK] $1"
}

# Error function
error() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

# Success function
success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

# Warning function
warning() {
    log "${YELLOW}WARNING: $1${NC}"
}

# Check if cloudflared process is running
check_process() {
    log "Checking cloudflared process..."
    if ! pgrep -f "cloudflared.*tunnel.*run" > /dev/null 2>&1; then
        error "cloudflared process is not running"
    fi
    success "cloudflared process is running"
}

# Check metrics endpoint availability
check_metrics() {
    log "Checking metrics endpoint..."
    if ! wget --quiet --tries=1 --timeout=$TIMEOUT --spider "$METRICS_URL" 2>/dev/null; then
        error "Metrics endpoint $METRICS_URL is not accessible"
    fi
    success "Metrics endpoint is accessible"
}

# Validate tunnel configuration
check_config() {
    log "Validating tunnel configuration..."
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Configuration file $CONFIG_FILE not found"
    fi
    
    if ! cloudflared tunnel ingress validate "$CONFIG_FILE" > /dev/null 2>&1; then
        error "Invalid tunnel configuration in $CONFIG_FILE"
    fi
    success "Tunnel configuration is valid"
}

# Check credentials file
check_credentials() {
    log "Checking credentials file..."
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        warning "Credentials file $CREDENTIALS_FILE not found (may be using token auth)"
        return 0
    fi
    
    # Check if credentials file is valid JSON
    if ! python3 -m json.tool "$CREDENTIALS_FILE" > /dev/null 2>&1; then
        error "Invalid JSON in credentials file $CREDENTIALS_FILE"
    fi
    success "Credentials file is valid"
}

# Check tunnel connectivity (if tunnel ID is configured)
check_tunnel_connectivity() {
    log "Checking tunnel connectivity..."
    
    # Extract tunnel ID from config
    if [ -f "$CONFIG_FILE" ] && grep -q "tunnel:" "$CONFIG_FILE"; then
        TUNNEL_ID=$(grep "tunnel:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
        
        # Skip check if using placeholder
        if [ "$TUNNEL_ID" = "YOUR_TUNNEL_ID" ]; then
            warning "Tunnel ID not configured (using placeholder)"
            return 0
        fi
        
        # Check tunnel info
        if ! cloudflared tunnel info "$TUNNEL_ID" > /dev/null 2>&1; then
            error "Cannot retrieve tunnel info for tunnel ID: $TUNNEL_ID"
        fi
        success "Tunnel connectivity verified for tunnel ID: $TUNNEL_ID"
    else
        warning "No tunnel ID found in configuration"
    fi
}

# Check log file for recent errors
check_logs() {
    log "Checking recent logs for errors..."
    
    if [ ! -f "$LOG_FILE" ]; then
        warning "Log file $LOG_FILE not found"
        return 0
    fi
    
    # Check for recent errors (last 5 minutes)
    RECENT_ERRORS=$(tail -n 100 "$LOG_FILE" | grep -i "error\|fatal\|panic" | wc -l)
    
    if [ "$RECENT_ERRORS" -gt 5 ]; then
        warning "Found $RECENT_ERRORS recent errors in logs"
        # Show last few errors
        tail -n 20 "$LOG_FILE" | grep -i "error\|fatal\|panic" | tail -n 3
    else
        success "No significant errors found in recent logs"
    fi
}

# Check network connectivity to Cloudflare edge
check_edge_connectivity() {
    log "Checking connectivity to Cloudflare edge..."
    
    # Test connectivity to Cloudflare's edge network
    if ! wget --quiet --tries=1 --timeout=$TIMEOUT --spider "https://www.cloudflare.com" 2>/dev/null; then
        error "Cannot reach Cloudflare edge network"
    fi
    success "Connectivity to Cloudflare edge verified"
}

# Check metrics for tunnel health indicators
check_tunnel_metrics() {
    log "Checking tunnel health metrics..."
    
    # Fetch metrics and check for key indicators
    if ! METRICS=$(wget --quiet --tries=1 --timeout=$TIMEOUT -O - "$METRICS_URL" 2>/dev/null); then
        error "Cannot fetch metrics from $METRICS_URL"
    fi
    
    # Check for active connections
    ACTIVE_CONNECTIONS=$(echo "$METRICS" | grep -c "cloudflared_tunnel_active_streams" || echo "0")
    if [ "$ACTIVE_CONNECTIONS" -eq 0 ]; then
        warning "No active tunnel connections found in metrics"
    else
        success "Found $ACTIVE_CONNECTIONS active tunnel connections"
    fi
    
    # Check for recent requests
    TOTAL_REQUESTS=$(echo "$METRICS" | grep "cloudflared_tunnel_total_requests" | head -1 | awk '{print $2}' || echo "0")
    success "Total tunnel requests: $TOTAL_REQUESTS"
}

# Main health check execution
main() {
    log "Starting comprehensive cloudflared health check..."
    
    # Run all health checks
    check_process
    check_config
    check_credentials
    check_metrics
    check_tunnel_metrics
    check_edge_connectivity
    check_tunnel_connectivity
    check_logs
    
    success "All health checks passed successfully"
    log "Health check completed"
}

# Execute main function
main "$@"