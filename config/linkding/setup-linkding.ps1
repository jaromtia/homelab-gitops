# Linkding Bookmark Manager Setup Script
# This script helps with initial setup and configuration of Linkding

param(
    [string]$Action = "setup",
    [string]$Username = $env:LINKDING_SUPERUSER_NAME,
    [string]$Password = $env:LINKDING_SUPERUSER_PASSWORD
)

# Configuration
$ContainerName = "linkding"
$ServiceUrl = "http://localhost:9091"
$ExternalUrl = "https://bookmarks.$env:DOMAIN"

function Write-Status {
    param([string]$Message, [string]$Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Type] $Message" -ForegroundColor $(
        switch ($Type) {
            "ERROR" { "Red" }
            "SUCCESS" { "Green" }
            "WARNING" { "Yellow" }
            default { "Cyan" }
        }
    )
}

function Test-LinkdingHealth {
    try {
        $response = Invoke-WebRequest -Uri "$ServiceUrl/health" -Method GET -TimeoutSec 10
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Wait-ForLinkding {
    Write-Status "Waiting for Linkding to be ready..."
    $maxAttempts = 30
    $attempt = 0
    
    do {
        $attempt++
        if (Test-LinkdingHealth) {
            Write-Status "Linkding is ready!" "SUCCESS"
            return $true
        }
        
        Write-Status "Attempt $attempt/$maxAttempts - Linkding not ready yet..."
        Start-Sleep -Seconds 5
    } while ($attempt -lt $maxAttempts)
    
    Write-Status "Linkding failed to become ready after $maxAttempts attempts" "ERROR"
    return $false
}

function Show-LinkdingStatus {
    Write-Status "Checking Linkding service status..."
    
    # Check container status
    $containerStatus = docker ps --filter "name=$ContainerName" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    if ($containerStatus -match $ContainerName) {
        Write-Status "Container Status:" "SUCCESS"
        Write-Host $containerStatus
    } else {
        Write-Status "Container not running" "ERROR"
        return
    }
    
    # Check health
    if (Test-LinkdingHealth) {
        Write-Status "Health Check: PASSED" "SUCCESS"
    } else {
        Write-Status "Health Check: FAILED" "ERROR"
    }
    
    # Show access URLs
    Write-Status "Access URLs:"
    Write-Host "  Local:    $ServiceUrl"
    Write-Host "  External: $ExternalUrl"
    Write-Host "  Username: $Username"
}

function Setup-Linkding {
    Write-Status "Setting up Linkding bookmark manager..."
    
    # Verify environment variables
    if (-not $Username -or -not $Password) {
        Write-Status "Missing required environment variables:" "ERROR"
        Write-Host "  LINKDING_SUPERUSER_NAME: $Username"
        Write-Host "  LINKDING_SUPERUSER_PASSWORD: $(if($Password) { '[SET]' } else { '[NOT SET]' })"
        return
    }
    
    # Check if container is running
    $containerRunning = docker ps --filter "name=$ContainerName" --quiet
    if (-not $containerRunning) {
        Write-Status "Starting Linkding container..." "WARNING"
        docker-compose up -d linkding
        Start-Sleep -Seconds 10
    }
    
    # Wait for service to be ready
    if (-not (Wait-ForLinkding)) {
        return
    }
    
    Write-Status "Linkding setup completed successfully!" "SUCCESS"
    Write-Status "Configuration details:"
    Write-Host "  Service: Linkding Bookmark Manager"
    Write-Host "  Version: Latest"
    Write-Host "  Local URL: $ServiceUrl"
    Write-Host "  External URL: $ExternalUrl"
    Write-Host "  Admin User: $Username"
    Write-Host "  Data Volume: linkding_data"
    Write-Host "  Backup: Included in Duplicati jobs"
    
    Write-Status "Next steps:"
    Write-Host "  1. Access the web interface at $ExternalUrl"
    Write-Host "  2. Log in with username: $Username"
    Write-Host "  3. Install browser extension for easy bookmark saving"
    Write-Host "  4. Import existing bookmarks if needed"
    Write-Host "  5. Configure API token for automation (optional)"
}

function Show-LinkdingLogs {
    Write-Status "Showing Linkding container logs..."
    docker logs $ContainerName --tail 50 --follow
}

function Restart-Linkding {
    Write-Status "Restarting Linkding service..."
    docker-compose restart linkding
    
    if (Wait-ForLinkding) {
        Write-Status "Linkding restarted successfully!" "SUCCESS"
    } else {
        Write-Status "Failed to restart Linkding" "ERROR"
    }
}

# Main execution
switch ($Action.ToLower()) {
    "setup" {
        Setup-Linkding
    }
    "status" {
        Show-LinkdingStatus
    }
    "logs" {
        Show-LinkdingLogs
    }
    "restart" {
        Restart-Linkding
    }
    "health" {
        if (Test-LinkdingHealth) {
            Write-Status "Linkding health check: PASSED" "SUCCESS"
        } else {
            Write-Status "Linkding health check: FAILED" "ERROR"
        }
    }
    default {
        Write-Status "Usage: setup-linkding.ps1 [-Action <setup|status|logs|restart|health>]"
        Write-Host "Actions:"
        Write-Host "  setup   - Initial setup and configuration"
        Write-Host "  status  - Show service status and access information"
        Write-Host "  logs    - Show container logs"
        Write-Host "  restart - Restart the service"
        Write-Host "  health  - Check service health"
    }
}