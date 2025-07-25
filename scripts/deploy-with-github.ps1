#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Complete deployment script with GitHub integration
.DESCRIPTION
    This script handles complete homelab infrastructure deployment with GitHub integration.
    It can deploy from scratch, update existing deployments, and manage configuration synchronization.
.PARAMETER Mode
    Deployment mode: fresh, update, or restore
.PARAMETER SyncToGitHub
    Whether to sync configuration to GitHub after deployment
.PARAMETER Branch
    Git branch to use (default: main)
.EXAMPLE
    .\deploy-with-github.ps1 -Mode fresh -SyncToGitHub
    .\deploy-with-github.ps1 -Mode update
    .\deploy-with-github.ps1 -Mode restore -Branch develop
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("fresh", "update", "restore")]
    [string]$Mode,
    
    [Parameter(Mandatory=$false)]
    [switch]$SyncToGitHub,
    
    [Parameter(Mandatory=$false)]
    [string]$Branch = "main"
)

# Import common functions
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

function Test-Prerequisites {
    Write-Log "Checking deployment prerequisites..."
    
    $prerequisites = @(
        @{ Name = "Docker"; Command = "docker --version" },
        @{ Name = "Docker Compose"; Command = "docker-compose --version" },
        @{ Name = "Git"; Command = "git --version" }
    )
    
    $allGood = $true
    foreach ($prereq in $prerequisites) {
        try {
            $version = Invoke-Expression $prereq.Command
            Write-Log "$($prereq.Name) found: $version"
        } catch {
            Write-Log "$($prereq.Name) is not installed or not in PATH" "ERROR"
            $allGood = $false
        }
    }
    
    return $allGood
}

function Initialize-GitRepository {
    Write-Log "Initializing Git repository for configuration management..."
    
    # Run the GitHub sync script to initialize
    $initScript = Join-Path $scriptDir "github-sync.ps1"
    if (Test-Path $initScript) {
        & $initScript -Action init
    } else {
        Write-Log "GitHub sync script not found. Initializing manually..." "WARN"
        
        if (-not (Test-Path ".git")) {
            git init
            Write-Log "Git repository initialized"
        }
    }
}

function Deploy-FreshInstallation {
    Write-Log "Starting fresh installation deployment..."
    
    # Check if this is truly a fresh installation
    if (Test-Path "docker-compose.yml") {
        Write-Log "Existing installation detected. Use 'update' mode instead." "WARN"
        $response = Read-Host "Continue with fresh installation? This will overwrite existing files. (y/N)"
        if ($response -ne "y" -and $response -ne "Y") {
            Write-Log "Fresh installation cancelled"
            return $false
        }
    }
    
    # Create directory structure
    Write-Log "Creating directory structure..."
    $directories = @(
        "config/cloudflared",
        "config/prometheus",
        "config/grafana/provisioning/dashboards",
        "config/grafana/provisioning/datasources",
        "config/loki",
        "config/promtail",
        "config/dashy",
        "config/duplicati",
        "config/filebrowser",
        "config/linkding",
        "config/actual",
        "config/portainer",
        "data/files",
        "data/backups",
        "data/logs",
        "scripts",
        "docs"
    )
    
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Log "Created directory: $dir"
        }
    }
    
    # Create .env from template if it doesn't exist
    if (-not (Test-Path ".env")) {
        if (Test-Path ".env.template") {
            Copy-Item ".env.template" ".env"
            Write-Log "Created .env from template"
            Write-Log "IMPORTANT: Please edit .env file with your configuration before continuing" "WARN"
            
            # Pause for user to edit .env
            Read-Host "Press Enter after editing .env file to continue"
        } else {
            Write-Log ".env.template not found. Cannot create .env file." "ERROR"
            return $false
        }
    }
    
    # Initialize Git repository
    Initialize-GitRepository
    
    # Deploy services
    return Deploy-Services
}

