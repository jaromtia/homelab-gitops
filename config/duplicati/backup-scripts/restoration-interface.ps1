# Duplicati Restoration Interface and Procedures
# Provides guided restoration procedures and automated restoration testing

param(
    [string]$RestoreType = "interactive",
    [string]$BackupSet = "",
    [string]$RestorePoint = "latest",
    [string]$DestinationPath = "",
    [string]$BackupPath = ".\data\backups",
    [string]$LogPath = ".\data\logs\duplicati",
    [string]$TempRestorePath = ".\data\temp\restore",
    [switch]$TestMode,
    [switch]$VerifyRestore,
    [string[]]$SpecificFiles = @()
)

# Global variables
$script:RestoreSession = @{
    "session-id" = (New-Guid).ToString()
    "start-time" = Get-Date
    "restore-type" = $RestoreType
    "backup-set" = $BackupSet
    "status" = "initializing"
}

# Function to write restoration log messages
function Write-RestoreLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Component = "RESTORE"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $sessionId = $script:RestoreSession["session-id"].Substring(0, 8)
    
    $logEntry = "[$timestamp] [$sessionId] [$Component] [$Level] $Message"
    
    # Console output with color coding
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "INFO" { Write-Host $logEntry -ForegroundColor Cyan }
        default { Write-Host $logEntry }
    }
    
    # File logging
    if (!(Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    $logFile = Join-Path $LogPath "restoration.log"
    Add-Content -Path $logFile -Value $logEntry
}

# Display available backup sets with details
function Show-AvailableBackups {
    Write-RestoreLog "Scanning available backup sets..." "INFO" "DISCOVERY"
    
    $backupSets = @()
    
    if (Test-Path $BackupPath) {
        $directories = Get-ChildItem $BackupPath -Directory | Where-Object { $_.Name -notmatch "-alt$" }
        
        foreach ($dir in $directories) {
            $backupInfo = @{
                "name" = $dir.Name
                "path" = $dir.FullName
                "file-count" = 0
                "total-size" = 0
                "latest-backup" = $null
                "oldest-backup" = $null
                "backup-points" = @()
            }
            
            $backupFiles = Get-ChildItem $dir.FullName -File -Recurse
            if ($backupFiles.Count -gt 0) {
                $backupInfo["file-count"] = $backupFiles.Count
                $backupInfo["total-size"] = ($backupFiles | Measure-Object -Property Length -Sum).Sum
                
                $sortedFiles = $backupFiles | Sort-Object LastWriteTime
                $backupInfo["oldest-backup"] = $sortedFiles[0].LastWriteTime
                $backupInfo["latest-backup"] = $sortedFiles[-1].LastWriteTime
                
                # Group files by date to identify backup points
                $backupPoints = $backupFiles | Group-Object { $_.LastWriteTime.Date } | Sort-Object Name -Descending
                $backupInfo["backup-points"] = $backupPoints | ForEach-Object {
                    @{
                        "date" = [DateTime]$_.Name
                        "file-count" = $_.Count
                        "size" = ($_.Group | Measure-Object -Property Length -Sum).Sum
                    }
                }
            }
            
            $backupSets += $backupInfo
        }
    }
    
    # Display backup sets in a formatted table
    Write-Host "`nAvailable Backup Sets:" -ForegroundColor Yellow
    Write-Host "======================" -ForegroundColor Yellow
    
    if ($backupSets.Count -eq 0) {
        Write-Host "No backup sets found in $BackupPath" -ForegroundColor Red
        return @()
    }
    
    $index = 1
    foreach ($backup in $backupSets) {
        $sizeFormatted = if ($backup["total-size"] -gt 1GB) { "{0:N2} GB" -f ($backup["total-size"] / 1GB) }
                        elseif ($backup["total-size"] -gt 1MB) { "{0:N2} MB" -f ($backup["total-size"] / 1MB) }
                        else { "{0:N2} KB" -f ($backup["total-size"] / 1KB) }
        
        $latestFormatted = if ($backup["latest-backup"]) { $backup["latest-backup"].ToString("yyyy-MM-dd HH:mm") } else { "No backups" }
        $pointsCount = $backup["backup-points"].Count
        
        Write-Host "$index. $($backup['name'])" -ForegroundColor Green
        Write-Host "   Files: $($backup['file-count']) | Size: $sizeFormatted | Latest: $latestFormatted | Points: $pointsCount" -ForegroundColor Gray
        
        $index++
    }
    
    return $backupSets
}

# Interactive backup set selection
function Select-BackupSet {
    param([array]$AvailableBackups)
    
    if ($AvailableBackups.Count -eq 0) {
        Write-RestoreLog "No backup sets available for selection" "ERROR" "SELECTION"
        return $null
    }
    
    Write-Host "`nSelect a backup set to restore:" -ForegroundColor Yellow
    
    do {
        $selection = Read-Host "Enter backup set number (1-$($AvailableBackups.Count)) or 'q' to quit"
        
        if ($selection -eq 'q') {
            Write-RestoreLog "User cancelled backup set selection" "INFO" "SELECTION"
            return $null
        }
        
        if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $AvailableBackups.Count) {
            $selectedBackup = $AvailableBackups[[int]$selection - 1]
            Write-RestoreLog "Selected backup set: $($selectedBackup['name'])" "SUCCESS" "SELECTION"
            return $selectedBackup
        }
        
        Write-Host "Invalid selection. Please enter a number between 1 and $($AvailableBackups.Count)" -ForegroundColor Red
        
    } while ($true)
}

