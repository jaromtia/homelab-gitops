#!/bin/sh
# Simple tunnel health check for Docker health checks
# Returns 0 if healthy, 1 if unhealthy

# Check if cloudflared process is running
if ! pgrep -f "cloudflared.*tunnel.*run" > /dev/null 2>&1; then
    exit 1
fi

# Check if metrics endpoint is accessible
if ! wget --quiet --tries=1 --timeout=5 --spider "http://localhost:8080/metrics" 2>/dev/null; then
    exit 1
fi

# All checks passed
exit 0