function Deploy-UpdateInstallation {
    Write-Log "Starting update deployment..."
    
    # Check if installation exists
    if (-not (Test-Path "docker-compose.yml")) {
        Write-Log "No existing installation found. Use 'fresh' mode instead." "ERROR"
        return $false
    }
    
    # Pull latest images
    Write-Log "Pulling latest Docker images..."
    try {
        docker-compose pull
        Write-Log "Docker images updated successfully"
    } catch {
        Write-Log "Failed to pull Docker images: $_" "ERROR"
        return $false
    }
    
    # Deploy services with updated images
    return Deploy-Services
}

function Deploy-RestoreInstallation {
    Write-Log "Starting restore deployment..."
    
    # Use the restore script
    $restoreScript = Join-Path $scriptDir "restore-from-github.ps1"
    if (-not (Test-Path $restoreScript)) {
        Write-Log "Restore script not found: $restoreScript" "ERROR"
        return $false
    }
    
    # Run restore script
    try {
        & $restoreScript -Branch $Branch -Force
        Write-Log "Configuration restored from GitHub"
    } catch {
        Write-Log "Failed to restore from GitHub: $_" "ERROR"
        return $false
    }
    
    # Deploy services after restoration
    return Deploy-Services
}

function Deploy-Services {
    Write-Log "Deploying services with Docker Compose..."
    
    # Validate configuration
    try {
        docker-compose config | Out-Null
        Write-Log "Docker Compose configuration is valid"
    } catch {
        Write-Log "Docker Compose configuration is invalid: $_" "ERROR"
        return $false
    }
    
    # Stop existing services
    Write-Log "Stopping existing services..."
    docker-compose down
    
    # Start services
    Write-Log "Starting services..."
    try {
        docker-compose up -d
        Write-Log "Services started successfully"
    } catch {
        Write-Log "Failed to start services: $_" "ERROR"
        return $false
    }
    
    # Wait for services to be ready
    Write-Log "Waiting for services to be ready..."
    Start-Sleep -Seconds 30
    
    # Check service health
    return Test-ServiceHealth
}

function Test-ServiceHealth {
    Write-Log "Testing service health..."
    
    $services = @(
        @{ Name = "Prometheus"; Url = "http://localhost:9090/-/ready"; Timeout = 30 },
        @{ Name = "Grafana"; Url = "http://localhost:3000/api/health"; Timeout = 60 },
        @{ Name = "Portainer"; Url = "http://localhost:9000/api/status"; Timeout = 30 },
        @{ Name = "FileBrowser"; Url = "http://localhost:8082/health"; Timeout = 30 }
    )
    
    $healthyServices = 0
    $totalServices = $services.Count
    
    foreach ($service in $services) {
        Write-Log "Checking $($service.Name)..."
        
        $maxAttempts = [math]::Ceiling($service.Timeout / 5)
        $attempt = 0
        $healthy = $false
        
        while ($attempt -lt $maxAttempts -and -not $healthy) {
            $attempt++
            try {
                $response = Invoke-WebRequest -Uri $service.Url -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                if ($response.StatusCode -eq 200) {
                    Write-Log "$($service.Name) is healthy ✓"
                    $healthy = $true
                    $healthyServices++
                }
            } catch {
                if ($attempt -eq $maxAttempts) {
                    Write-Log "$($service.Name) is not responding ✗" "WARN"
                } else {
                    Start-Sleep -Seconds 5
                }
            }
        }
    }
    
    Write-Log "Service health check complete: $healthyServices/$totalServices services healthy"
    
    # Consider deployment successful if at least 75% of services are healthy
    $successThreshold = [math]::Ceiling($totalServices * 0.75)
    return $healthyServices -ge $successThreshold
}