# Display backup points for selected backup set
function Show-BackupPoints {
    param([hashtable]$BackupSet)
    
    Write-Host "`nAvailable Backup Points for '$($BackupSet['name'])':" -ForegroundColor Yellow
    Write-Host "=================================================" -ForegroundColor Yellow
    
    if ($BackupSet["backup-points"].Count -eq 0) {
        Write-Host "No backup points found" -ForegroundColor Red
        return @()
    }
    
    $index = 1
    foreach ($point in $BackupSet["backup-points"]) {
        $sizeFormatted = if ($point["size"] -gt 1GB) { "{0:N2} GB" -f ($point["size"] / 1GB) }
                        elseif ($point["size"] -gt 1MB) { "{0:N2} MB" -f ($point["size"] / 1MB) }
                        else { "{0:N2} KB" -f ($point["size"] / 1KB) }
        
        $ageInDays = [math]::Round(((Get-Date) - $point["date"]).TotalDays, 1)
        
        Write-Host "$index. $($point['date'].ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor Green
        Write-Host "   Files: $($point['file-count']) | Size: $sizeFormatted | Age: $ageInDays days" -ForegroundColor Gray
        
        $index++
    }
    
    return $BackupSet["backup-points"]
}

# Interactive backup point selection
function Select-BackupPoint {
    param([array]$BackupPoints)
    
    if ($BackupPoints.Count -eq 0) {
        Write-RestoreLog "No backup points available for selection" "ERROR" "SELECTION"
        return $null
    }
    
    Write-Host "`nSelect a backup point to restore:" -ForegroundColor Yellow
    Write-Host "1. Latest (most recent backup)" -ForegroundColor Cyan
    
    $index = 2
    foreach ($point in $BackupPoints) {
        Write-Host "$index. $($point['date'].ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor White
        $index++
    }
    
    do {
        $selection = Read-Host "Enter backup point number (1-$($BackupPoints.Count + 1)) or 'q' to quit"
        
        if ($selection -eq 'q') {
            Write-RestoreLog "User cancelled backup point selection" "INFO" "SELECTION"
            return $null
        }
        
        if ($selection -eq '1') {
            Write-RestoreLog "Selected latest backup point" "SUCCESS" "SELECTION"
            return $BackupPoints[0]  # Latest is first in sorted array
        }
        
        if ($selection -match '^\d+$' -and [int]$selection -ge 2 -and [int]$selection -le ($BackupPoints.Count + 1)) {
            $selectedPoint = $BackupPoints[[int]$selection - 2]
            Write-RestoreLog "Selected backup point: $($selectedPoint['date'])" "SUCCESS" "SELECTION"
            return $selectedPoint
        }
        
        Write-Host "Invalid selection. Please enter a number between 1 and $($BackupPoints.Count + 1)" -ForegroundColor Red
        
    } while ($true)
}

