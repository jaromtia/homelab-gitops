#!/bin/bash

# SSL Certificate Health Check and Monitoring Script
# This script monitors SSL certificate expiration and handles renewal errors

set -euo pipefail

# Configuration
DOMAIN="${DOMAIN:-localhost}"
ACME_JSON_PATH="${ACME_JSON_PATH:-./data/traefik/letsencrypt/acme.json}"
LOG_FILE="${LOG_FILE:-./logs/ssl-health-check.log}"
ALERT_DAYS="${ALERT_DAYS:-30}"
CRITICAL_DAYS="${CRITICAL_DAYS:-7}"
TRAEFIK_CONTAINER="${TRAEFIK_CONTAINER:-traefik}"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Check if required tools are available
check_dependencies() {
    local deps=("docker" "openssl" "jq" "curl")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error_exit "$dep is required but not installed"
        fi
    done
}

# Check Traefik container status
check_traefik_status() {
    log "Checking Traefik container status..."
    
    if ! docker ps --filter "name=$TRAEFIK_CONTAINER" --filter "status=running" | grep -q "$TRAEFIK_CONTAINER"; then
        error_exit "Traefik container is not running"
    fi
    
    # Check Traefik health endpoint
    if ! curl -sf "http://localhost:8080/ping" > /dev/null; then
        error_exit "Traefik health check failed"
    fi
    
    log "✓ Traefik is running and healthy"
}

# Check SSL certificate expiration
check_certificate_expiration() {
    local domain="$1"
    log "Checking SSL certificate for $domain..."
    
    # Get certificate expiration date
    local cert_info
    cert_info=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
    
    if [ -z "$cert_info" ]; then
        log "WARNING: Could not retrieve certificate information for $domain"
        return 1
    fi
    
    local not_after
    not_after=$(echo "$cert_info" | grep "notAfter" | cut -d= -f2)
    
    # Convert to epoch time
    local exp_epoch
    exp_epoch=$(date -d "$not_after" +%s)
    local current_epoch
    current_epoch=$(date +%s)
    
    # Calculate days until expiration
    local days_until_exp
    days_until_exp=$(( (exp_epoch - current_epoch) / 86400 ))
    
    if [ "$days_until_exp" -lt "$CRITICAL_DAYS" ]; then
        log "${RED}CRITICAL: Certificate for $domain expires in $days_until_exp days${NC}"
        return 2
    elif [ "$days_until_exp" -lt "$ALERT_DAYS" ]; then
        log "${YELLOW}WARNING: Certificate for $domain expires in $days_until_exp days${NC}"
        return 1
    else
        log "${GREEN}✓ Certificate for $domain is valid for $days_until_exp days${NC}"
        return 0
    fi
}

# Check ACME JSON file for certificate information
check_acme_certificates() {
    if [ ! -f "$ACME_JSON_PATH" ]; then
        log "WARNING: ACME JSON file not found at $ACME_JSON_PATH"
        return 1
    fi
    
    log "Checking ACME certificate storage..."
    
    # Parse ACME JSON for certificate information
    local cert_count
    cert_count=$(jq -r '.letsencrypt.Certificates | length' "$ACME_JSON_PATH" 2>/dev/null || echo "0")
    
    if [ "$cert_count" -eq 0 ]; then
        log "WARNING: No certificates found in ACME storage"
        return 1
    fi
    
    log "✓ Found $cert_count certificates in ACME storage"
    
    # List certificate domains and expiration
    jq -r '.letsencrypt.Certificates[] | "\(.domain.main) expires: \(.certificate | @base64d | split("\n") | map(select(startswith("-----BEGIN CERTIFICATE-----"))) | .[0] | @base64 | @base64d)"' "$ACME_JSON_PATH" 2>/dev/null | while read -r line; do
        log "  $line"
    done
}