function Sync-ConfigurationToGitHub {
    Write-Log "Syncing configuration to GitHub..."
    
    $syncScript = Join-Path $scriptDir "github-sync.ps1"
    if (-not (Test-Path $syncScript)) {
        Write-Log "GitHub sync script not found: $syncScript" "ERROR"
        return $false
    }
    
    try {
        $commitMessage = "Automated deployment sync - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        & $syncScript -Action push -Message $commitMessage
        Write-Log "Configuration synced to GitHub successfully"
        return $true
    } catch {
        Write-Log "Failed to sync to GitHub: $_" "ERROR"
        return $false
    }
}

function Show-DeploymentSummary {
    param([bool]$Success, [string]$DeploymentMode)
    
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "DEPLOYMENT SUMMARY" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    
    Write-Host "Mode: $DeploymentMode" -ForegroundColor White
    Write-Host "Status: $(if ($Success) { 'SUCCESS ✓' } else { 'FAILED ✗' })" -ForegroundColor $(if ($Success) { 'Green' } else { 'Red' })
    Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
    
    if ($Success) {
        Write-Host "`nServices are now running. Access them at:" -ForegroundColor Green
        Write-Host "• Dashboard (Dashy): http://localhost:80" -ForegroundColor White
        Write-Host "• Monitoring (Grafana): http://localhost:3000" -ForegroundColor White
        Write-Host "• Metrics (Prometheus): http://localhost:9090" -ForegroundColor White
        Write-Host "• Containers (Portainer): http://localhost:9000" -ForegroundColor White
        Write-Host "• Files (FileBrowser): http://localhost:8082" -ForegroundColor White
        Write-Host "• Bookmarks (Linkding): http://localhost:9090" -ForegroundColor White
        Write-Host "• Budget (Actual): http://localhost:5006" -ForegroundColor White
        Write-Host "• Backup (Duplicati): http://localhost:8200" -ForegroundColor White
        
        Write-Host "`nNext steps:" -ForegroundColor Yellow
        Write-Host "1. Configure Cloudflare tunnel for external access" -ForegroundColor White
        Write-Host "2. Set up service-specific configurations" -ForegroundColor White
        Write-Host "3. Configure backup schedules in Duplicati" -ForegroundColor White
        Write-Host "4. Review and customize Grafana dashboards" -ForegroundColor White
    } else {
        Write-Host "`nDeployment failed. Check the logs above for details." -ForegroundColor Red
        Write-Host "Common issues:" -ForegroundColor Yellow
        Write-Host "• Docker not running" -ForegroundColor White
        Write-Host "• Port conflicts" -ForegroundColor White
        Write-Host "• Invalid .env configuration" -ForegroundColor White
        Write-Host "• Network connectivity issues" -ForegroundColor White
    }
    
    Write-Host "="*60 -ForegroundColor Cyan
}

# Main execution
Write-Log "Starting homelab deployment with GitHub integration"
Write-Log "Mode: $Mode, Branch: $Branch, Sync to GitHub: $SyncToGitHub"

# Check prerequisites
if (-not (Test-Prerequisites)) {
    Write-Log "Prerequisites check failed. Please install required tools." "ERROR"
    exit 1
}

# Execute deployment based on mode
$deploymentSuccess = $false

switch ($Mode) {
    "fresh" {
        $deploymentSuccess = Deploy-FreshInstallation
    }
    "update" {
        $deploymentSuccess = Deploy-UpdateInstallation
    }
    "restore" {
        $deploymentSuccess = Deploy-RestoreInstallation
    }
}

# Sync to GitHub if requested and deployment was successful
if ($deploymentSuccess -and $SyncToGitHub) {
    $syncSuccess = Sync-ConfigurationToGitHub
    if (-not $syncSuccess) {
        Write-Log "Deployment succeeded but GitHub sync failed" "WARN"
    }
}

# Show deployment summary
Show-DeploymentSummary -Success $deploymentSuccess -DeploymentMode $Mode

# Exit with appropriate code
if ($deploymentSuccess) {
    Write-Log "Deployment completed successfully"
    exit 0
} else {
    Write-Log "Deployment failed"
    exit 1
}