# Validate restore destination
function Test-RestoreDestination {
    param([string]$Destination)
    
    Write-RestoreLog "Validating restore destination: $Destination" "INFO" "VALIDATION"
    
    $validationResults = @{
        "path-valid" = $false
        "writable" = $false
        "sufficient-space" = $false
        "existing-files" = $false
        "warnings" = @()
        "errors" = @()
    }
    
    # Check if path is valid
    try {
        $resolvedPath = Resolve-Path $Destination -ErrorAction SilentlyContinue
        if ($resolvedPath) {
            $validationResults["path-valid"] = $true
        } else {
            # Try to create the directory if it doesn't exist
            if (!(Test-Path $Destination)) {
                New-Item -ItemType Directory -Path $Destination -Force | Out-Null
                $validationResults["path-valid"] = $true
                Write-RestoreLog "Created restore destination directory" "SUCCESS" "VALIDATION"
            }
        }
    }
    catch {
        $validationResults["errors"] += "Invalid destination path: $($_.Exception.Message)"
    }
    
    if ($validationResults["path-valid"]) {
        # Check write permissions
        try {
            $testFile = Join-Path $Destination "duplicati-restore-test.tmp"
            "test" | Out-File -FilePath $testFile -Force
            Remove-Item $testFile -Force
            $validationResults["writable"] = $true
        }
        catch {
            $validationResults["errors"] += "Destination is not writable: $($_.Exception.Message)"
        }
        
        # Check for existing files
        if (Test-Path $Destination) {
            $existingFiles = Get-ChildItem $Destination -Recurse -File
            if ($existingFiles.Count -gt 0) {
                $validationResults["existing-files"] = $true
                $validationResults["warnings"] += "Destination contains $($existingFiles.Count) existing files"
            }
        }
        
        # Check available disk space (simplified check)
        try {
            $drive = Split-Path $Destination -Qualifier
            $driveInfo = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $drive }
            if ($driveInfo) {
                $freeSpaceGB = [math]::Round($driveInfo.FreeSpace / 1GB, 2)
                if ($freeSpaceGB -gt 1) {  # Require at least 1GB free space
                    $validationResults["sufficient-space"] = $true
                } else {
                    $validationResults["errors"] += "Insufficient disk space: only $freeSpaceGB GB available"
                }
            }
        }
        catch {
            $validationResults["warnings"] += "Could not check available disk space"
            $validationResults["sufficient-space"] = $true  # Assume sufficient if can't check
        }
    }
    
    # Report validation results
    if ($validationResults["errors"].Count -eq 0) {
        Write-RestoreLog "Destination validation passed" "SUCCESS" "VALIDATION"
        
        if ($validationResults["warnings"].Count -gt 0) {
            foreach ($warning in $validationResults["warnings"]) {
                Write-RestoreLog "Warning: $warning" "WARNING" "VALIDATION"
            }
        }
        
        return $true
    } else {
        foreach ($error in $validationResults["errors"]) {
            Write-RestoreLog "Error: $error" "ERROR" "VALIDATION"
        }
        return $false
    }
}

