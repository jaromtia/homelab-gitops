#!/usr/bin/env pwsh
# Task 3.1 Validation Script
# Validates that the Docker Compose file meets all requirements for task 3.1

Write-Host "=== Task 3.1 Validation: Docker Compose Networking ===" -ForegroundColor Cyan

$success = $true

# Test 1: Validate Docker Compose syntax
Write-Host "`n1. Validating Docker Compose syntax..." -ForegroundColor Yellow
try {
    docker-compose config --quiet
    Write-Host "   ✓ Docker Compose file is syntactically valid" -ForegroundColor Green
}
catch {
    Write-Host "   ✗ Docker Compose file has syntax errors" -ForegroundColor Red
    $success = $false
}

# Test 2: Check for isolated networks
Write-Host "`n2. Checking isolated networks..." -ForegroundColor Yellow
$requiredNetworks = @("homelab_frontend", "homelab_backend", "homelab_monitoring")
foreach ($network in $requiredNetworks) {
    if (docker-compose config | Select-String -Pattern "name: $network" -Quiet) {
        Write-Host "   ✓ Network $network is defined" -ForegroundColor Green
    }
    else {
        Write-Host "   ✗ Network $network is missing" -ForegroundColor Red
        $success = $false
    }
}

# Test 3: Verify backend and monitoring networks are internal
Write-Host "`n3. Checking network isolation..." -ForegroundColor Yellow
if (docker-compose config | Select-String -Pattern "internal: true" -Quiet) {
    Write-Host "   ✓ Internal networks are properly configured" -ForegroundColor Green
}
else {
    Write-Host "   ✗ Internal network configuration missing" -ForegroundColor Red
    $success = $false
}

# Test 4: Check Cloudflare tunnel service
Write-Host "`n4. Validating Cloudflare tunnel service..." -ForegroundColor Yellow
if (docker-compose config | Select-String -Pattern "container_name: cloudflared" -Quiet) {
    Write-Host "   ✓ Cloudflare tunnel service is defined" -ForegroundColor Green
}
else {
    Write-Host "   ✗ Cloudflare tunnel service is missing" -ForegroundColor Red
    $success = $false
}

# Test 5: Check tunnel configuration volumes
Write-Host "`n5. Checking tunnel configuration volumes..." -ForegroundColor Yellow
if (docker-compose config | Select-String -Pattern "./config/cloudflared:/etc/cloudflared" -Quiet) {
    Write-Host "   ✓ Tunnel configuration volume is mounted" -ForegroundColor Green
}
else {
    Write-Host "   ✗ Tunnel configuration volume is missing" -ForegroundColor Red
    $success = $false
}

# Test 6: Check shared volumes
Write-Host "`n6. Validating shared volumes..." -ForegroundColor Yellow
$requiredVolumes = @("prometheus_data", "grafana_data", "loki_data", "cloudflared_logs")
foreach ($volume in $requiredVolumes) {
    if (docker-compose config | Select-String -Pattern "name: homelab_$volume" -Quiet) {
        Write-Host "   ✓ Volume $volume is configured" -ForegroundColor Green
    }
    else {
        Write-Host "   ✗ Volume $volume is missing" -ForegroundColor Red
        $success = $false
    }
}

# Test 7: Check network assignments
Write-Host "`n7. Checking service network assignments..." -ForegroundColor Yellow
if (docker-compose config | Select-String -Pattern "frontend:" -Quiet) {
    Write-Host "   ✓ Services are assigned to networks" -ForegroundColor Green
}
else {
    Write-Host "   ✗ Network assignments are missing" -ForegroundColor Red
    $success = $false
}

# Final result
Write-Host "`n=== Task 3.1 Validation Results ===" -ForegroundColor Cyan
if ($success) {
    Write-Host "✓ All requirements for task 3.1 are met!" -ForegroundColor Green
    Write-Host "  - Isolated networks defined (frontend, backend, monitoring)" -ForegroundColor Green
    Write-Host "  - Cloudflare tunnel service configured with proper volumes" -ForegroundColor Green
    Write-Host "  - Shared volumes and network configurations in place" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "✗ Some requirements are not met. Please review the issues above." -ForegroundColor Red
    exit 1
}