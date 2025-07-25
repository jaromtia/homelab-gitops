# Advanced Duplicati Backup Verification System
# Implements comprehensive backup verification with configurable checks and reporting

param(
    [string]$VerificationType = "quick",
    [string]$ConfigPath = ".\config\duplicati\verification-config.json",
    [string]$RetentionConfigPath = ".\config\duplicati\retention-policies.json",
    [string]$BackupPath = ".\data\backups",
    [string]$LogPath = ".\data\logs\duplicati",
    [string]$ReportPath = ".\data\logs\duplicati\reports",
    [switch]$GenerateReport,
    [switch]$SendNotifications,
    [string[]]$TargetBackups = @()
)

# Import required modules
Add-Type -AssemblyName System.Web

# Global variables
$script:VerificationResults = @{}
$script:StartTime = Get-Date
$script:Config = $null
$script:RetentionConfig = $null

# Function to write structured log messages
function Write-StructuredLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Component = "VERIFICATION",
        [hashtable]$Data = @{}
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = @{
        timestamp = $timestamp
        level = $Level
        component = $Component
        message = $Message
        data = $Data
    }
    
    $logJson = $logEntry | ConvertTo-Json -Compress
    
    # Console output with color coding
    switch ($Level) {
        "ERROR" { Write-Host "[$timestamp] [$Component] $Message" -ForegroundColor Red }
        "WARNING" { Write-Host "[$timestamp] [$Component] $Message" -ForegroundColor Yellow }
        "SUCCESS" { Write-Host "[$timestamp] [$Component] $Message" -ForegroundColor Green }
        "INFO" { Write-Host "[$timestamp] [$Component] $Message" -ForegroundColor White }
        default { Write-Host "[$timestamp] [$Component] $Message" }
    }
    
    # File logging
    if (!(Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    $logFile = Join-Path $LogPath "advanced-verification.log"
    Add-Content -Path $logFile -Value $logJson
}

# Load configuration files
function Initialize-Configuration {
    Write-StructuredLog "Loading verification configuration..." "INFO" "CONFIG"
    
    try {
        if (Test-Path $ConfigPath) {
            $script:Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            Write-StructuredLog "Verification configuration loaded successfully" "SUCCESS" "CONFIG"
        } else {
            throw "Verification configuration file not found: $ConfigPath"
        }
        
        if (Test-Path $RetentionConfigPath) {
            $script:RetentionConfig = Get-Content $RetentionConfigPath -Raw | ConvertFrom-Json
            Write-StructuredLog "Retention configuration loaded successfully" "SUCCESS" "CONFIG"
        } else {
            throw "Retention configuration file not found: $RetentionConfigPath"
        }
        
        return $true
    }
    catch {
        Write-StructuredLog "Failed to load configuration: $($_.Exception.Message)" "ERROR" "CONFIG"
        return $false
    }
}

# Test Duplicati service connectivity with detailed diagnostics
function Test-DuplicatiServiceAdvanced {
    Write-StructuredLog "Testing Duplicati service connectivity..." "INFO" "SERVICE"
    
    $serviceTests = @{
        "basic-connectivity" = $false
        "api-response" = $false
        "authentication" = $false
        "backup-jobs" = $false
    }
    
    try {
        # Basic connectivity test
        $response = Invoke-WebRequest -Uri "http://localhost:8200" -TimeoutSec 10 -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            $serviceTests["basic-connectivity"] = $true
            Write-StructuredLog "Basic connectivity test passed" "SUCCESS" "SERVICE"
        }
        
        # API response test
        $apiResponse = Invoke-WebRequest -Uri "http://localhost:8200/api/v1/serverstate" -TimeoutSec 10 -UseBasicParsing
        if ($apiResponse.StatusCode -eq 200) {
            $serviceTests["api-response"] = $true
            $serverState = $apiResponse.Content | ConvertFrom-Json
            Write-StructuredLog "API response test passed - Server state: $($serverState.ProgramState)" "SUCCESS" "SERVICE"
        }
        
        # Test backup jobs endpoint
        try {
            $jobsResponse = Invoke-WebRequest -Uri "http://localhost:8200/api/v1/backups" -TimeoutSec 10 -UseBasicParsing
            if ($jobsResponse.StatusCode -eq 200) {
                $serviceTests["backup-jobs"] = $true
                $jobs = $jobsResponse.Content | ConvertFrom-Json
                Write-StructuredLog "Backup jobs endpoint accessible - Found $($jobs.Count) jobs" "SUCCESS" "SERVICE"
            }
        }
        catch {
            Write-StructuredLog "Backup jobs endpoint test failed: $($_.Exception.Message)" "WARNING" "SERVICE"
        }
        
    }
    catch {
        Write-StructuredLog "Service connectivity test failed: $($_.Exception.Message)" "ERROR" "SERVICE"
    }
    
    $script:VerificationResults["service-tests"] = $serviceTests
    
    $passedTests = ($serviceTests.Values | Where-Object { $_ -eq $true }).Count
    $totalTests = $serviceTests.Count
    
    Write-StructuredLog "Service tests completed: $passedTests/$totalTests passed" "INFO" "SERVICE"
    
    return $passedTests -ge 2  # Require at least basic connectivity and API response
}