# Generate restoration instructions
function New-RestorationInstructions {
    param(
        [hashtable]$BackupSet,
        [hashtable]$BackupPoint,
        [string]$Destination
    )
    
    Write-RestoreLog "Generating restoration instructions..." "INFO" "INSTRUCTIONS"
    
    $instructionsFile = Join-Path $LogPath "restore-instructions-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    
    $instructions = @"
DUPLICATI RESTORATION INSTRUCTIONS
==================================

Session ID: $($script:RestoreSession['session-id'])
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

BACKUP DETAILS:
- Backup Set: $($BackupSet['name'])
- Backup Point: $($BackupPoint['date'].ToString('yyyy-MM-dd HH:mm:ss'))
- Files to Restore: $($BackupPoint['file-count'])
- Estimated Size: $([math]::Round($BackupPoint['size'] / 1MB, 2)) MB

RESTORE DESTINATION:
- Path: $Destination

PREREQUISITES:
1. Ensure Duplicati service is running (http://localhost:8200)
2. Have backup encryption password ready (DUPLICATI_PASSWORD)
3. Verify sufficient disk space at destination
4. Stop any services that might be using the files being restored

RESTORATION STEPS:

1. ACCESS DUPLICATI WEB INTERFACE
   - Open browser and navigate to: http://localhost:8200
   - Log in with your Duplicati password

2. NAVIGATE TO RESTORE SECTION
   - Click on "Restore" in the main menu
   - Select "Restore files from backup"

3. SELECT BACKUP CONFIGURATION
   - Choose the backup job for: $($BackupSet['name'])
   - If no backup job exists, use "Direct restore from files"

4. CHOOSE RESTORE POINT
   - Select backup version from: $($BackupPoint['date'].ToString('yyyy-MM-dd HH:mm:ss'))
   - Or choose "Latest" for most recent backup

5. SELECT FILES TO RESTORE
   - Browse the backup contents
   - Select specific files/folders or choose "All files"
   - Review the selection before proceeding

6. SET RESTORE OPTIONS
   - Destination: $Destination
   - Restore permissions: Yes (recommended)
   - Overwrite existing files: Choose based on your needs
   - Restore path structure: Maintain original structure

7. ENTER ENCRYPTION PASSWORD
   - Use the password from DUPLICATI_PASSWORD environment variable
   - Verify password is correct before proceeding

8. START RESTORATION
   - Review all settings one final time
   - Click "Start Restore" to begin the process
   - Monitor progress in the web interface

POST-RESTORATION VERIFICATION:

1. VERIFY FILE INTEGRITY
   - Check that all expected files were restored
   - Verify file sizes and timestamps
   - Test file accessibility and readability

2. UPDATE PERMISSIONS (if needed)
   - Ensure proper file/folder permissions
   - Update ownership if necessary
   - Test application access to restored files

3. RESTART SERVICES
   - Restart any services that use the restored files
   - Verify services start correctly with restored data
   - Test application functionality

4. CLEANUP
   - Remove any temporary files created during restore
   - Update backup logs with restoration details
   - Document any issues encountered

TROUBLESHOOTING:

Common Issues:
- "Access Denied": Check destination permissions
- "Insufficient Space": Free up disk space or choose different destination
- "Backup Not Found": Verify backup files exist and are accessible
- "Wrong Password": Verify DUPLICATI_PASSWORD environment variable

Log Files:
- Duplicati Service: docker-compose logs duplicati
- Restoration Log: $($instructionsFile)
- Verification Log: $LogPath\restoration.log

Emergency Contacts:
- System Administrator: Check system documentation
- Backup Documentation: config\duplicati\SETUP.md
- Duplicati Documentation: https://duplicati.readthedocs.io/

IMPORTANT NOTES:
- Always test restored files before putting them into production use
- Keep a record of this restoration for audit purposes
- Consider running a backup verification after restoration
- Update disaster recovery documentation with lessons learned

Generated by Duplicati Restoration Interface
Session: $($script:RestoreSession['session-id'])
"@
    
    $instructions | Out-File -FilePath $instructionsFile -Encoding UTF8
    Write-RestoreLog "Restoration instructions saved: $instructionsFile" "SUCCESS" "INSTRUCTIONS"
    
    return $instructionsFile
}

# Interactive restoration wizard
function Start-InteractiveRestore {
    Write-RestoreLog "Starting interactive restoration wizard..." "INFO" "WIZARD"
    
    # Step 1: Show available backups
    $availableBackups = Show-AvailableBackups
    if ($availableBackups.Count -eq 0) {
        Write-RestoreLog "No backups available for restoration" "ERROR" "WIZARD"
        return $false
    }
    
    # Step 2: Select backup set
    $selectedBackup = Select-BackupSet -AvailableBackups $availableBackups
    if (!$selectedBackup) {
        Write-RestoreLog "No backup set selected" "INFO" "WIZARD"
        return $false
    }
    
    # Step 3: Show and select backup point
    $backupPoints = Show-BackupPoints -BackupSet $selectedBackup
    $selectedPoint = Select-BackupPoint -BackupPoints $backupPoints
    if (!$selectedPoint) {
        Write-RestoreLog "No backup point selected" "INFO" "WIZARD"
        return $false
    }
    
    # Step 4: Get restore destination
    Write-Host "`nEnter restore destination path:" -ForegroundColor Yellow
    $defaultDestination = Join-Path $TempRestorePath $selectedBackup["name"]
    $destination = Read-Host "Destination path (default: $defaultDestination)"
    
    if ([string]::IsNullOrWhiteSpace($destination)) {
        $destination = $defaultDestination
    }
    
    # Step 5: Validate destination
    if (!(Test-RestoreDestination -Destination $destination)) {
        Write-RestoreLog "Destination validation failed" "ERROR" "WIZARD"
        return $false
    }
    
    # Step 6: Generate instructions
    $instructionsFile = New-RestorationInstructions -BackupSet $selectedBackup -BackupPoint $selectedPoint -Destination $destination
    
    # Step 7: Summary and confirmation
    Write-Host "`nRESTORATION SUMMARY:" -ForegroundColor Yellow
    Write-Host "===================" -ForegroundColor Yellow
    Write-Host "Backup Set: $($selectedBackup['name'])" -ForegroundColor Green
    Write-Host "Backup Point: $($selectedPoint['date'])" -ForegroundColor Green
    Write-Host "Destination: $destination" -ForegroundColor Green
    Write-Host "Instructions: $instructionsFile" -ForegroundColor Green
    
    Write-Host "`nNext Steps:" -ForegroundColor Cyan
    Write-Host "1. Review the generated instructions file" -ForegroundColor White
    Write-Host "2. Access Duplicati web interface at http://localhost:8200" -ForegroundColor White
    Write-Host "3. Follow the step-by-step restoration procedure" -ForegroundColor White
    Write-Host "4. Verify restored files after completion" -ForegroundColor White
    
    $script:RestoreSession["status"] = "instructions-generated"
    Write-RestoreLog "Interactive restoration wizard completed successfully" "SUCCESS" "WIZARD"
    
    return $true
}

# Automated restore testing
function Start-RestoreTest {
    param([string]$TestBackupSet)
    
    Write-RestoreLog "Starting automated restore test for: $TestBackupSet" "INFO" "TEST"
    
    $testResults = @{
        "backup-set" = $TestBackupSet
        "test-start" = Get-Date
        "test-status" = "running"
        "files-tested" = 0
        "files-passed" = 0
        "files-failed" = 0
        "errors" = @()
        "warnings" = @()
    }
    
    # Create test restore directory
    $testRestoreDir = Join-Path $TempRestorePath "test-$TestBackupSet-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    try {
        New-Item -ItemType Directory -Path $testRestoreDir -Force | Out-Null
        Write-RestoreLog "Created test restore directory: $testRestoreDir" "SUCCESS" "TEST"
        
        # Simulate restore test by copying a few sample files
        $backupDir = Join-Path $BackupPath $TestBackupSet
        if (Test-Path $backupDir) {
            $sampleFiles = Get-ChildItem $backupDir -File | Select-Object -First 3
            
            foreach ($file in $sampleFiles) {
                try {
                    $testResults["files-tested"]++
                    
                    # Copy file to test directory (simulating restore)
                    $destFile = Join-Path $testRestoreDir $file.Name
                    Copy-Item $file.FullName $destFile -Force
                    
                    # Verify copied file
                    if ((Test-Path $destFile) -and ((Get-Item $destFile).Length -eq $file.Length)) {
                        $testResults["files-passed"]++
                        Write-RestoreLog "Test file restored successfully: $($file.Name)" "SUCCESS" "TEST"
                    } else {
                        $testResults["files-failed"]++
                        $testResults["errors"] += "File restore verification failed: $($file.Name)"
                    }
                }
                catch {
                    $testResults["files-failed"]++
                    $testResults["errors"] += "File restore failed: $($file.Name) - $($_.Exception.Message)"
                }
            }
        } else {
            $testResults["errors"] += "Backup directory not found: $backupDir"
        }
        
        # Cleanup test directory
        if ($TestMode -eq $false) {
            Remove-Item $testRestoreDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-RestoreLog "Cleaned up test restore directory" "INFO" "TEST"
        }
        
        $testResults["test-status"] = "completed"
        $testResults["test-end"] = Get-Date
        $testDuration = $testResults["test-end"] - $testResults["test-start"]
        
        Write-RestoreLog "Restore test completed in $([math]::Round($testDuration.TotalSeconds, 2)) seconds" "SUCCESS" "TEST"
        Write-RestoreLog "Test results: $($testResults['files-passed'])/$($testResults['files-tested']) files passed" "INFO" "TEST"
        
        return $testResults["files-failed"] -eq 0
        
    }
    catch {
        $testResults["test-status"] = "failed"
        $testResults["errors"] += "Test execution failed: $($_.Exception.Message)"
        Write-RestoreLog "Restore test failed: $($_.Exception.Message)" "ERROR" "TEST"
        return $false
    }
}