# Force certificate renewal with enhanced error handling
force_renewal() {
    local domain="$1"
    log "Forcing certificate renewal for $domain..."
    
    # Validate domain accessibility before renewal
    if ! validate_domain_accessibility "$domain"; then
        log "WARNING: Domain $domain is not accessible, renewal may fail"
    fi
    
    # Check if ACME storage exists and is writable
    if [ -f "$ACME_JSON_PATH" ]; then
        if [ ! -w "$ACME_JSON_PATH" ]; then
            error_exit "ACME JSON file is not writable: $ACME_JSON_PATH"
        fi
        
        log "Backing up ACME JSON file..."
        cp "$ACME_JSON_PATH" "${ACME_JSON_PATH}.backup.$(date +%s)"
        
        # Validate JSON structure before modification
        if ! jq empty "$ACME_JSON_PATH" 2>/dev/null; then
            log "WARNING: ACME JSON file appears corrupted, attempting repair..."
            local acme_email="${ACME_EMAIL:-admin@${DOMAIN}}"
            echo '{"letsencrypt":{"Account":{"Email":"'$acme_email'","Registration":{"body":{"status":"valid","contact":["mailto:'$acme_email'"]},"uri":"https://acme-v02.api.letsencrypt.org/acme/acct/123456789"}},"Certificates":[],"HTTPChallenges":{},"TLSChallenges":{}}}' > "$ACME_JSON_PATH"
        fi
        
        # Remove certificate entry (this will trigger renewal)
        local temp_file="${ACME_JSON_PATH}.tmp"
        if jq "del(.letsencrypt.Certificates[] | select(.domain.main == \"$domain\"))" "$ACME_JSON_PATH" > "$temp_file"; then
            mv "$temp_file" "$ACME_JSON_PATH"
            chmod 600 "$ACME_JSON_PATH"
        else
            log "ERROR: Failed to modify ACME JSON file"
            rm -f "$temp_file"
            return 1
        fi
    else
        log "ACME JSON file not found, creating new one..."
        mkdir -p "$(dirname "$ACME_JSON_PATH")"
        local acme_email="${ACME_EMAIL:-admin@${DOMAIN}}"
        echo '{"letsencrypt":{"Account":{"Email":"'$acme_email'","Registration":{"body":{"status":"valid","contact":["mailto:'$acme_email'"]},"uri":"https://acme-v02.api.letsencrypt.org/acme/acct/123456789"}},"Certificates":[],"HTTPChallenges":{},"TLSChallenges":{}}}' > "$ACME_JSON_PATH"
        chmod 600 "$ACME_JSON_PATH"
    fi
    
    # Check Traefik container health before restart
    if ! docker ps --filter "name=$TRAEFIK_CONTAINER" --filter "status=running" | grep -q "$TRAEFIK_CONTAINER"; then
        log "Traefik container is not running, starting it..."
        if ! docker start "$TRAEFIK_CONTAINER"; then
            error_exit "Failed to start Traefik container"
        fi
    fi
    
    # Restart Traefik to trigger renewal
    log "Restarting Traefik container to trigger certificate renewal..."
    if ! docker restart "$TRAEFIK_CONTAINER"; then
        error_exit "Failed to restart Traefik container"
    fi
    
    # Wait for container to be healthy with exponential backoff
    local retries=30
    local wait_time=2
    while [ $retries -gt 0 ]; do
        if docker ps --filter "name=$TRAEFIK_CONTAINER" --filter "status=running" | grep -q "$TRAEFIK_CONTAINER"; then
            if curl -sf "http://localhost:8080/ping" > /dev/null 2>&1; then
                log "✓ Traefik restarted successfully"
                
                # Additional validation: check if Traefik can access ACME storage
                if docker exec "$TRAEFIK_CONTAINER" ls /letsencrypt/acme.json > /dev/null 2>&1; then
                    log "✓ ACME storage accessible from container"
                    return 0
                else
                    log "WARNING: ACME storage not accessible from container"
                fi
                return 0
            fi
        fi
        
        log "Waiting for Traefik to become healthy... (attempt $((31-retries))/30)"
        sleep $wait_time
        
        # Exponential backoff, max 10 seconds
        if [ $wait_time -lt 10 ]; then
            wait_time=$((wait_time * 2))
        fi
        
        ((retries--))
    done
    
    # If restart failed, try to diagnose the issue
    log "Traefik restart failed, attempting diagnosis..."
    docker logs "$TRAEFIK_CONTAINER" --tail 50 | log
    
    error_exit "Traefik failed to restart properly after certificate renewal attempt"
}

