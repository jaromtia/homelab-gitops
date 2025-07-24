#!/bin/bash
# Cloudflare Tunnel Management Script
# This script provides utilities for managing locally managed Cloudflare tunnels
# including creation, configuration, DNS setup, and monitoring

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.yml"
CREDENTIALS_FILE="$SCRIPT_DIR/credentials.json"
CREDENTIALS_TEMPLATE="$SCRIPT_DIR/credentials.json.template"
ENV_FILE="$SCRIPT_DIR/../../.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

error() {
    echo -e "${RED}✗ ERROR: $1${NC}"
    exit 1
}

warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ INFO: $1${NC}"
}

# Check if cloudflared is installed
check_cloudflared() {
    if ! command -v cloudflared &> /dev/null; then
        error "cloudflared is not installed. Please install it first: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/"
    fi
    success "cloudflared is installed"
}

# Load environment variables
load_env() {
    if [ -f "$ENV_FILE" ]; then
        # Export variables from .env file
        set -a
        source "$ENV_FILE"
        set +a
        success "Environment variables loaded from .env"
    else
        warning ".env file not found. Some features may not work correctly."
    fi
}

# Create a new tunnel
create_tunnel() {
    local tunnel_name="${1:-homelab}"
    
    log "Creating new Cloudflare tunnel: $tunnel_name"
    
    # Create tunnel
    local tunnel_output
    tunnel_output=$(cloudflared tunnel create "$tunnel_name" 2>&1)
    
    if [ $? -eq 0 ]; then
        # Extract tunnel ID from output
        local tunnel_id
        tunnel_id=$(echo "$tunnel_output" | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}')
        
        success "Tunnel created successfully"
        info "Tunnel Name: $tunnel_name"
        info "Tunnel ID: $tunnel_id"
        
        # Update configuration with tunnel ID
        update_tunnel_config "$tunnel_id"
        
        # Copy credentials file
        copy_credentials "$tunnel_id"
        
        echo
        info "Next steps:"
        echo "1. Update your .env file with DOMAIN=your-domain.com"
        echo "2. Run: $0 setup-dns $tunnel_id"
        echo "3. Run: docker-compose up -d cloudflared"
        
    else
        error "Failed to create tunnel: $tunnel_output"
    fi
}

# Update tunnel configuration with tunnel ID
update_tunnel_config() {
    local tunnel_id="$1"
    
    if [ -z "$tunnel_id" ]; then
        error "Tunnel ID is required"
    fi
    
    log "Updating tunnel configuration with ID: $tunnel_id"
    
    # Replace placeholder tunnel ID in config
    sed -i.bak "s/YOUR_TUNNEL_ID/$tunnel_id/g" "$CONFIG_FILE"
    
    success "Configuration updated with tunnel ID"
}

# Copy credentials file from cloudflared directory
copy_credentials() {
    local tunnel_id="$1"
    
    if [ -z "$tunnel_id" ]; then
        error "Tunnel ID is required"
    fi
    
    local source_creds="$HOME/.cloudflared/$tunnel_id.json"
    
    if [ -f "$source_creds" ]; then
        cp "$source_creds" "$CREDENTIALS_FILE"
        chmod 600 "$CREDENTIALS_FILE"
        success "Credentials file copied and secured"
    else
        error "Credentials file not found at $source_creds"
    fi
}

# Setup DNS records
setup_dns() {
    local tunnel_id="$1"
    
    if [ -z "$tunnel_id" ]; then
        error "Tunnel ID is required"
    fi
    
    if [ -z "$DOMAIN" ]; then
        error "DOMAIN environment variable is not set. Please update your .env file."
    fi
    
    log "Setting up DNS records for domain: $DOMAIN"
    
    # List of subdomains to create
    local subdomains=(
        "$DOMAIN"
        "dashboard.$DOMAIN"
        "grafana.$DOMAIN"
        "prometheus.$DOMAIN"
        "portainer.$DOMAIN"
        "backup.$DOMAIN"
        "files.$DOMAIN"
        "bookmarks.$DOMAIN"
        "budget.$DOMAIN"
    )
    
    local tunnel_hostname="$tunnel_id.cfargotunnel.com"
    
    echo "Please create the following DNS CNAME records in your Cloudflare dashboard:"
    echo
    printf "%-25s | %-30s | %s\n" "Name" "Target" "Type"
    printf "%-25s | %-30s | %s\n" "----" "------" "----"
    
    for subdomain in "${subdomains[@]}"; do
        printf "%-25s | %-30s | %s\n" "$subdomain" "$tunnel_hostname" "CNAME"
    done
    
    echo
    info "Alternatively, you can use the Cloudflare API or Terraform to automate DNS setup"
    
    # Provide API example
    echo
    echo "Example using Cloudflare API:"
    echo "curl -X POST \"https://api.cloudflare.com/client/v4/zones/ZONE_ID/dns_records\" \\"
    echo "  -H \"Authorization: Bearer YOUR_API_TOKEN\" \\"
    echo "  -H \"Content-Type: application/json\" \\"
    echo "  --data '{\"type\":\"CNAME\",\"name\":\"dashboard\",\"content\":\"$tunnel_hostname\"}'"
}

# List existing tunnels
list_tunnels() {
    log "Listing existing Cloudflare tunnels"
    
    cloudflared tunnel list
}

