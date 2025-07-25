# Actual Budget Backup and Restore Script
# This script provides backup and restore functionality for Actual Budget data

param(
    [string]$Action = "backup",
    [string]$BackupPath = "./data/backups/actual",
    [string]$RestoreFile = "",
    [switch]$Compress = $true,
    [switch]$Encrypt = $false,
    [string]$EncryptionKey = ""
)

# Configuration
$ContainerName = "actual"
$DataVolume = "homelab_actual_data"
$ServiceUrl = "http://localhost:5006"

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

function Test-ActualRunning {
    try {
        $response = Invoke-WebRequest -Uri "$ServiceUrl/" -Method GET -TimeoutSec 10 -UseBasicParsing
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Stop-ActualService {
    Write-Status "Stopping Actual Budget service for backup..."
    docker-compose stop actual
    Start-Sleep -Seconds 5
}

function Start-ActualService {
    Write-Status "Starting Actual Budget service..."
    docker-compose start actual
    
    # Wait for service to be ready
    $maxAttempts = 30
    $attempt = 0
    
    do {
        $attempt++
        if (Test-ActualRunning) {
            Write-Status "Actual Budget is ready!" "SUCCESS"
            return $true
        }
        
        Write-Status "Waiting for Actual Budget to start... ($attempt/$maxAttempts)"
        Start-Sleep -Seconds 5
    } while ($attempt -lt $maxAttempts)
    
    Write-Status "Failed to start Actual Budget" "ERROR"
    return $false
}

function Create-Backup {
    Write-Status "Creating backup of Actual Budget data..."
    
    # Create backup directory
    if (-not (Test-Path $BackupPath)) {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        Write-Status "Created backup directory: $BackupPath"
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupName = "actual-backup-$timestamp"
    $backupFile = "$BackupPath/$backupName.tar"
    
    try {
        # Stop service for consistent backup
        $wasRunning = Test-ActualRunning
        if ($wasRunning) {
            Stop-ActualService
        }
        
        # Create backup using docker
        Write-Status "Creating data backup..."
        docker run --rm -v ${DataVolume}:/data -v "${PWD}/${BackupPath}:/backup" alpine:latest tar cf "/backup/$backupName.tar" -C /data .
        
        if ($LASTEXITCODE -eq 0) {
            Write-Status "Backup created successfully: $backupFile" "SUCCESS"
            
            # Compress if requested
            if ($Compress) {
                Write-Status "Compressing backup..."
                docker run --rm -v "${PWD}/${BackupPath}:/backup" alpine:latest gzip "/backup/$backupName.tar"
                $backupFile = "$backupFile.gz"
                Write-Status "Backup compressed: $backupFile" "SUCCESS"
            }
            
            # Encrypt if requested
            if ($Encrypt -and $EncryptionKey) {
                Write-Status "Encrypting backup..."
                # Note: This would require additional encryption tools
                Write-Status "Encryption not implemented in this version" "WARNING"
            }
            
            # Show backup info
            $backupInfo = Get-Item $backupFile -ErrorAction SilentlyContinue
            if ($backupInfo) {
                Write-Status "Backup Details:"
                Write-Host "  File: $($backupInfo.FullName)"
                Write-Host "  Size: $([math]::Round($backupInfo.Length / 1MB, 2)) MB"
                Write-Host "  Created: $($backupInfo.CreationTime)"
            }
        } else {
            Write-Status "Failed to create backup" "ERROR"
        }
        
        # Restart service if it was running
        if ($wasRunning) {
            Start-ActualService
        }
        
    }
    catch {
        Write-Status "Backup failed: $($_.Exception.Message)" "ERROR"
        
        # Ensure service is restarted
        if ($wasRunning) {
            Start-ActualService
        }
    }
}

function Restore-Backup {
    if (-not $RestoreFile) {
        Write-Status "Please specify a backup file to restore" "ERROR"
        Write-Host "Usage: backup-restore.ps1 -Action restore -RestoreFile <path>"
        return
    }
    
    if (-not (Test-Path $RestoreFile)) {
        Write-Status "Backup file not found: $RestoreFile" "ERROR"
        return
    }
    
    Write-Status "Restoring Actual Budget data from: $RestoreFile" "WARNING"
    Write-Host "This will overwrite all existing data. Continue? (y/N): " -NoNewline
    $confirm = Read-Host
    
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Status "Restore cancelled" "WARNING"
        return
    }
    
    try {
        # Stop service
        $wasRunning = Test-ActualRunning
        if ($wasRunning) {
            Stop-ActualService
        }
        
        # Determine if file is compressed
        $isCompressed = $RestoreFile.EndsWith(".gz")
        $tempFile = $RestoreFile
        
        if ($isCompressed) {
            Write-Status "Decompressing backup file..."
            $tempFile = $RestoreFile -replace "\.gz$", ""
            docker run --rm -v "${PWD}:/backup" alpine:latest gunzip -c "/backup/$RestoreFile" > $tempFile
        }
        
        # Restore data
        Write-Status "Restoring data..."
        docker run --rm -v ${DataVolume}:/data -v "${PWD}:/backup" alpine:latest tar xf "/backup/$tempFile" -C /data
        
        if ($LASTEXITCODE -eq 0) {
            Write-Status "Data restored successfully" "SUCCESS"
            
            # Clean up temp file if created
            if ($isCompressed -and (Test-Path $tempFile)) {
                Remove-Item $tempFile -Force
            }
            
            # Start service
            if ($wasRunning) {
                if (Start-ActualService) {
                    Write-Status "Actual Budget restored and started successfully!" "SUCCESS"
                } else {
                    Write-Status "Data restored but service failed to start" "WARNING"
                }
            }
        } else {
            Write-Status "Failed to restore data" "ERROR"
        }
        
    }
    catch {
        Write-Status "Restore failed: $($_.Exception.Message)" "ERROR"
        
        # Ensure service is restarted
        if ($wasRunning) {
            Start-ActualService
        }
    }
}

function List-Backups {
    Write-Status "Available backups in $BackupPath:"
    
    if (-not (Test-Path $BackupPath)) {
        Write-Status "Backup directory does not exist: $BackupPath" "WARNING"
        return
    }
    
    $backups = Get-ChildItem $BackupPath -Filter "actual-backup-*" | Sort-Object CreationTime -Descending
    
    if ($backups.Count -eq 0) {
        Write-Status "No backups found" "WARNING"
        return
    }
    
    Write-Host "`nBackup Files:" -ForegroundColor Cyan
    Write-Host "=============" -ForegroundColor Cyan
    
    foreach ($backup in $backups) {
        $size = [math]::Round($backup.Length / 1MB, 2)
        $age = (Get-Date) - $backup.CreationTime
        $ageStr = if ($age.Days -gt 0) { "$($age.Days)d" } elseif ($age.Hours -gt 0) { "$($age.Hours)h" } else { "$($age.Minutes)m" }
        
        Write-Host "  $($backup.Name)" -ForegroundColor White
        Write-Host "    Size: $size MB, Age: $ageStr, Created: $($backup.CreationTime)" -ForegroundColor Gray
    }
}

function Verify-Backup {
    if (-not $RestoreFile) {
        Write-Status "Please specify a backup file to verify" "ERROR"
        Write-Host "Usage: backup-restore.ps1 -Action verify -RestoreFile <path>"
        return
    }
    
    if (-not (Test-Path $RestoreFile)) {
        Write-Status "Backup file not found: $RestoreFile" "ERROR"
        return
    }
    
    Write-Status "Verifying backup file: $RestoreFile"
    
    try {
        # Test if the backup file is valid
        $isCompressed = $RestoreFile.EndsWith(".gz")
        
        if ($isCompressed) {
            # Test gzip file
            docker run --rm -v "${PWD}:/backup" alpine:latest gzip -t "/backup/$RestoreFile"
        } else {
            # Test tar file
            docker run --rm -v "${PWD}:/backup" alpine:latest tar tf "/backup/$RestoreFile" > $null
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Status "Backup file is valid" "SUCCESS"
            
            # Show backup contents
            Write-Status "Backup contents:"
            if ($isCompressed) {
                docker run --rm -v "${PWD}:/backup" alpine:latest sh -c "gunzip -c '/backup/$RestoreFile' | tar tf -"
            } else {
                docker run --rm -v "${PWD}:/backup" alpine:latest tar tf "/backup/$RestoreFile"
            }
        } else {
            Write-Status "Backup file is corrupted or invalid" "ERROR"
        }
    }
    catch {
        Write-Status "Verification failed: $($_.Exception.Message)" "ERROR"
    }
}

# Main execution
switch ($Action.ToLower()) {
    "backup" {
        Create-Backup
    }
    "restore" {
        Restore-Backup
    }
    "list" {
        List-Backups
    }
    "verify" {
        Verify-Backup
    }
    default {
        Write-Status "Usage: backup-restore.ps1 [-Action <backup|restore|list|verify>]"
        Write-Host "Actions:"
        Write-Host "  backup  - Create a backup of Actual Budget data"
        Write-Host "  restore - Restore from a backup file"
        Write-Host "  list    - List available backup files"
        Write-Host "  verify  - Verify backup file integrity"
        Write-Host ""
        Write-Host "Parameters:"
        Write-Host "  -BackupPath <path>     - Backup directory (default: ./data/backups/actual)"
        Write-Host "  -RestoreFile <file>    - Backup file to restore/verify"
        Write-Host "  -Compress              - Compress backup files (default: true)"
        Write-Host "  -Encrypt               - Encrypt backup files (not implemented)"
        Write-Host "  -EncryptionKey <key>   - Encryption key for backup files"
    }
}