# Validate domain accessibility
validate_domain_accessibility() {
    local domain="$1"
    
    # Check DNS resolution
    if ! nslookup "$domain" > /dev/null 2>&1; then
        log "WARNING: DNS resolution failed for $domain"
        return 1
    fi
    
    # Check if domain points to this server (basic check)
    local domain_ip
    domain_ip=$(dig +short "$domain" | head -n1)
    if [ -z "$domain_ip" ]; then
        log "WARNING: Could not resolve IP for $domain"
        return 1
    fi
    
    # Check if port 80 is reachable (for ACME HTTP challenge)
    if ! timeout 10 bash -c "</dev/tcp/$domain/80" 2>/dev/null; then
        log "WARNING: Port 80 not reachable on $domain"
        return 1
    fi
    
    return 0
}

# Monitor certificate renewal process
monitor_renewal() {
    local domain="$1"
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    log "Monitoring certificate renewal for $domain..."
    
    while [ $wait_time -lt $max_wait ]; do
        if check_certificate_expiration "$domain" > /dev/null 2>&1; then
            log "✓ Certificate renewal completed successfully"
            return 0
        fi
        
        sleep 10
        wait_time=$((wait_time + 10))
        log "Waiting for renewal... ($wait_time/${max_wait}s)"
    done
    
    log "WARNING: Certificate renewal monitoring timed out"
    return 1
}

# Main health check function
main_health_check() {
    log "Starting SSL health check..."
    
    check_dependencies
    check_traefik_status
    
    # Check main domain certificate
    local cert_status=0
    check_certificate_expiration "$DOMAIN" || cert_status=$?
    
    # Check ACME storage
    check_acme_certificates
    
    # If certificate is critical or failed, attempt renewal
    if [ $cert_status -eq 2 ]; then
        log "Attempting automatic certificate renewal..."
        force_renewal "$DOMAIN"
        monitor_renewal "$DOMAIN"
    fi
    
    log "SSL health check completed"
}

# Script usage
usage() {
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  check          Run health check (default)"
    echo "  renew DOMAIN   Force certificate renewal for domain"
    echo "  monitor        Continuous monitoring mode"
    echo ""
    echo "Options:"
    echo "  -d DOMAIN      Domain to check (default: \$DOMAIN)"
    echo "  -a DAYS        Alert threshold in days (default: 30)"
    echo "  -c DAYS        Critical threshold in days (default: 7)"
    echo "  -l LOGFILE     Log file path"
    echo "  -h             Show this help"
}

# Parse command line arguments
while getopts "d:a:c:l:h" opt; do
    case $opt in
        d) DOMAIN="$OPTARG" ;;
        a) ALERT_DAYS="$OPTARG" ;;
        c) CRITICAL_DAYS="$OPTARG" ;;
        l) LOG_FILE="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

shift $((OPTIND-1))

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Execute command
case "${1:-check}" in
    check)
        main_health_check
        ;;
    renew)
        if [ -z "${2:-}" ]; then
            error_exit "Domain required for renewal command"
        fi
        force_renewal "$2"
        monitor_renewal "$2"
        ;;
    monitor)
        log "Starting continuous monitoring mode..."
        while true; do
            main_health_check
            sleep 3600  # Check every hour
        done
        ;;
    *)
        usage
        exit 1
        ;;
esac