# Verify backup file integrity with advanced checks
function Test-BackupIntegrityAdvanced {
    param([string[]]$BackupSets)
    
    Write-StructuredLog "Starting advanced backup integrity verification..." "INFO" "INTEGRITY"
    
    $integrityResults = @{}
    
    foreach ($backupSet in $BackupSets) {
        Write-StructuredLog "Verifying integrity for backup set: $backupSet" "INFO" "INTEGRITY"
        
        $backupPath = Join-Path $BackupPath $backupSet
        $setResults = @{
            "file-count" = 0
            "total-size" = 0
            "corrupted-files" = 0
            "missing-files" = 0
            "integrity-score" = 0
            "last-backup" = $null
            "file-details" = @()
        }
        
        if (Test-Path $backupPath) {
            $backupFiles = Get-ChildItem $backupPath -File -Recurse
            $setResults["file-count"] = $backupFiles.Count
            $setResults["total-size"] = ($backupFiles | Measure-Object -Property Length -Sum).Sum
            
            # Find latest backup
            $latestFile = $backupFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latestFile) {
                $setResults["last-backup"] = $latestFile.LastWriteTime
            }
            
            # Detailed file analysis
            foreach ($file in $backupFiles) {
                $fileDetail = @{
                    "name" = $file.Name
                    "size" = $file.Length
                    "modified" = $file.LastWriteTime
                    "status" = "ok"
                    "issues" = @()
                }
                
                # Check for zero-byte files
                if ($file.Length -eq 0) {
                    $fileDetail["status"] = "corrupted"
                    $fileDetail["issues"] += "zero-byte-file"
                    $setResults["corrupted-files"]++
                }
                
                # Check file readability
                try {
                    $stream = [System.IO.File]::OpenRead($file.FullName)
                    $buffer = New-Object byte[] 1024
                    $bytesRead = $stream.Read($buffer, 0, 1024)
                    $stream.Close()
                    
                    if ($bytesRead -eq 0 -and $file.Length -gt 0) {
                        $fileDetail["status"] = "corrupted"
                        $fileDetail["issues"] += "unreadable"
                        $setResults["corrupted-files"]++
                    }
                }
                catch {
                    $fileDetail["status"] = "corrupted"
                    $fileDetail["issues"] += "access-denied"
                    $setResults["corrupted-files"]++
                }
                
                # Check file extension validity
                $validExtensions = @('.dblock', '.dindex', '.dlist', '.zip', '.json')
                if ($file.Extension -notin $validExtensions) {
                    $fileDetail["status"] = "warning"
                    $fileDetail["issues"] += "unexpected-extension"
                }
                
                $setResults["file-details"] += $fileDetail
            }
            
            # Calculate integrity score
            if ($setResults["file-count"] -gt 0) {
                $healthyFiles = $setResults["file-count"] - $setResults["corrupted-files"]
                $setResults["integrity-score"] = [math]::Round(($healthyFiles / $setResults["file-count"]) * 100, 2)
            }
            
            $sizeFormatted = if ($setResults["total-size"] -gt 1GB) { "{0:N2} GB" -f ($setResults["total-size"] / 1GB) }
                           elseif ($setResults["total-size"] -gt 1MB) { "{0:N2} MB" -f ($setResults["total-size"] / 1MB) }
                           else { "{0:N2} KB" -f ($setResults["total-size"] / 1KB) }
            
            Write-StructuredLog "Backup set $backupSet: $($setResults['file-count']) files, $sizeFormatted, $($setResults['integrity-score'])% integrity" "INFO" "INTEGRITY"
            
        } else {
            Write-StructuredLog "Backup set directory not found: $backupSet" "ERROR" "INTEGRITY"
            $setResults["missing-files"] = 1
        }
        
        $integrityResults[$backupSet] = $setResults
    }
    
    $script:VerificationResults["integrity-results"] = $integrityResults
    
    # Overall integrity assessment
    $overallScore = 0
    $validSets = 0
    
    foreach ($result in $integrityResults.Values) {
        if ($result["file-count"] -gt 0) {
            $overallScore += $result["integrity-score"]
            $validSets++
        }
    }
    
    if ($validSets -gt 0) {
        $overallScore = [math]::Round($overallScore / $validSets, 2)
        Write-StructuredLog "Overall integrity score: $overallScore%" "INFO" "INTEGRITY"
        
        return $overallScore -ge 95  # Require 95% integrity score
    }
    
    return $false
}