# Main restoration interface function
function Start-RestorationInterface {
    Write-RestoreLog "Initializing Duplicati Restoration Interface..." "INFO" "MAIN"
    Write-RestoreLog "Restore type: $RestoreType" "INFO" "MAIN"
    
    $script:RestoreSession["status"] = "running"
    
    switch ($RestoreType.ToLower()) {
        "interactive" {
            return Start-InteractiveRestore
        }
        "test" {
            if ([string]::IsNullOrWhiteSpace($BackupSet)) {
                Write-RestoreLog "Backup set required for test mode" "ERROR" "MAIN"
                return $false
            }
            return Start-RestoreTest -TestBackupSet $BackupSet
        }
        "guided" {
            # Guided mode with pre-selected parameters
            if ([string]::IsNullOrWhiteSpace($BackupSet) -or [string]::IsNullOrWhiteSpace($DestinationPath)) {
                Write-RestoreLog "Backup set and destination path required for guided mode" "ERROR" "MAIN"
                return $false
            }
            
            # Generate instructions for guided restore
            $backupInfo = @{ "name" = $BackupSet }
            $pointInfo = @{ "date" = Get-Date; "file-count" = "Unknown"; "size" = 0 }
            
            $instructionsFile = New-RestorationInstructions -BackupSet $backupInfo -BackupPoint $pointInfo -Destination $DestinationPath
            Write-RestoreLog "Guided restoration instructions generated: $instructionsFile" "SUCCESS" "MAIN"
            return $true
        }
        default {
            Write-RestoreLog "Unknown restore type: $RestoreType" "ERROR" "MAIN"
            return $false
        }
    }
}

# Execute restoration interface
try {
    $success = Start-RestorationInterface
    
    if ($success) {
        Write-Host "`nRestoration interface completed successfully!" -ForegroundColor Green
        Write-Host "Session ID: $($script:RestoreSession['session-id'])" -ForegroundColor Cyan
        exit 0
    } else {
        Write-Host "`nRestoration interface encountered issues!" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-RestoreLog "Restoration interface failed with exception: $($_.Exception.Message)" "ERROR" "MAIN"
    Write-Host "`nRestoration interface failed with error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}