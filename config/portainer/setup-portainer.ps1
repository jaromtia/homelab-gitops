# Portainer Setup Script
# This script initializes Portainer with proper configuration for container management

param(
    [string]$AdminPassword = "",
    [switch]$Force = $false
)

Write-Host "=== Portainer Setup Script ===" -ForegroundColor Green
Write-Host "Setting up Portainer container management interface..." -ForegroundColor Yellow

# Check if Docker is running
try {
    docker version | Out-Null
    Write-Host "✓ Docker is running" -ForegroundColor Green
} catch {
    Write-Host "✗ Docker is not running. Please start Docker first." -ForegroundColor Red
    exit 1
}

# Check if Portainer container exists and is running
$portainerStatus = docker ps -a --filter "name=portainer" --format "{{.Status}}"
if ($portainerStatus) {
    Write-Host "Portainer container found: $portainerStatus" -ForegroundColor Yellow
    
    if ($portainerStatus -like "*Up*") {
        Write-Host "✓ Portainer is already running" -ForegroundColor Green
        if (-not $Force) {
            Write-Host "Use -Force to restart Portainer" -ForegroundColor Yellow
            exit 0
        }
    }
}

# Create necessary directories
$configDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$dataDir = Join-Path (Split-Path -Parent (Split-Path -Parent $configDir)) "data"
$logsDir = Join-Path $dataDir "logs"

if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    Write-Host "✓ Created logs directory: $logsDir" -ForegroundColor Green
}

# Verify Docker socket access
if (-not (Test-Path "\\.\pipe\docker_engine")) {
    Write-Host "✗ Docker socket not accessible. Ensure Docker Desktop is running." -ForegroundColor Red
    exit 1
}

Write-Host "✓ Docker socket is accessible" -ForegroundColor Green

# Check if Portainer service is defined in docker-compose.yml
$composeFile = Join-Path (Split-Path -Parent (Split-Path -Parent $configDir)) "docker-compose.yml"
if (Test-Path $composeFile) {
    $composeContent = Get-Content $composeFile -Raw
    if ($composeContent -match "portainer:") {
        Write-Host "✓ Portainer service found in docker-compose.yml" -ForegroundColor Green
    } else {
        Write-Host "✗ Portainer service not found in docker-compose.yml" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "✗ docker-compose.yml not found" -ForegroundColor Red
    exit 1
}

# Start Portainer via docker-compose
Write-Host "Starting Portainer service..." -ForegroundColor Yellow
try {
    Set-Location (Split-Path -Parent (Split-Path -Parent $configDir))
    docker-compose up -d portainer
    
    # Wait for Portainer to be ready
    Write-Host "Waiting for Portainer to start..." -ForegroundColor Yellow
    $maxAttempts = 30
    $attempt = 0
    
    do {
        Start-Sleep -Seconds 2
        $attempt++
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:9000/api/status" -TimeoutSec 5 -UseBasicParsing
            if ($response.StatusCode -eq 200) {
                Write-Host "✓ Portainer is ready!" -ForegroundColor Green
                break
            }
        } catch {
            # Continue waiting
        }
        
        if ($attempt -eq $maxAttempts) {
            Write-Host "✗ Portainer failed to start within timeout" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "." -NoNewline -ForegroundColor Yellow
    } while ($true)
    
} catch {
    Write-Host "✗ Failed to start Portainer: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Display access information
Write-Host "`n=== Portainer Setup Complete ===" -ForegroundColor Green
Write-Host "Local Access: http://localhost:9000" -ForegroundColor Cyan
Write-Host "External Access: https://portainer.yourdomain.com (via Cloudflare tunnel)" -ForegroundColor Cyan
Write-Host "`nFeatures available:" -ForegroundColor Yellow
Write-Host "  • Container monitoring and control" -ForegroundColor White
Write-Host "  • Real-time log viewing" -ForegroundColor White
Write-Host "  • Resource monitoring (CPU, memory, network)" -ForegroundColor White
Write-Host "  • Container restart and management" -ForegroundColor White
Write-Host "`nFirst-time setup:" -ForegroundColor Yellow
Write-Host "  1. Navigate to http://localhost:9000" -ForegroundColor White
Write-Host "  2. Create admin user account" -ForegroundColor White
Write-Host "  3. Select 'Docker' environment" -ForegroundColor White
Write-Host "  4. Connect to local Docker socket" -ForegroundColor White

# Verify container health
Write-Host "`nVerifying container health..." -ForegroundColor Yellow
$healthStatus = docker inspect portainer --format='{{.State.Health.Status}}' 2>$null
if ($healthStatus -eq "healthy") {
    Write-Host "✓ Portainer container is healthy" -ForegroundColor Green
} else {
    Write-Host "⚠ Portainer container health status: $healthStatus" -ForegroundColor Yellow
}

# Display container information
$containerInfo = docker ps --filter "name=portainer" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
Write-Host "`nContainer Status:" -ForegroundColor Yellow
Write-Host $containerInfo -ForegroundColor White

Write-Host "`n✓ Portainer setup completed successfully!" -ForegroundColor Green