# Verify retention policy compliance
function Test-RetentionCompliance {
    param([string[]]$BackupSets)
    
    Write-StructuredLog "Verifying retention policy compliance..." "INFO" "RETENTION"
    
    $retentionResults = @{}
    
    foreach ($backupSet in $BackupSets) {
        Write-StructuredLog "Checking retention compliance for: $backupSet" "INFO" "RETENTION"
        
        $backupPath = Join-Path $BackupPath $backupSet
        $policyKey = $backupSet -replace "-alt$", ""  # Remove alternate suffix for policy lookup
        
        $complianceResult = @{
            "policy-found" = $false
            "compliant" = $false
            "violations" = @()
            "recommendations" = @()
            "file-analysis" = @{}
        }
        
        # Check if retention policy exists
        if ($script:RetentionConfig.'retention-policies'.$policyKey) {
            $policy = $script:RetentionConfig.'retention-policies'.$policyKey
            $complianceResult["policy-found"] = $true
            
            Write-StructuredLog "Found retention policy for $backupSet" "SUCCESS" "RETENTION"
            
            if (Test-Path $backupPath) {
                $backupFiles = Get-ChildItem $backupPath -File -Recurse | Sort-Object LastWriteTime -Descending
                
                # Analyze file age distribution
                $now = Get-Date
                $ageGroups = @{
                    "daily" = @()
                    "weekly" = @()
                    "monthly" = @()
                    "yearly" = @()
                    "expired" = @()
                }
                
                foreach ($file in $backupFiles) {
                    $age = $now - $file.LastWriteTime
                    
                    if ($age.TotalDays -le 7) {
                        $ageGroups["daily"] += $file
                    } elseif ($age.TotalDays -le 30) {
                        $ageGroups["weekly"] += $file
                    } elseif ($age.TotalDays -le 365) {
                        $ageGroups["monthly"] += $file
                    } elseif ($age.TotalDays -le 1825) {  # 5 years
                        $ageGroups["yearly"] += $file
                    } else {
                        $ageGroups["expired"] += $file
                    }
                }
                
                $complianceResult["file-analysis"] = @{
                    "daily-count" = $ageGroups["daily"].Count
                    "weekly-count" = $ageGroups["weekly"].Count
                    "monthly-count" = $ageGroups["monthly"].Count
                    "yearly-count" = $ageGroups["yearly"].Count
                    "expired-count" = $ageGroups["expired"].Count
                }
                
                # Check for expired files that should be cleaned up
                if ($ageGroups["expired"].Count -gt 0) {
                    $complianceResult["violations"] += "expired-files-present"
                    $complianceResult["recommendations"] += "Run cleanup to remove $($ageGroups['expired'].Count) expired files"
                }
                
                # Check storage limits
                $totalSize = ($backupFiles | Measure-Object -Property Length -Sum).Sum
                $maxSize = $policy.'storage-limits'.'max-backup-size'
                
                if ($maxSize -match "(\d+)(GB|MB|KB)") {
                    $sizeValue = [int]$matches[1]
                    $sizeUnit = $matches[2]
                    
                    $maxSizeBytes = switch ($sizeUnit) {
                        "GB" { $sizeValue * 1GB }
                        "MB" { $sizeValue * 1MB }
                        "KB" { $sizeValue * 1KB }
                    }
                    
                    if ($totalSize -gt $maxSizeBytes) {
                        $complianceResult["violations"] += "storage-limit-exceeded"
                        $complianceResult["recommendations"] += "Current size exceeds limit by $([math]::Round(($totalSize - $maxSizeBytes) / 1MB, 2)) MB"
                    }
                }
                
                # Overall compliance assessment
                $complianceResult["compliant"] = $complianceResult["violations"].Count -eq 0
                
            } else {
                $complianceResult["violations"] += "backup-directory-missing"
            }
            
        } else {
            Write-StructuredLog "No retention policy found for $backupSet" "WARNING" "RETENTION"
            $complianceResult["violations"] += "no-policy-defined"
        }
        
        $retentionResults[$backupSet] = $complianceResult
        
        $status = if ($complianceResult["compliant"]) { "COMPLIANT" } else { "NON-COMPLIANT" }
        Write-StructuredLog "Retention compliance for $backupSet : $status" "INFO" "RETENTION"
    }
    
    $script:VerificationResults["retention-results"] = $retentionResults
    
    # Overall compliance
    $compliantSets = ($retentionResults.Values | Where-Object { $_["compliant"] -eq $true }).Count
    $totalSets = $retentionResults.Count
    
    Write-StructuredLog "Retention compliance: $compliantSets/$totalSets backup sets compliant" "INFO" "RETENTION"
    
    return $compliantSets -eq $totalSets
}

