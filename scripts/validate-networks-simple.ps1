#!/usr/bin/env pwsh
# Simple Network Configuration Validation Script

Write-Host "=== Homelab Infrastructure Network Validation ===" -ForegroundColor Cyan

# Check if Docker is running
try {
    docker version | Out-Null
    Write-Host "✓ Docker is running" -ForegroundColor Green
}
catch {
    Write-Host "✗ Docker is not running or not accessible" -ForegroundColor Red
    exit 1
}

# Validate Docker Compose file
Write-Host "`nValidating Docker Compose configuration..." -ForegroundColor Yellow
try {
    docker-compose config --quiet
    Write-Host "✓ Docker Compose file is valid" -ForegroundColor Green
}
catch {
    Write-Host "✗ Docker Compose file has errors" -ForegroundColor Red
    exit 1
}

# Check for required networks in compose output
Write-Host "`nChecking network definitions..." -ForegroundColor Yellow

$networks = @("homelab_frontend", "homelab_backend", "homelab_monitoring")
foreach ($network in $networks) {
    if (docker-compose config | Select-String -Pattern $network -Quiet) {
        Write-Host "  ✓ Network $network defined" -ForegroundColor Green
    }
    else {
        Write-Host "  ✗ Network $network missing" -ForegroundColor Red
    }
}

# Check for Cloudflare tunnel service
Write-Host "`nChecking Cloudflare tunnel service..." -ForegroundColor Yellow
if (docker-compose config | Select-String -Pattern "cloudflared:" -Quiet) {
    Write-Host "  ✓ Cloudflare tunnel service defined" -ForegroundColor Green
}
else {
    Write-Host "  ✗ Cloudflare tunnel service missing" -ForegroundColor Red
}

# Check for volume definitions
Write-Host "`nChecking volume definitions..." -ForegroundColor Yellow
$volumes = @("prometheus_data", "grafana_data", "loki_data", "cloudflared_logs")
foreach ($volume in $volumes) {
    if (docker-compose config | Select-String -Pattern "homelab_$volume" -Quiet) {
        Write-Host "  ✓ Volume $volume defined" -ForegroundColor Green
    }
    else {
        Write-Host "  ✗ Volume $volume missing" -ForegroundColor Red
    }
}

Write-Host "`n=== Validation Complete ===" -ForegroundColor Cyan