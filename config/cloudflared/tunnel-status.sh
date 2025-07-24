#!/bin/sh
# Cloudflare Tunnel Status Script
# Simple status monitoring script for tunnel health and metrics

set -e

# Configuration
METRICS_URL="http://localhost:8080/metrics"
CONFIG_FILE="/etc/cloudflared/config.yml"

# Check command line arguments
case "${1:-status}" in
    "health")
        # Quick health check
        if pgrep -f "cloudflared.*tunnel.*run" > /dev/null 2>&1; then
            echo "✓ cloudflared process is running"
            if wget --quiet --tries=1 --timeout=5 --spider "$METRICS_URL" 2>/dev/null; then
                echo "✓ Metrics endpoint is accessible"
                exit 0
            else
                echo "✗ Metrics endpoint is not accessible"
                exit 1
            fi
        else
            echo "✗ cloudflared process is not running"
            exit 1
        fi
        ;;
    
    "metrics")
        # Get metrics in JSON format
        if wget --quiet --tries=1 --timeout=10 -O - "$METRICS_URL" 2>/dev/null; then
            exit 0
        else
            echo "Error: Cannot fetch metrics from $METRICS_URL"
            exit 1
        fi
        ;;
    
    "status"|*)
        # Default status check
        echo "=== Cloudflare Tunnel Status ==="
        echo "$(date)"
        echo
        
        # Process status
        if pgrep -f "cloudflared.*tunnel.*run" > /dev/null 2>&1; then
            echo "✓ Process: Running"
            PID=$(pgrep -f "cloudflared.*tunnel.*run")
            echo "  PID: $PID"
        else
            echo "✗ Process: Not running"
        fi
        
        # Metrics endpoint
        if wget --quiet --tries=1 --timeout=5 --spider "$METRICS_URL" 2>/dev/null; then
            echo "✓ Metrics: Accessible at $METRICS_URL"
        else
            echo "✗ Metrics: Not accessible"
        fi
        
        # Configuration file
        if [ -f "$CONFIG_FILE" ]; then
            echo "✓ Config: Found at $CONFIG_FILE"
            if cloudflared tunnel ingress validate "$CONFIG_FILE" > /dev/null 2>&1; then
                echo "✓ Config: Valid"
            else
                echo "✗ Config: Invalid"
            fi
        else
            echo "✗ Config: Not found"
        fi
        
        # Tunnel ID
        if [ -f "$CONFIG_FILE" ] && grep -q "tunnel:" "$CONFIG_FILE"; then
            TUNNEL_ID=$(grep "tunnel:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
            if [ "$TUNNEL_ID" != "YOUR_TUNNEL_ID" ]; then
                echo "✓ Tunnel ID: $TUNNEL_ID"
            else
                echo "⚠ Tunnel ID: Not configured (using placeholder)"
            fi
        else
            echo "✗ Tunnel ID: Not found in config"
        fi
        ;;
esac