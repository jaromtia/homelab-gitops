#!/bin/bash

# SSL Certificate Renewal Error Handler
# This script provides advanced error handling and recovery for SSL certificate renewal failures

set -euo pipefail

# Configuration
DOMAIN="${DOMAIN:-localhost}"
ACME_JSON_PATH="${ACME_JSON_PATH:-./data/traefik/letsencrypt/acme.json}"
LOG_FILE="${LOG_FILE:-./logs/ssl-renewal-handler.log}"
TRAEFIK_CONTAINER="${TRAEFIK_CONTAINER:-traefik}"
BACKUP_DIR="${BACKUP_DIR:-./backups/ssl}"
MAX_RETRY_ATTEMPTS="${MAX_RETRY_ATTEMPTS:-3}"
RETRY_DELAY="${RETRY_DELAY:-300}"  # 5 minutes

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function with levels
log() {
    local level="${1:-INFO}"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$1"; }
log_warn() { log "WARN" "$1"; }
log_error() { log "ERROR" "$1"; }
log_debug() { log "DEBUG" "$1"; }

# Error handling with cleanup
error_exit() {
    log_error "$1"
    cleanup_temp_files
    exit 1
}

# Cleanup temporary files
cleanup_temp_files() {
    rm -f /tmp/acme_*.json /tmp/traefik_*.log
}

# Create backup directory
ensure_backup_dir() {
    mkdir -p "$BACKUP_DIR"
    if [ ! -w "$BACKUP_DIR" ]; then
        error_exit "Backup directory is not writable: $BACKUP_DIR"
    fi
}

# Backup ACME JSON with rotation
backup_acme_json() {
    ensure_backup_dir
    
    if [ -f "$ACME_JSON_PATH" ]; then
        local backup_file="$BACKUP_DIR/acme.json.$(date +%Y%m%d_%H%M%S)"
        cp "$ACME_JSON_PATH" "$backup_file"
        chmod 600 "$backup_file"
        log_info "ACME JSON backed up to: $backup_file"
        
        # Rotate backups (keep last 10)
        find "$BACKUP_DIR" -name "acme.json.*" -type f | sort -r | tail -n +11 | xargs -r rm
    fi
}

# Validate ACME JSON structure
validate_acme_json() {
    local json_file="$1"
    
    if [ ! -f "$json_file" ]; then
        log_warn "ACME JSON file does not exist: $json_file"
        return 1
    fi
    
    # Check if file is readable and has correct permissions
    if [ ! -r "$json_file" ]; then
        log_error "ACME JSON file is not readable: $json_file"
        return 1
    fi
    
    # Validate JSON structure
    if ! jq empty "$json_file" 2>/dev/null; then
        log_error "ACME JSON file has invalid JSON structure"
        return 1
    fi
    
    # Check for required fields
    if ! jq -e '.letsencrypt' "$json_file" >/dev/null 2>&1; then
        log_error "ACME JSON file missing letsencrypt section"
        return 1
    fi
    
    log_info "ACME JSON file validation passed"
    return 0
}

# Repair corrupted ACME JSON
repair_acme_json() {
    local json_file="$1"
    local acme_email="${ACME_EMAIL:-admin@${DOMAIN}}"
    
    log_warn "Attempting to repair corrupted ACME JSON file"
    
    # Create backup before repair
    if [ -f "$json_file" ]; then
        cp "$json_file" "${json_file}.corrupted.$(date +%s)"
    fi
    
    # Create minimal valid ACME JSON structure
    cat > "$json_file" << EOF
{
  "letsencrypt": {
    "Account": {
      "Email": "$acme_email",
      "Registration": {
        "body": {
          "status": "valid",
          "contact": ["mailto:$acme_email"]
        },
        "uri": "https://acme-v02.api.letsencrypt.org/acme/acct/placeholder"
      }
    },
    "Certificates": [],
    "HTTPChallenges": {},
    "TLSChallenges": {}
  }
}
EOF
    
    chmod 600 "$json_file"
    log_info "ACME JSON file repaired with minimal structure"
}

# Check Let's Encrypt rate limits
check_rate_limits() {
    local domain="$1"
    
    log_info "Checking Let's Encrypt rate limits for $domain..."
    
    # Check certificates issued in the last week
    local cert_count=0
    if [ -f "$ACME_JSON_PATH" ]; then
        # This is a simplified check - in production, you might want to query Let's Encrypt API
        cert_count=$(jq -r '.letsencrypt.Certificates | length' "$ACME_JSON_PATH" 2>/dev/null || echo "0")
    fi
    
    if [ "$cert_count" -gt 5 ]; then
        log_warn "Multiple certificates detected ($cert_count), potential rate limit concern"
        return 1
    fi
    
    log_info "Rate limit check passed"
    return 0
}

# Advanced certificate renewal with retry logic
advanced_certificate_renewal() {
    local domain="$1"
    local attempt=1
    
    log_info "Starting advanced certificate renewal for $domain"
    
    while [ $attempt -le $MAX_RETRY_ATTEMPTS ]; do
        log_info "Renewal attempt $attempt/$MAX_RETRY_ATTEMPTS"
        
        # Pre-renewal checks
        if ! check_rate_limits "$domain"; then
            log_warn "Rate limit check failed, waiting before retry..."
            sleep $RETRY_DELAY
            ((attempt++))
            continue
        fi
        
        # Backup current state
        backup_acme_json
        
        # Validate and repair ACME JSON if needed
        if ! validate_acme_json "$ACME_JSON_PATH"; then
            repair_acme_json "$ACME_JSON_PATH"
        fi
        
        # Attempt renewal
        if perform_renewal "$domain"; then
            log_info "Certificate renewal successful on attempt $attempt"
            return 0
        fi
        
        log_warn "Renewal attempt $attempt failed"
        
        if [ $attempt -lt $MAX_RETRY_ATTEMPTS ]; then
            log_info "Waiting ${RETRY_DELAY}s before next attempt..."
            sleep $RETRY_DELAY
        fi
        
        ((attempt++))
    done
    
    log_error "All renewal attempts failed for $domain"
    return 1
}

# Perform the actual renewal
perform_renewal() {
    local domain="$1"
    
    log_info "Performing certificate renewal for $domain"
    
    # Remove existing certificate to force renewal
    if [ -f "$ACME_JSON_PATH" ]; then
        local temp_file="/tmp/acme_temp_$(date +%s).json"
        if jq "del(.letsencrypt.Certificates[] | select(.domain.main == \"$domain\"))" "$ACME_JSON_PATH" > "$temp_file"; then
            mv "$temp_file" "$ACME_JSON_PATH"
            chmod 600 "$ACME_JSON_PATH"
            log_info "Removed existing certificate entry for $domain"
        else
            log_error "Failed to modify ACME JSON file"
            rm -f "$temp_file"
            return 1
        fi
    fi
    
    # Restart Traefik with health monitoring
    if ! restart_traefik_with_monitoring; then
        log_error "Traefik restart failed during renewal"
        return 1
    fi
    
    # Wait for certificate generation
    if wait_for_certificate_generation "$domain"; then
        log_info "Certificate generation completed successfully"
        return 0
    else
        log_error "Certificate generation failed or timed out"
        return 1
    fi
}

# Restart Traefik with comprehensive monitoring
restart_traefik_with_monitoring() {
    log_info "Restarting Traefik with monitoring..."
    
    # Check if container exists
    if ! docker ps -a --filter "name=$TRAEFIK_CONTAINER" | grep -q "$TRAEFIK_CONTAINER"; then
        log_error "Traefik container does not exist"
        return 1
    fi
    
    # Stop container gracefully
    log_info "Stopping Traefik container gracefully..."
    if ! docker stop "$TRAEFIK_CONTAINER" --time 30; then
        log_warn "Graceful stop failed, forcing stop..."
        docker kill "$TRAEFIK_CONTAINER" || true
    fi
    
    # Start container
    log_info "Starting Traefik container..."
    if ! docker start "$TRAEFIK_CONTAINER"; then
        log_error "Failed to start Traefik container"
        return 1
    fi
    
    # Monitor startup with detailed logging
    local retries=60  # 2 minutes with 2-second intervals
    local wait_time=2
    
    while [ $retries -gt 0 ]; do
        # Check container status
        if docker ps --filter "name=$TRAEFIK_CONTAINER" --filter "status=running" | grep -q "$TRAEFIK_CONTAINER"; then
            # Check health endpoint
            if curl -sf "http://localhost:8080/ping" >/dev/null 2>&1; then
                log_info "✓ Traefik is running and healthy"
                
                # Additional checks
                if docker exec "$TRAEFIK_CONTAINER" ls /letsencrypt/acme.json >/dev/null 2>&1; then
                    log_info "✓ ACME storage accessible"
                fi
                
                if curl -sf "http://localhost:8080/api/http/services" >/dev/null 2>&1; then
                    log_info "✓ API endpoint accessible"
                fi
                
                return 0
            fi
        fi
        
        # Log container status for debugging
        local container_status
        container_status=$(docker inspect "$TRAEFIK_CONTAINER" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
        log_debug "Container status: $container_status (waiting $((61-retries))/60)"
        
        sleep $wait_time
        ((retries--))
    done
    
    # If we get here, startup failed
    log_error "Traefik failed to start properly"
    
    # Collect diagnostic information
    log_error "Container logs (last 20 lines):"
    docker logs "$TRAEFIK_CONTAINER" --tail 20 2>&1 | while read -r line; do
        log_error "  $line"
    done
    
    return 1
}

# Wait for certificate generation with progress monitoring
wait_for_certificate_generation() {
    local domain="$1"
    local max_wait=600  # 10 minutes
    local check_interval=10
    local elapsed=0
    
    log_info "Waiting for certificate generation for $domain..."
    
    while [ $elapsed -lt $max_wait ]; do
        # Check if certificate exists in ACME JSON
        if [ -f "$ACME_JSON_PATH" ]; then
            local cert_count
            cert_count=$(jq -r ".letsencrypt.Certificates[] | select(.domain.main == \"$domain\") | length" "$ACME_JSON_PATH" 2>/dev/null || echo "0")
            
            if [ "$cert_count" != "0" ] && [ "$cert_count" != "null" ]; then
                log_info "Certificate found in ACME storage"
                
                # Verify certificate is actually working
                if verify_certificate_functionality "$domain"; then
                    log_info "Certificate verification successful"
                    return 0
                fi
            fi
        fi
        
        # Check Traefik logs for ACME activity
        if docker logs "$TRAEFIK_CONTAINER" --since "${check_interval}s" 2>&1 | grep -i "acme\|certificate" | tail -5 | while read -r line; do
            log_debug "ACME activity: $line"
        done
        
        log_info "Certificate generation in progress... (${elapsed}s/${max_wait}s)"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    log_error "Certificate generation timed out after ${max_wait}s"
    return 1
}

# Verify certificate functionality
verify_certificate_functionality() {
    local domain="$1"
    
    if [ "$domain" = "localhost" ]; then
        log_info "Skipping certificate verification for localhost"
        return 0
    fi
    
    log_info "Verifying certificate functionality for $domain"
    
    # Test HTTPS connection
    if echo | openssl s_client -servername "$domain" -connect "$domain:443" -verify_return_error >/dev/null 2>&1; then
        log_info "HTTPS connection successful"
        return 0
    else
        log_warn "HTTPS connection verification failed"
        return 1
    fi
}

# Main renewal handler
main() {
    local domain="${1:-$DOMAIN}"
    local action="${2:-renew}"
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log_info "Starting SSL renewal handler for $domain (action: $action)"
    
    case "$action" in
        "renew")
            if advanced_certificate_renewal "$domain"; then
                log_info "Certificate renewal completed successfully"
                exit 0
            else
                log_error "Certificate renewal failed"
                exit 1
            fi
            ;;
        "validate")
            if validate_acme_json "$ACME_JSON_PATH"; then
                log_info "ACME JSON validation passed"
                exit 0
            else
                log_error "ACME JSON validation failed"
                exit 1
            fi
            ;;
        "repair")
            repair_acme_json "$ACME_JSON_PATH"
            log_info "ACME JSON repair completed"
            exit 0
            ;;
        "backup")
            backup_acme_json
            log_info "ACME JSON backup completed"
            exit 0
            ;;
        *)
            echo "Usage: $0 [domain] [renew|validate|repair|backup]"
            echo "  domain: Domain to process (default: \$DOMAIN)"
            echo "  action: Action to perform (default: renew)"
            exit 1
            ;;
    esac
}

# Trap cleanup on exit
trap cleanup_temp_files EXIT

# Run main function
main "$@"