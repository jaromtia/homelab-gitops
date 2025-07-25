# Duplicati Backup Verification Script
# Verifies backup integrity and generates status reports

param(
    [string]$BackupPath = ".\data\backups",
    [string]$LogPath = ".\data\logs\duplicati",
    [switch]$Detailed,
    [switch]$GenerateReport
)

# Function to write log messages
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage }
    }
    
    # Ensure log directory exists
    if (!(Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    $logFile = Join-Path $LogPath "backup-verification.log"
    Add-Content -Path $logFile -Value $logMessage
}

# Test Duplicati service connectivity
function Test-DuplicatiService {
    Write-Log "Testing Duplicati service connectivity..."
    
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8200/api/v1/serverstate" -TimeoutSec 10 -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Log "Duplicati service is responding" "SUCCESS"
            return $true
        }
    }
    catch {
        Write-Log "Duplicati service is not responding: $($_.Exception.Message)" "ERROR"
        return $false
    }
    
    return $false
}

# Verify backup directory structure
function Test-BackupDirectories {
    Write-Log "Verifying backup directory structure..."
    
    $expectedDirs = @(
        "critical-daily",
        "config-daily", 
        "metrics-weekly",
        "system-weekly"
    )
    
    $allDirsExist = $true
    
    foreach ($dir in $expectedDirs) {
        $fullPath = Join-Path $BackupPath $dir
        if (Test-Path $fullPath) {
            $fileCount = (Get-ChildItem $fullPath -File -Recurse).Count
            $dirSize = (Get-ChildItem $fullPath -Recurse | Measure-Object -Property Length -Sum).Sum
            $sizeFormatted = if ($dirSize -gt 1GB) { "{0:N2} GB" -f ($dirSize / 1GB) } 
                           elseif ($dirSize -gt 1MB) { "{0:N2} MB" -f ($dirSize / 1MB) }
                           elseif ($dirSize -gt 1KB) { "{0:N2} KB" -f ($dirSize / 1KB) }
                           else { "$dirSize bytes" }
            
            Write-Log "✓ $dir : $fileCount files, $sizeFormatted" "SUCCESS"
        } else {
            Write-Log "✗ Missing backup directory: $dir" "ERROR"
            $allDirsExist = $false
        }
    }
    
    return $allDirsExist
}

# Check backup file integrity
function Test-BackupFileIntegrity {
    Write-Log "Checking backup file integrity..."
    
    $backupDirs = Get-ChildItem $BackupPath -Directory | Where-Object { $_.Name -notmatch "-alt$" }
    $totalFiles = 0
    $corruptedFiles = 0
    
    foreach ($dir in $backupDirs) {
        Write-Log "Checking files in: $($dir.Name)"
        
        $backupFiles = Get-ChildItem $dir.FullName -File -Recurse | Where-Object { 
            $_.Extension -in @('.dblock', '.dindex', '.dlist', '.zip') 
        }
        
        foreach ($file in $backupFiles) {
            $totalFiles++
            
            # Basic file integrity check
            if ($file.Length -eq 0) {
                Write-Log "✗ Empty file detected: $($file.FullName)" "WARNING"
                $corruptedFiles++
            }
            
            # Check if file is readable
            try {
                $stream = [System.IO.File]::OpenRead($file.FullName)
                $stream.Close()
            }
            catch {
                Write-Log "✗ Unreadable file: $($file.FullName)" "ERROR"
                $corruptedFiles++
            }
        }
    }
    
    if ($corruptedFiles -eq 0) {
        Write-Log "✓ All $totalFiles backup files passed integrity check" "SUCCESS"
        return $true
    } else {
        Write-Log "✗ Found $corruptedFiles corrupted files out of $totalFiles total" "ERROR"
        return $false
    }
}

# Check backup freshness
function Test-BackupFreshness {
    Write-Log "Checking backup freshness..."
    
    $backupSchedules = @{
        "critical-daily" = 1    # Should have backups within 1 day
        "config-daily" = 1      # Should have backups within 1 day
        "metrics-weekly" = 7    # Should have backups within 7 days
        "system-weekly" = 7     # Should have backups within 7 days
    }
    
    $allFresh = $true
    
    foreach ($schedule in $backupSchedules.GetEnumerator()) {
        $backupDir = Join-Path $BackupPath $schedule.Key
        
        if (Test-Path $backupDir) {
            $latestFile = Get-ChildItem $backupDir -File -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            
            if ($latestFile) {
                $daysSinceBackup = (Get-Date) - $latestFile.LastWriteTime
                
                if ($daysSinceBackup.TotalDays -le $schedule.Value) {
                    Write-Log "✓ $($schedule.Key): Latest backup is $([math]::Round($daysSinceBackup.TotalHours, 1)) hours old" "SUCCESS"
                } else {
                    Write-Log "✗ $($schedule.Key): Latest backup is $([math]::Round($daysSinceBackup.TotalDays, 1)) days old (expected within $($schedule.Value) days)" "WARNING"
                    $allFresh = $false
                }
            } else {
                Write-Log "✗ $($schedule.Key): No backup files found" "ERROR"
                $allFresh = $false
            }
        } else {
            Write-Log "✗ $($schedule.Key): Backup directory not found" "ERROR"
            $allFresh = $false
        }
    }
    
    return $allFresh
}