# Get tunnel info
tunnel_info() {
    local tunnel_id="$1"
    
    if [ -z "$tunnel_id" ]; then
        # Try to extract from config file
        if [ -f "$CONFIG_FILE" ]; then
            tunnel_id=$(grep "tunnel:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
        fi
    fi
    
    if [ -z "$tunnel_id" ] || [ "$tunnel_id" = "YOUR_TUNNEL_ID" ]; then
        error "Tunnel ID not found. Please provide tunnel ID or configure it first."
    fi
    
    log "Getting tunnel information for: $tunnel_id"
    
    cloudflared tunnel info "$tunnel_id"
}

# Validate tunnel configuration
validate_config() {
    log "Validating tunnel configuration"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Configuration file not found: $CONFIG_FILE"
    fi
    
    # Validate configuration syntax
    if cloudflared tunnel ingress validate "$CONFIG_FILE"; then
        success "Configuration is valid"
    else
        error "Configuration validation failed"
    fi
    
    # Check for placeholder values
    if grep -q "YOUR_TUNNEL_ID" "$CONFIG_FILE"; then
        warning "Configuration contains placeholder tunnel ID"
    fi
    
    if grep -q "\${DOMAIN}" "$CONFIG_FILE"; then
        if [ -z "$DOMAIN" ]; then
            warning "DOMAIN environment variable not set"
        else
            info "Domain configured as: $DOMAIN"
        fi
    fi
}

# Test tunnel connectivity
test_connectivity() {
    local tunnel_id="$1"
    
    if [ -z "$tunnel_id" ]; then
        # Try to extract from config file
        if [ -f "$CONFIG_FILE" ]; then
            tunnel_id=$(grep "tunnel:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
        fi
    fi
    
    if [ -z "$tunnel_id" ] || [ "$tunnel_id" = "YOUR_TUNNEL_ID" ]; then
        error "Tunnel ID not found. Please provide tunnel ID or configure it first."
    fi
    
    log "Testing tunnel connectivity for: $tunnel_id"
    
    # Test tunnel connection
    if cloudflared tunnel info "$tunnel_id" > /dev/null 2>&1; then
        success "Tunnel is accessible"
    else
        error "Cannot connect to tunnel"
    fi
    
    # Test ingress rules if domain is configured
    if [ -n "$DOMAIN" ]; then
        log "Testing ingress rules for domain: $DOMAIN"
        
        local test_urls=(
            "https://$DOMAIN"
            "https://dashboard.$DOMAIN"
            "https://grafana.$DOMAIN"
        )
        
        for url in "${test_urls[@]}"; do
            if curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" | grep -q "200\|301\|302"; then
                success "✓ $url is accessible"
            else
                warning "✗ $url is not accessible (may be normal if services are not running)"
            fi
        done
    fi
}

# Monitor tunnel status
monitor_tunnel() {
    log "Starting tunnel monitoring (Press Ctrl+C to stop)"
    
    while true; do
        clear
        echo "=== Cloudflare Tunnel Status Monitor ==="
        echo "$(date)"
        echo
        
        # Check if cloudflared container is running
        if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "cloudflared"; then
            success "Cloudflared container is running"
            
            # Get container logs (last 10 lines)
            echo
            echo "Recent logs:"
            docker logs --tail 10 cloudflared 2>/dev/null || warning "Cannot access container logs"
            
        else
            warning "Cloudflared container is not running"
        fi
        
        echo
        echo "Refreshing in 30 seconds..."
        sleep 30
    done
}

# Cleanup tunnel
cleanup_tunnel() {
    local tunnel_id="$1"
    
    if [ -z "$tunnel_id" ]; then
        error "Tunnel ID is required for cleanup"
    fi
    
    warning "This will delete the tunnel permanently. Are you sure? (y/N)"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        log "Cleaning up tunnel: $tunnel_id"
        
        # Stop container if running
        docker stop cloudflared 2>/dev/null || true
        
        # Delete tunnel
        cloudflared tunnel delete "$tunnel_id"
        
        # Remove credentials file
        rm -f "$CREDENTIALS_FILE"
        
        # Reset config file
        sed -i.bak "s/$tunnel_id/YOUR_TUNNEL_ID/g" "$CONFIG_FILE"
        
        success "Tunnel cleanup completed"
    else
        info "Cleanup cancelled"
    fi
}

# Show help
show_help() {
    echo "Cloudflare Tunnel Management Script"
    echo
    echo "Usage: $0 <command> [arguments]"
    echo
    echo "Commands:"
    echo "  create [name]           Create a new tunnel (default name: homelab)"
    echo "  setup-dns <tunnel-id>   Show DNS setup instructions"
    echo "  list                    List existing tunnels"
    echo "  info [tunnel-id]        Show tunnel information"
    echo "  validate                Validate tunnel configuration"
    echo "  test [tunnel-id]        Test tunnel connectivity"
    echo "  monitor                 Monitor tunnel status"
    echo "  cleanup <tunnel-id>     Delete tunnel and cleanup"
    echo "  help                    Show this help message"
    echo
    echo "Examples:"
    echo "  $0 create homelab"
    echo "  $0 setup-dns abc123-def456-ghi789"
    echo "  $0 test"
    echo "  $0 monitor"
}

# Main function
main() {
    local command="$1"
    
    case "$command" in
        "create")
            check_cloudflared
            load_env
            create_tunnel "$2"
            ;;
        "setup-dns")
            load_env
            setup_dns "$2"
            ;;
        "list")
            check_cloudflared
            list_tunnels
            ;;
        "info")
            check_cloudflared
            load_env
            tunnel_info "$2"
            ;;
        "validate")
            check_cloudflared
            load_env
            validate_config
            ;;
        "test")
            check_cloudflared
            load_env
            test_connectivity "$2"
            ;;
        "monitor")
            monitor_tunnel
            ;;
        "cleanup")
            check_cloudflared
            cleanup_tunnel "$2"
            ;;
        "help"|"--help"|"-h"|"")
            show_help
            ;;
        *)
            error "Unknown command: $command"
            echo
            show_help
            ;;
    esac
}

# Execute main function with all arguments
main "$@"