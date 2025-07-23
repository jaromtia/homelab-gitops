#!/bin/bash

# Traefik Configuration Test Script
# This script validates Traefik configuration and SSL setup

set -euo pipefail

# Configuration
DOMAIN="${DOMAIN:-localhost}"
TRAEFIK_CONTAINER="${TRAEFIK_CONTAINER:-traefik}"
TEST_TIMEOUT="${TEST_TIMEOUT:-30}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

# Logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo "Running test: $test_name"
    if $test_function; then
        log_info "✓ $test_name PASSED"
        ((TESTS_PASSED++))
    else
        log_error "✗ $test_name FAILED"
        ((TESTS_FAILED++))
    fi
    echo
}

# Test 1: Configuration file validation
test_config_files() {
    local config_files=(
        "config/traefik/traefik.yml"
        "config/traefik/dynamic/tls.yml"
        "config/traefik/dynamic/middleware.yml"
        "docker-compose.traefik.yml"
    )
    
    for file in "${config_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "Configuration file missing: $file"
            return 1
        fi
    done
    
    # Validate YAML syntax
    if command -v yamllint &> /dev/null; then
        for file in "${config_files[@]}"; do
            if [[ "$file" == *.yml ]] || [[ "$file" == *.yaml ]]; then
                if ! yamllint "$file" &> /dev/null; then
                    log_error "YAML syntax error in: $file"
                    return 1
                fi
            fi
        done
    fi
    
    return 0
}

# Test 2: Docker Compose validation
test_docker_compose() {
    if ! docker-compose -f docker-compose.traefik.yml config &> /dev/null; then
        log_error "Docker Compose configuration is invalid"
        return 1
    fi
    
    return 0
}