# Generate detailed backup report
function New-BackupReport {
    Write-Log "Generating detailed backup report..."
    
    $reportPath = Join-Path $LogPath "backup-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Duplicati Backup Status Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 10px; border-radius: 5px; }
        .success { color: green; }
        .warning { color: orange; }
        .error { color: red; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .status-ok { background-color: #d4edda; }
        .status-warning { background-color: #fff3cd; }
        .status-error { background-color: #f8d7da; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Duplicati Backup Status Report</h1>
        <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    </div>
    
    <h2>Service Status</h2>
    <table>
        <tr><th>Component</th><th>Status</th><th>Details</th></tr>
"@
    
    # Add service status
    $serviceStatus = Test-DuplicatiService
    $statusClass = if ($serviceStatus) { "status-ok" } else { "status-error" }
    $statusText = if ($serviceStatus) { "✓ Running" } else { "✗ Not responding" }
    
    $html += "<tr class='$statusClass'><td>Duplicati Service</td><td>$statusText</td><td>Web interface on port 8200</td></tr>"
    
    $html += "</table><h2>Backup Directory Status</h2><table><tr><th>Backup Set</th><th>Files</th><th>Size</th><th>Latest Backup</th><th>Status</th></tr>"
    
    # Add backup directory information
    $backupDirs = @("critical-daily", "config-daily", "metrics-weekly", "system-weekly")
    
    foreach ($dir in $backupDirs) {
        $fullPath = Join-Path $BackupPath $dir
        
        if (Test-Path $fullPath) {
            $files = Get-ChildItem $fullPath -File -Recurse
            $fileCount = $files.Count
            $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
            $sizeFormatted = if ($totalSize -gt 1GB) { "{0:N2} GB" -f ($totalSize / 1GB) } 
                           elseif ($totalSize -gt 1MB) { "{0:N2} MB" -f ($totalSize / 1MB) }
                           else { "{0:N2} KB" -f ($totalSize / 1KB) }
            
            $latestFile = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $latestDate = if ($latestFile) { $latestFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm') } else { "No files" }
            
            $daysSinceBackup = if ($latestFile) { ((Get-Date) - $latestFile.LastWriteTime).TotalDays } else { 999 }
            $expectedDays = if ($dir -match "daily") { 1 } else { 7 }
            
            $statusClass = if ($daysSinceBackup -le $expectedDays) { "status-ok" } 
                          elseif ($daysSinceBackup -le ($expectedDays * 2)) { "status-warning" }
                          else { "status-error" }
            
            $statusText = if ($daysSinceBackup -le $expectedDays) { "✓ Current" }
                         elseif ($daysSinceBackup -le ($expectedDays * 2)) { "⚠ Overdue" }
                         else { "✗ Stale" }
            
            $html += "<tr class='$statusClass'><td>$dir</td><td>$fileCount</td><td>$sizeFormatted</td><td>$latestDate</td><td>$statusText</td></tr>"
        } else {
            $html += "<tr class='status-error'><td>$dir</td><td>-</td><td>-</td><td>-</td><td>✗ Missing</td></tr>"
        }
    }
    
    $html += "</table></body></html>"
    
    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Log "Backup report generated: $reportPath" "SUCCESS"
    
    return $reportPath
}

# Main verification function
function Start-BackupVerification {
    Write-Log "Starting Duplicati backup verification..."
    Write-Log "=========================================="
    
    $results = @{
        ServiceStatus = Test-DuplicatiService
        DirectoryStructure = Test-BackupDirectories
        FileIntegrity = Test-BackupFileIntegrity
        BackupFreshness = Test-BackupFreshness
    }
    
    $overallStatus = $results.Values | ForEach-Object { $_ } | Where-Object { $_ -eq $false }
    
    if ($overallStatus.Count -eq 0) {
        Write-Log "✓ All backup verification checks passed" "SUCCESS"
        $exitCode = 0
    } else {
        Write-Log "✗ Some backup verification checks failed" "ERROR"
        $exitCode = 1
    }
    
    if ($GenerateReport) {
        $reportPath = New-BackupReport
        Write-Log "Detailed report available at: $reportPath"
    }
    
    Write-Log "Backup verification completed"
    return $exitCode
}

# Execute verification
try {
    $exitCode = Start-BackupVerification
    
    if ($exitCode -eq 0) {
        Write-Host "`nBackup verification completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "`nBackup verification found issues. Check logs for details." -ForegroundColor Yellow
    }
    
    exit $exitCode
}
catch {
    Write-Log "ERROR: Verification failed with exception: $($_.Exception.Message)" "ERROR"
    Write-Host "`nVerification failed with error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}