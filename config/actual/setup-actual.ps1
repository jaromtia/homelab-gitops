# Actual Budget Personal Finance Manager Setup Script
# This script helps with initial setup and configuration of Actual Budget

param(
    [string]$Action = "setup",
    [string]$Password = $env:ACTUAL_PASSWORD
)

# Configuration
$ContainerName = "actual"
$ServiceUrl = "http://localhost:5006"
$ExternalUrl = "https://budget.$env:DOMAIN"

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

function Test-ActualHealth {
    try {
        $response = Invoke-WebRequest -Uri "$ServiceUrl/" -Method GET -TimeoutSec 10
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Wait-ForActual {
    Write-Status "Waiting for Actual Budget to be ready..."
    $maxAttempts = 30
    $attempt = 0
    
    do {
        $attempt++
        if (Test-ActualHealth) {
            Write-Status "Actual Budget is ready!" "SUCCESS"
            return $true
        }
        
        Write-Status "Attempt $attempt/$maxAttempts - Actual Budget not ready yet..."
        Start-Sleep -Seconds 5
    } while ($attempt -lt $maxAttempts)
    
    Write-Status "Actual Budget failed to become ready after $maxAttempts attempts" "ERROR"
    return $false
}

function Show-ActualStatus {
    Write-Status "Checking Actual Budget service status..."
    
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
    if (Test-ActualHealth) {
        Write-Status "Health Check: PASSED" "SUCCESS"
    } else {
        Write-Status "Health Check: FAILED" "ERROR"
    }
    
    # Show access URLs
    Write-Status "Access URLs:"
    Write-Host "  Local:    $ServiceUrl"
    Write-Host "  External: $ExternalUrl"
    
    # Show data volume info
    $volumeInfo = docker volume inspect homelab_actual_data --format "{{.Mountpoint}}" 2>$null
    if ($volumeInfo) {
        Write-Status "Data Volume: homelab_actual_data"
        Write-Host "  Mount Point: $volumeInfo"
    }
}

function Setup-Actual {
    Write-Status "Setting up Actual Budget personal finance manager..."
    
    # Verify environment variables
    if (-not $Password) {
        Write-Status "Missing required environment variable:" "ERROR"
        Write-Host "  ACTUAL_PASSWORD: $(if($Password) { '[SET]' } else { '[NOT SET]' })"
        Write-Status "Please set ACTUAL_PASSWORD in your .env file" "ERROR"
        return
    }
    
    # Check if container is running
    $containerRunning = docker ps --filter "name=$ContainerName" --quiet
    if (-not $containerRunning) {
        Write-Status "Starting Actual Budget container..." "WARNING"
        docker-compose up -d actual
        Start-Sleep -Seconds 10
    }
    
    # Wait for service to be ready
    if (-not (Wait-ForActual)) {
        return
    }
    
    Write-Status "Actual Budget setup completed successfully!" "SUCCESS"
    Write-Status "Configuration details:"
    Write-Host "  Service: Actual Budget Personal Finance Manager"
    Write-Host "  Version: Latest"
    Write-Host "  Local URL: $ServiceUrl"
    Write-Host "  External URL: $ExternalUrl"
    Write-Host "  Server Password: [SET]"
    Write-Host "  Data Volume: actual_data"
    Write-Host "  Backup: Included in Duplicati jobs"
    
    Write-Status "Next steps:"
    Write-Host "  1. Access the web interface at $ExternalUrl"
    Write-Host "  2. Enter the server password when prompted"
    Write-Host "  3. Create your first budget file"
    Write-Host "  4. Add your bank accounts and credit cards"
    Write-Host "  5. Set up budget categories"
    Write-Host "  6. Import historical transactions (CSV/OFX)"
    Write-Host "  7. Install mobile app for on-the-go access"
    
    Write-Status "Mobile Apps:"
    Write-Host "  iOS: Search 'Actual Budget' in App Store"
    Write-Host "  Android: Search 'Actual Budget' in Google Play"
    Write-Host "  Server URL: $ExternalUrl"
}

function Show-ActualLogs {
    Write-Status "Showing Actual Budget container logs..."
    docker logs $ContainerName --tail 50 --follow
}

function Restart-Actual {
    Write-Status "Restarting Actual Budget service..."
    docker-compose restart actual
    
    if (Wait-ForActual) {
        Write-Status "Actual Budget restarted successfully!" "SUCCESS"
    } else {
        Write-Status "Failed to restart Actual Budget" "ERROR"
    }
}

function Backup-ActualData {
    Write-Status "Creating manual backup of Actual Budget data..."
    
    $backupDir = "./data/backups/actual-manual"
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupFile = "$backupDir/actual-backup-$timestamp.tar.gz"
    
    # Create backup directory
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    
    # Create backup using docker
    try {
        docker run --rm -v homelab_actual_data:/data -v "${PWD}/data/backups/actual-manual:/backup" alpine:latest tar czf "/backup/actual-backup-$timestamp.tar.gz" -C /data .
        Write-Status "Backup created: $backupFile" "SUCCESS"
    }
    catch {
        Write-Status "Failed to create backup: $($_.Exception.Message)" "ERROR"
    }
}

function Restore-ActualData {
    param([string]$BackupFile)
    
    if (-not $BackupFile) {
        Write-Status "Please specify backup file path" "ERROR"
        Write-Host "Usage: setup-actual.ps1 -Action restore -BackupFile <path>"
        return
    }
    
    if (-not (Test-Path $BackupFile)) {
        Write-Status "Backup file not found: $BackupFile" "ERROR"
        return
    }
    
    Write-Status "Restoring Actual Budget data from: $BackupFile" "WARNING"
    Write-Host "This will overwrite existing data. Continue? (y/N): " -NoNewline
    $confirm = Read-Host
    
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Status "Restore cancelled" "WARNING"
        return
    }
    
    # Stop container
    docker-compose stop actual
    
    try {
        # Restore data
        docker run --rm -v homelab_actual_data:/data -v "${PWD}:/backup" alpine:latest tar xzf "/backup/$BackupFile" -C /data
        Write-Status "Data restored successfully" "SUCCESS"
        
        # Start container
        docker-compose start actual
        
        if (Wait-ForActual) {
            Write-Status "Actual Budget restored and started successfully!" "SUCCESS"
        }
    }
    catch {
        Write-Status "Failed to restore data: $($_.Exception.Message)" "ERROR"
        docker-compose start actual
    }
}

# Main execution
switch ($Action.ToLower()) {
    "setup" {
        Setup-Actual
    }
    "status" {
        Show-ActualStatus
    }
    "logs" {
        Show-ActualLogs
    }
    "restart" {
        Restart-Actual
    }
    "health" {
        if (Test-ActualHealth) {
            Write-Status "Actual Budget health check: PASSED" "SUCCESS"
        } else {
            Write-Status "Actual Budget health check: FAILED" "ERROR"
        }
    }
    "backup" {
        Backup-ActualData
    }
    "restore" {
        Restore-ActualData -BackupFile $BackupFile
    }
    default {
        Write-Status "Usage: setup-actual.ps1 [-Action <setup|status|logs|restart|health|backup|restore>]"
        Write-Host "Actions:"
        Write-Host "  setup   - Initial setup and configuration"
        Write-Host "  status  - Show service status and access information"
        Write-Host "  logs    - Show container logs"
        Write-Host "  restart - Restart the service"
        Write-Host "  health  - Check service health"
        Write-Host "  backup  - Create manual backup"
        Write-Host "  restore - Restore from backup file"
    }
}