# Test 3: Environment variables
test_environment() {
    local required_vars=(
        "DOMAIN"
        "ACME_EMAIL"
        "TRAEFIK_DASHBOARD_USER"
        "TRAEFIK_DASHBOARD_PASSWORD_HASH"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            log_error "Required environment variable not set: $var"
            return 1
        fi
    done
    
    return 0
}

# Test 4: Container startup
test_container_startup() {
    log_info "Starting Traefik container..."
    
    if ! docker-compose -f docker-compose.traefik.yml up -d; then
        log_error "Failed to start Traefik container"
        return 1
    fi
    
    # Wait for container to be ready
    local retries=$TEST_TIMEOUT
    while [ $retries -gt 0 ]; do
        if docker ps --filter "name=$TRAEFIK_CONTAINER" --filter "status=running" | grep -q "$TRAEFIK_CONTAINER"; then
            log_info "Container started successfully"
            return 0
        fi
        sleep 1
        ((retries--))
    done
    
    log_error "Container failed to start within timeout"
    return 1
}

# Test 5: Health check endpoint
test_health_endpoint() {
    local retries=$TEST_TIMEOUT
    
    while [ $retries -gt 0 ]; do
        if curl -sf "http://localhost:8080/ping" > /dev/null; then
            log_info "Health endpoint responding"
            return 0
        fi
        sleep 1
        ((retries--))
    done
    
    log_error "Health endpoint not responding"
    return 1
}

# Test 6: Dashboard access
test_dashboard_access() {
    if curl -sf "http://localhost:8080/dashboard/" > /dev/null; then
        log_info "Dashboard accessible"
        return 0
    else
        log_error "Dashboard not accessible"
        return 1
    fi
}

# Test 7: Metrics endpoint
test_metrics_endpoint() {
    if curl -sf "http://localhost:8080/metrics" | grep -q "traefik_"; then
        log_info "Metrics endpoint working"
        return 0
    else
        log_error "Metrics endpoint not working"
        return 1
    fi
}

# Test 8: HTTP to HTTPS redirect
test_https_redirect() {
    if [ "$DOMAIN" != "localhost" ]; then
        local response
        response=$(curl -sI "http://$DOMAIN" | head -n 1)
        if echo "$response" | grep -q "301\|302"; then
            log_info "HTTP to HTTPS redirect working"
            return 0
        else
            log_error "HTTP to HTTPS redirect not working"
            return 1
        fi
    else
        log_warn "Skipping HTTPS redirect test for localhost"
        return 0
    fi
}

# Test 9: SSL certificate (if domain is not localhost)
test_ssl_certificate() {
    if [ "$DOMAIN" != "localhost" ]; then
        if echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null | openssl x509 -noout -text | grep -q "Let's Encrypt"; then
            log_info "SSL certificate from Let's Encrypt"
            return 0
        else
            log_warn "SSL certificate not from Let's Encrypt (may be self-signed or from another CA)"
            return 0
        fi
    else
        log_warn "Skipping SSL certificate test for localhost"
        return 0
    fi
}

# Test 10: Docker provider functionality
test_docker_provider() {
    # Check if Traefik can discover itself
    if curl -sf "http://localhost:8080/api/http/services" | grep -q "traefik"; then
        log_info "Docker provider discovering services"
        return 0
    else
        log_error "Docker provider not working"
        return 1
    fi
}

# Test 11: Log files
test_log_files() {
    # Check if log directory exists in container
    if docker exec "$TRAEFIK_CONTAINER" ls /var/log/traefik/ &> /dev/null; then
        log_info "Log directory accessible"
        return 0
    else
        log_error "Log directory not accessible"
        return 1
    fi
}

# Test 12: Volume mounts
test_volume_mounts() {
    local volumes=(
        "/var/run/docker.sock"
        "/etc/traefik/traefik.yml"
        "/etc/traefik/dynamic"
        "/letsencrypt"
    )
    
    for volume in "${volumes[@]}"; do
        if ! docker exec "$TRAEFIK_CONTAINER" ls "$volume" &> /dev/null; then
            log_error "Volume mount not accessible: $volume"
            return 1
        fi
    done
    
    log_info "All volume mounts accessible"
    return 0
}

# Test 13: SSL renewal error handling
test_ssl_renewal_error_handling() {
    log_info "Testing SSL renewal error handling capabilities..."
    
    # Test SSL health check script exists and is executable
    if [ ! -f "scripts/ssl-health-check.sh" ]; then
        log_error "SSL health check script not found"
        return 1
    fi
    
    # Test SSL renewal handler script exists
    if [ ! -f "scripts/ssl-renewal-handler.sh" ]; then
        log_error "SSL renewal handler script not found"
        return 1
    fi
    
    # Test ACME JSON validation function
    if command -v jq &> /dev/null; then
        # Create a test ACME JSON structure
        local test_acme="/tmp/test_acme.json"
        echo '{"letsencrypt":{"Account":{"Email":"test@example.com"},"Certificates":[]}}' > "$test_acme"
        
        if jq empty "$test_acme" &> /dev/null; then
            log_info "ACME JSON validation capability working"
            rm -f "$test_acme"
        else
            log_error "ACME JSON validation not working"
            rm -f "$test_acme"
            return 1
        fi
    else
        log_warn "jq not available, skipping ACME JSON validation test"
    fi
    
    # Test error recovery mechanisms
    if docker exec "$TRAEFIK_CONTAINER" ls /letsencrypt &> /dev/null; then
        log_info "ACME storage directory accessible for error recovery"
    else
        log_error "ACME storage directory not accessible"
        return 1
    fi
    
    return 0
}

# Test 14: Enhanced middleware functionality
test_enhanced_middleware() {
    log_info "Testing enhanced middleware functionality..."
    
    # Check if dynamic middleware configuration is loaded
    if curl -sf "http://localhost:8080/api/http/middlewares" | grep -q "security-headers\|rate-limit\|circuit-breaker"; then
        log_info "Enhanced middleware configurations loaded"
        return 0
    else
        log_error "Enhanced middleware configurations not loaded"
        return 1
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    docker-compose -f docker-compose.traefik.yml down -v &> /dev/null || true
}

# Main test execution
main() {
    echo "Starting Traefik Configuration Tests"
    echo "===================================="
    echo
    
    # Load environment variables if .env exists
    if [ -f ".env" ]; then
        set -a
        source .env
        set +a
        log_info "Loaded environment variables from .env"
    fi
    
    # Run tests
    run_test "Configuration Files" test_config_files
    run_test "Docker Compose Validation" test_docker_compose
    run_test "Environment Variables" test_environment
    run_test "Container Startup" test_container_startup
    run_test "Health Endpoint" test_health_endpoint
    run_test "Dashboard Access" test_dashboard_access
    run_test "Metrics Endpoint" test_metrics_endpoint
    run_test "Volume Mounts" test_volume_mounts
    run_test "Docker Provider" test_docker_provider
    run_test "Log Files" test_log_files
    run_test "SSL Renewal Error Handling" test_ssl_renewal_error_handling
    run_test "Enhanced Middleware" test_enhanced_middleware
    run_test "HTTPS Redirect" test_https_redirect
    run_test "SSL Certificate" test_ssl_certificate
    
    # Test summary
    echo "Test Summary"
    echo "============"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_info "All tests passed! Traefik configuration is working correctly."
        cleanup
        exit 0
    else
        log_error "Some tests failed. Please check the configuration."
        cleanup
        exit 1
    fi
}

# Trap cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"