# Generate comprehensive verification report
function New-VerificationReport {
    Write-StructuredLog "Generating comprehensive verification report..." "INFO" "REPORT"
    
    if (!(Test-Path $ReportPath)) {
        New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
    }
    
    $reportTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $reportFile = Join-Path $ReportPath "verification-report-$reportTimestamp.html"
    
    $duration = (Get-Date) - $script:StartTime
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Duplicati Advanced Verification Report</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .header h1 { margin: 0; font-size: 28px; }
        .header .subtitle { margin: 10px 0 0 0; opacity: 0.9; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 30px; }
        .summary-card { background: #f8f9fa; padding: 15px; border-radius: 6px; border-left: 4px solid #007bff; }
        .summary-card.success { border-left-color: #28a745; }
        .summary-card.warning { border-left-color: #ffc107; }
        .summary-card.error { border-left-color: #dc3545; }
        .summary-card h3 { margin: 0 0 10px 0; color: #333; font-size: 16px; }
        .summary-card .value { font-size: 24px; font-weight: bold; color: #007bff; }
        .summary-card.success .value { color: #28a745; }
        .summary-card.warning .value { color: #ffc107; }
        .summary-card.error .value { color: #dc3545; }
        .section { margin-bottom: 30px; }
        .section h2 { color: #333; border-bottom: 2px solid #007bff; padding-bottom: 10px; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; font-weight: 600; color: #333; }
        .status-ok { color: #28a745; font-weight: bold; }
        .status-warning { color: #ffc107; font-weight: bold; }
        .status-error { color: #dc3545; font-weight: bold; }
        .progress-bar { width: 100%; height: 20px; background-color: #e9ecef; border-radius: 10px; overflow: hidden; }
        .progress-fill { height: 100%; background: linear-gradient(90deg, #28a745 0%, #20c997 100%); transition: width 0.3s ease; }
        .details { background: #f8f9fa; padding: 15px; border-radius: 6px; margin: 10px 0; }
        .recommendations { background: #fff3cd; border: 1px solid #ffeaa7; padding: 15px; border-radius: 6px; margin: 10px 0; }
        .footer { text-align: center; margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Duplicati Advanced Verification Report</h1>
            <div class="subtitle">
                Verification Type: $VerificationType | 
                Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | 
                Duration: $([math]::Round($duration.TotalMinutes, 2)) minutes
            </div>
        </div>
        
        <div class="summary">
"@
    
    # Add summary cards
    $serviceStatus = if ($script:VerificationResults["service-tests"]) { 
        $passedTests = ($script:VerificationResults["service-tests"].Values | Where-Object { $_ -eq $true }).Count
        $totalTests = $script:VerificationResults["service-tests"].Count
        "$passedTests/$totalTests"
    } else { "N/A" }
    
    $html += "<div class='summary-card success'><h3>Service Status</h3><div class='value'>$serviceStatus</div></div>"
    
    if ($script:VerificationResults["integrity-results"]) {
        $avgIntegrity = 0
        $validSets = 0
        foreach ($result in $script:VerificationResults["integrity-results"].Values) {
            if ($result["file-count"] -gt 0) {
                $avgIntegrity += $result["integrity-score"]
                $validSets++
            }
        }
        if ($validSets -gt 0) {
            $avgIntegrity = [math]::Round($avgIntegrity / $validSets, 1)
        }
        $html += "<div class='summary-card success'><h3>Avg Integrity</h3><div class='value'>$avgIntegrity%</div></div>"
    }
    
    if ($script:VerificationResults["retention-results"]) {
        $compliantSets = ($script:VerificationResults["retention-results"].Values | Where-Object { $_["compliant"] -eq $true }).Count
        $totalSets = $script:VerificationResults["retention-results"].Count
        $html += "<div class='summary-card success'><h3>Retention Compliance</h3><div class='value'>$compliantSets/$totalSets</div></div>"
    }
    
    $html += "</div>"
    
    # Add detailed sections
    if ($script:VerificationResults["integrity-results"]) {
        $html += "<div class='section'><h2>Backup Integrity Analysis</h2><table><tr><th>Backup Set</th><th>Files</th><th>Size</th><th>Integrity Score</th><th>Issues</th></tr>"
        
        foreach ($backupSet in $script:VerificationResults["integrity-results"].Keys) {
            $result = $script:VerificationResults["integrity-results"][$backupSet]
            $sizeFormatted = if ($result["total-size"] -gt 1GB) { "{0:N2} GB" -f ($result["total-size"] / 1GB) }
                           elseif ($result["total-size"] -gt 1MB) { "{0:N2} MB" -f ($result["total-size"] / 1MB) }
                           else { "{0:N2} KB" -f ($result["total-size"] / 1KB) }
            
            $statusClass = if ($result["integrity-score"] -ge 95) { "status-ok" } 
                          elseif ($result["integrity-score"] -ge 80) { "status-warning" }
                          else { "status-error" }
            
            $issues = if ($result["corrupted-files"] -gt 0) { "$($result['corrupted-files']) corrupted" } else { "None" }
            
            $html += "<tr><td>$backupSet</td><td>$($result['file-count'])</td><td>$sizeFormatted</td><td class='$statusClass'>$($result['integrity-score'])%</td><td>$issues</td></tr>"
        }
        
        $html += "</table></div>"
    }
    
    # Add retention compliance section
    if ($script:VerificationResults["retention-results"]) {
        $html += "<div class='section'><h2>Retention Policy Compliance</h2><table><tr><th>Backup Set</th><th>Status</th><th>Daily</th><th>Weekly</th><th>Monthly</th><th>Violations</th></tr>"
        
        foreach ($backupSet in $script:VerificationResults["retention-results"].Keys) {
            $result = $script:VerificationResults["retention-results"][$backupSet]
            $statusClass = if ($result["compliant"]) { "status-ok" } else { "status-error" }
            $statusText = if ($result["compliant"]) { "Compliant" } else { "Non-Compliant" }
            
            $daily = if ($result["file-analysis"]["daily-count"]) { $result["file-analysis"]["daily-count"] } else { "0" }
            $weekly = if ($result["file-analysis"]["weekly-count"]) { $result["file-analysis"]["weekly-count"] } else { "0" }
            $monthly = if ($result["file-analysis"]["monthly-count"]) { $result["file-analysis"]["monthly-count"] } else { "0" }
            $violations = if ($result["violations"].Count -gt 0) { $result["violations"].Count } else { "None" }
            
            $html += "<tr><td>$backupSet</td><td class='$statusClass'>$statusText</td><td>$daily</td><td>$weekly</td><td>$monthly</td><td>$violations</td></tr>"
        }
        
        $html += "</table></div>"
    }
    
    $html += @"
        <div class="footer">
            <p>Report generated by Duplicati Advanced Verification System</p>
            <p>For technical support, check logs at: $LogPath</p>
        </div>
    </div>
</body>
</html>
"@
    
    $html | Out-File -FilePath $reportFile -Encoding UTF8
    Write-StructuredLog "Verification report generated: $reportFile" "SUCCESS" "REPORT"
    
    return $reportFile
}

# Main verification function
function Start-AdvancedVerification {
    Write-StructuredLog "Starting advanced backup verification..." "INFO" "MAIN"
    Write-StructuredLog "Verification type: $VerificationType" "INFO" "MAIN"
    
    # Initialize configuration
    if (!(Initialize-Configuration)) {
        Write-StructuredLog "Configuration initialization failed" "ERROR" "MAIN"
        return $false
    }
    
    # Determine target backup sets
    $backupSets = if ($TargetBackups.Count -gt 0) {
        $TargetBackups
    } else {
        @("critical-daily", "config-daily", "metrics-weekly", "system-weekly")
    }
    
    Write-StructuredLog "Target backup sets: $($backupSets -join ', ')" "INFO" "MAIN"
    
    # Run verification checks based on type
    $verificationPassed = $true
    
    # Service connectivity test
    if (!(Test-DuplicatiServiceAdvanced)) {
        Write-StructuredLog "Service connectivity test failed" "ERROR" "MAIN"
        $verificationPassed = $false
    }
    
    # Integrity verification
    if (!(Test-BackupIntegrityAdvanced -BackupSets $backupSets)) {
        Write-StructuredLog "Backup integrity verification failed" "ERROR" "MAIN"
        $verificationPassed = $false
    }
    
    # Retention compliance check
    if (!(Test-RetentionCompliance -BackupSets $backupSets)) {
        Write-StructuredLog "Retention compliance check failed" "WARNING" "MAIN"
        # Don't fail overall verification for retention issues
    }
    
    # Generate report if requested
    if ($GenerateReport) {
        $reportFile = New-VerificationReport
        Write-StructuredLog "Detailed report available: $reportFile" "INFO" "MAIN"
    }
    
    $duration = (Get-Date) - $script:StartTime
    Write-StructuredLog "Advanced verification completed in $([math]::Round($duration.TotalMinutes, 2)) minutes" "INFO" "MAIN"
    
    return $verificationPassed
}

# Execute verification
try {
    $success = Start-AdvancedVerification
    
    if ($success) {
        Write-Host "`nAdvanced backup verification completed successfully!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "`nAdvanced backup verification found critical issues!" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-StructuredLog "Verification failed with exception: $($_.Exception.Message)" "ERROR" "MAIN"
    Write-Host "`nVerification failed with error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}