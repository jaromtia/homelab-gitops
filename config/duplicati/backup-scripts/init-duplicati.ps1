# Duplicati Initialization Script for Windows
# Initializes Duplicati backup system with proper directory structure and permissions

param(
    [switch]$Force,
    [string]$BackupPath = ".\data\backups",
    [string]$LogPath = ".\data\logs\duplicati"
)

# Function to write log messages
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage
    
    # Ensure log directory exists
    if (!(Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    $logFile = Join-Path $LogPath "duplicati-init.log"
    Add-Content -Path $logFile -Value $logMessage
}

# Create backup directories
function Initialize-BackupDirectories {
    Write-Log "Creating backup directories..."
    
    $backupDirs = @(
        "critical-daily",
        "critical-daily-alt", 
        "config-daily",
        "config-daily-alt",
        "metrics-weekly",
        "metrics-weekly-alt",
        "system-weekly",
        "system-weekly-alt"
    )
    
    foreach ($dir in $backupDirs) {
        $fullPath = Join-Path $BackupPath $dir
        if (!(Test-Path $fullPath)) {
            New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
            Write-Log "Created directory: $fullPath"
        } else {
            Write-Log "Directory already exists: $fullPath"
        }
    }
    
    Write-Log "Backup directories initialized successfully"
}

# Create log directories
function Initialize-LogDirectories {
    Write-Log "Creating log directories..."
    
    if (!(Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
        Write-Log "Created log directory: $LogPath"
    }
    
    # Create subdirectories for different log types
    $logSubDirs = @("backup-jobs", "restore-operations", "maintenance")
    
    foreach ($subDir in $logSubDirs) {
        $fullPath = Join-Path $LogPath $subDir
        if (!(Test-Path $fullPath)) {
            New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
            Write-Log "Created log subdirectory: $fullPath"
        }
    }
    
    Write-Log "Log directories initialized successfully"
}

# Validate Duplicati configuration
function Test-DuplicatiConfiguration {
    Write-Log "Validating Duplicati configuration..."
    
    $configFiles = @(
        "config\duplicati\settings.json",
        "config\duplicati\backup-jobs\critical-data-daily.json",
        "config\duplicati\backup-jobs\config-files-daily.json",
        "config\duplicati\backup-jobs\metrics-weekly.json",
        "config\duplicati\backup-jobs\system-backup-weekly.json"
    )
    
    $allValid = $true
    
    foreach ($configFile in $configFiles) {
        if (Test-Path $configFile) {
            try {
                $content = Get-Content $configFile -Raw | ConvertFrom-Json
                Write-Log "✓ Configuration file valid: $configFile"
            }
            catch {
                Write-Log "✗ Configuration file invalid: $configFile - $($_.Exception.Message)"
                $allValid = $false
            }
        } else {
            Write-Log "✗ Configuration file missing: $configFile"
            $allValid = $false
        }
    }
    
    if ($allValid) {
        Write-Log "All configuration files are valid"
    } else {
        Write-Log "Some configuration files have issues"
    }
    
    return $allValid
}

# Check Docker Compose configuration
function Test-DockerComposeConfiguration {
    Write-Log "Checking Docker Compose configuration for Duplicati..."
    
    if (!(Test-Path "docker-compose.yml")) {
        Write-Log "✗ docker-compose.yml not found"
        return $false
    }
    
    $composeContent = Get-Content "docker-compose.yml" -Raw
    
    if ($composeContent -match "duplicati:") {
        Write-Log "✓ Duplicati service found in docker-compose.yml"
        
        # Check for required volumes
        $requiredVolumes = @(
            "duplicati_data:/config",
            "./data/backups:/backups",
            "./data:/source/data:ro"
        )
        
        $allVolumesFound = $true
        foreach ($volume in $requiredVolumes) {
            if ($composeContent -match [regex]::Escape($volume)) {
                Write-Log "✓ Required volume found: $volume"
            } else {
                Write-Log "✗ Required volume missing: $volume"
                $allVolumesFound = $false
            }
        }
        
        return $allVolumesFound
    } else {
        Write-Log "✗ Duplicati service not found in docker-compose.yml"
        return $false
    }
}

# Generate backup schedule summary
function Show-BackupSchedule {
    Write-Log "Backup Schedule Summary:"
    Write-Log "========================"
    Write-Log "Critical Data Daily:    Every day at 2:00 AM"
    Write-Log "Configuration Daily:    Every day at 2:30 AM"
    Write-Log "Metrics Weekly:         Every Sunday at 3:00 AM"
    Write-Log "System Backup Weekly:   Every Sunday at 4:00 AM"
    Write-Log ""
    Write-Log "Retention Policies:"
    Write-Log "- Daily backups: 1 week daily, 4 weeks weekly, 12 months monthly"
    Write-Log "- Weekly backups: 4 weeks weekly, 12 months monthly, 5 years yearly"
}

# Main initialization function
function Initialize-Duplicati {
    Write-Log "Starting Duplicati backup system initialization..."
    Write-Log "=================================================="
    
    # Initialize directories
    Initialize-BackupDirectories
    Initialize-LogDirectories
    
    # Validate configuration
    $configValid = Test-DuplicatiConfiguration
    $dockerValid = Test-DockerComposeConfiguration
    
    if ($configValid -and $dockerValid) {
        Write-Log "✓ Duplicati initialization completed successfully"
        Show-BackupSchedule
        
        Write-Log ""
        Write-Log "Next Steps:"
        Write-Log "1. Start the Duplicati service: docker-compose up -d duplicati"
        Write-Log "2. Access Duplicati web interface at: http://localhost:8200"
        Write-Log "3. Import backup job configurations"
        Write-Log "4. Set up backup encryption password"
        Write-Log "5. Test backup operations"
        
        return $true
    } else {
        Write-Log "✗ Duplicati initialization completed with errors"
        Write-Log "Please review the configuration issues above before proceeding"
        return $false
    }
}

# Execute initialization
try {
    $success = Initialize-Duplicati
    
    if ($success) {
        Write-Host "`nDuplicati backup system initialized successfully!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "`nDuplicati initialization failed. Check logs for details." -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Log "ERROR: Initialization failed with exception: $($_.Exception.Message)"
    Write-Host "`nInitialization failed with error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}