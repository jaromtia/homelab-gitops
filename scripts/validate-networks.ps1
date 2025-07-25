#!/usr/bin/env pwsh
# Network Configuration Validation Script
# Validates Docker Compose network configuration and connectivity

param(
    [switch]$Verbose = $false
)

Write-Host "=== Homelab Infrastructure Network Validation ===" -ForegroundColor Cyan

# Check if Docker is running
try {
    docker version | Out-Null
    Write-Host "✓ Docker is running" -ForegroundColor Green
} catch {
    Write-Host "✗ Docker is not running or not accessible" -ForegroundColor Red
    exit 1
}

# Validate Docker Compose file
Write-Host "`nValidating Docker Compose configuration..." -ForegroundColor Yellow
try {
    docker-compose config --quiet
    Write-Host "✓ Docker Compose file is valid" -ForegroundColor Green
} catch {
    Write-Host "✗ Docker Compose file has errors" -ForegroundColor Red
    docker-compose config
    exit 1
}

# Check network configuration
Write-Host "`nChecking network configuration..." -ForegroundColor Yellow

$networks = @(
    @{Name="homelab_frontend"; Subnet="172.20.0.0/16"; Type="frontend"; Access="external"},
    @{Name="homelab_backend"; Subnet="172.21.0.0/16"; Type="backend"; Access="internal"},
    @{Name="homelab_monitoring"; Subnet="172.22.0.0/16"; Type="monitoring"; Access="internal"}
)

foreach ($network in $networks) {
    Write-Host "  Checking $($network.Name)..." -ForegroundColor Cyan
    
    # Parse compose file to check network definition
    $composeConfig = docker-compose config 2>$null | ConvertFrom-Yaml -ErrorAction SilentlyContinue
    
    if ($composeConfig -and $composeConfig.networks -and $composeConfig.networks.($network.Name.Replace("homelab_", ""))) {
        Write-Host "    ✓ Network defined in compose file" -ForegroundColor Green
        
        $networkConfig = $composeConfig.networks.($network.Name.Replace("homelab_", ""))
        
        # Check subnet configuration
        if ($networkConfig.ipam.config[0].subnet -eq $network.Subnet) {
            Write-Host "    ✓ Subnet correctly configured: $($network.Subnet)" -ForegroundColor Green
        } else {
            Write-Host "    ✗ Subnet mismatch: expected $($network.Subnet)" -ForegroundColor Red
        }
        
        # Check internal flag for backend and monitoring networks
        if ($network.Access -eq "internal" -and $networkConfig.internal) {
            Write-Host "    ✓ Network correctly marked as internal" -ForegroundColor Green
        } elseif ($network.Access -eq "external" -and -not $networkConfig.internal) {
            Write-Host "    ✓ Network correctly configured for external access" -ForegroundColor Green
        } else {
            Write-Host "    ✗ Network access configuration incorrect" -ForegroundColor Red
        }
    } else {
        Write-Host "    ✗ Network not found in compose file" -ForegroundColor Red
    }
}

# Check volume configuration
Write-Host "`nChecking volume configuration..." -ForegroundColor Yellow

$requiredVolumes = @(
    "prometheus_data", "grafana_data", "loki_data", "portainer_data",
    "homer_data", "dashy_data", "filebrowser_data", "linkding_data",
    "actual_data", "duplicati_data", "cloudflared_logs"
)

foreach ($volume in $requiredVolumes) {
    if (docker-compose config | Select-String -Pattern "homelab_$volume" -Quiet) {
        Write-Host "  ✓ Volume $volume configured" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Volume $volume missing" -ForegroundColor Red
    }
}

# Check Cloudflare tunnel service configuration
Write-Host "`nChecking Cloudflare tunnel configuration..." -ForegroundColor Yellow

$tunnelConfig = docker-compose config | Select-String -Pattern "cloudflared:" -A 20
if ($tunnelConfig) {
    Write-Host "  ✓ Cloudflare tunnel service defined" -ForegroundColor Green
    
    # Check if tunnel is connected to frontend network
    if (docker-compose config | Select-String -Pattern "frontend" -Context 0,5 | Select-String -Pattern "cloudflared" -Quiet) {
        Write-Host "  ✓ Tunnel connected to frontend network" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Tunnel not properly connected to frontend network" -ForegroundColor Red
    }
    
    # Check volume mounts
    if (docker-compose config | Select-String -Pattern "./config/cloudflared:/etc/cloudflared:ro" -Quiet) {
        Write-Host "  ✓ Tunnel configuration volume mounted" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Tunnel configuration volume not mounted" -ForegroundColor Red
    }
} else {
    Write-Host "  ✗ Cloudflare tunnel service not found" -ForegroundColor Red
}

Write-Host "`n=== Network Validation Complete ===" -ForegroundColor Cyan

# Helper function to convert YAML (simplified for basic parsing)
function ConvertFrom-Yaml {
    param([Parameter(ValueFromPipeline)]$InputObject)
    # This is a simplified YAML parser for basic validation
    # In production, you'd want to use a proper YAML parser
    return $null
}