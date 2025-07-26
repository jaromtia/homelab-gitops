#!/usr/bin/env pwsh
# Backup Integrity Verification Script
# Tests backup system configuration, integrity, and restoration capabilities

param(
    [switch]$Verbose = $false,
    [switch]$SkipRestore = $false,
    [switch]$CreateTestData = $false,
    [string]$BackupJob = "",
    [int]$Timeout = 300
)

# Color functions for output
function Write-Success { param([string]$Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Error { param([string]$Message) Write-Host "✗ $Message" -ForegroundColor Red }
function Write-Warning { param([string]$Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }
function Write-Info { param([string]$Message) Write-Host "ℹ $Message" -ForegroundColor Cyan }
function Write-Log { param([string]$Message) if ($Verbose) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor Gray } }

# Backup job definitions based on the infrastructure
$BackupJobs = @{
    "system-config" = @{
        Description = "System Configuration Files"
        SourcePath = "./config"
        Critical = $true
        ExpectedFiles = @("cloudflared/config.yml", "prometheus/prometheus.yml", "grafana/provisioning")
    }
    "application-data" = @{
        Description = "Application Data Volumes"
        SourcePath = "docker-volumes"
        Critical = $true
        ExpectedFiles = @("grafana_data", "prometheus_data", "portainer_data")
    }
    "user-files" = @{
        Description = "User Files and Documents"
        SourcePath = "./data/files"
        Critical = $false
        ExpectedFiles = @()
    }
    "backup-configs" = @{
        Description = "Duplicati Backup Configurations"
        SourcePath = "duplicati_data"
        Critical = $true
        ExpectedFiles = @()
    }
}

function Test-DuplicatiService {
    Write-Log "Testing Duplicati service availability..."
    $serviceResults = @{
        ContainerRunning = $false
        WebUIAccessible = $false
        APIAccessible = $false
        ConfigurationValid = $false
        Errors = @()
    }
    
    try {
        # Check container status
        $containerInfo = docker-compose ps --format json duplicati 2>$null | ConvertFrom-Json
        
        if ($containerInfo -and $containerInfo.State -eq "running") {
            $serviceResults.ContainerRunning = $true
            
            # Test web UI accessibility
            try {
                $webResponse = Invoke-WebRequest -Uri "http://localhost:8200/" -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop
                $serviceResults.WebUIAccessible = ($webResponse.StatusCode -eq 200)
            } catch {
                $serviceResults.Errors += "Web UI not accessible: $($_.Exception.Message)"
            }
            
            # Test API accessibility
            try {
                $apiResponse = Invoke-WebRequest -Uri "http://localhost:8200/api/v1/serverstate" -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop
                $serviceResults.APIAccessible = ($apiResponse.StatusCode -eq 200)
                
                if ($serviceResults.APIAccessible) {
                    $serverState = $apiResponse.Content | ConvertFrom-Json
                    $serviceResults.ConfigurationValid = ($serverState.ProgramState -eq "Running")
                }
            } catch {
                $serviceResults.Errors += "API not accessible: $($_.Exception.Message)"
            }
        } else {
            $serviceResults.Errors += "Container is not running"
        }
    } catch {
        $serviceResults.Errors += "Error checking service: $($_.Exception.Message)"
    }
    
    return $serviceResults
}

function Get-BackupJobs {
    Write-Log "Retrieving backup jobs from Duplicati..."
    $jobs = @()
    
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8200/api/v1/backups" -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop
        
        if ($response.StatusCode -eq 200) {
            $backupData = $response.Content | ConvertFrom-Json
            
            foreach ($backup in $backupData) {
                $jobs += @{
                    ID = $backup.ID
                    Name = $backup.Name
                    Description = $backup.Description
                    SourcePath = $backup.Sources -join "; "
                    TargetURL = $backup.TargetURL
                    LastRun = $backup.LastRun
                    NextRun = $backup.NextRun
                    IsActive = $backup.IsActive
                }
            }
        }
    } catch {
        Write-Log "Error retrieving backup jobs: $($_.Exception.Message)"
    }
    
    return $jobs
}

function Test-BackupJobConfiguration {
    param([array]$BackupJobs)
    
    Write-Log "Testing backup job configurations..."
    $configResults = @()
    
    foreach ($job in $BackupJobs) {
        $result = @{
            JobName = $job.Name
            JobID = $job.ID
            IsConfigured = $false
            HasValidSource = $false
            HasValidTarget = $false
            IsScheduled = $false
            Errors = @()
        }
        
        # Check if job is properly configured
        $result.IsConfigured = ($job.Name -and $job.SourcePath -and $job.TargetURL)
        
        # Validate source path
        if ($job.SourcePath) {
            # For Docker volumes, we can't directly check paths, but we can verify they're not empty
            $result.HasValidSource = ($job.SourcePath -ne "")
        } else {
            $result.Errors += "No source path configured"
        }
        
        # Validate target
        if ($job.TargetURL) {
            $result.HasValidTarget = ($job.TargetURL -match '^(file|ftp|s3|azure|gcs|b2)://')
            if (-not $result.HasValidTarget) {
                $result.Errors += "Invalid target URL format"
            }
        } else {
            $result.Errors += "No target URL configured"
        }
        
        # Check scheduling
        $result.IsScheduled = ($job.NextRun -and $job.NextRun -ne "")
        
        $configResults += $result
    }
    
    return $configResults
}

function Test-BackupExecution {
    param([string]$JobID)
    
    Write-Log "Testing backup execution for job: $JobID"
    $executionResult = @{
        JobID = $JobID
        ExecutionStarted = $false
        ExecutionCompleted = $false
        ExecutionTime = 0
        FilesBackedUp = 0
        DataSize = 0
        Errors = @()
    }
    
    try {
        # Start backup job
        $startTime = Get-Date
        $startResponse = Invoke-WebRequest -Uri "http://localhost:8200/api/v1/backup/$JobID/start" -Method POST -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop
        
        if ($startResponse.StatusCode -eq 200) {
            $executionResult.ExecutionStarted = $true
            
            # Monitor backup progress
            $maxWaitTime = 300  # 5 minutes
            $checkInterval = 10  # 10 seconds
            $elapsedTime = 0
            
            do {
                Start-Sleep -Seconds $checkInterval
                $elapsedTime += $checkInterval
                
                # Check backup status
                $statusResponse = Invoke-WebRequest -Uri "http://localhost:8200/api/v1/backup/$JobID/status" -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop
                
                if ($statusResponse.StatusCode -eq 200) {
                    $status = $statusResponse.Content | ConvertFrom-Json
                    
                    if ($status.Phase -eq "Backup_Complete") {
                        $executionResult.ExecutionCompleted = $true
                        $executionResult.ExecutionTime = (Get-Date) - $startTime
                        $executionResult.FilesBackedUp = $status.FilesBackedUp
                        $executionResult.DataSize = $status.BackupSize
                        break
                    } elseif ($status.Phase -eq "Backup_Error") {
                        $executionResult.Errors += "Backup failed: $($status.ErrorMessage)"
                        break
                    }
                }
            } while ($elapsedTime -lt $maxWaitTime)
            
            if ($elapsedTime -ge $maxWaitTime -and -not $executionResult.ExecutionCompleted) {
                $executionResult.Errors += "Backup execution timed out after $maxWaitTime seconds"
            }
        } else {
            $executionResult.Errors += "Failed to start backup job"
        }
    } catch {
        $executionResult.Errors += "Error executing backup: $($_.Exception.Message)"
    }
    
    return $executionResult
}

function Test-BackupIntegrity {
    param([string]$JobID)
    
    Write-Log "Testing backup integrity for job: $JobID"
    $integrityResult = @{
        JobID = $JobID
        IntegrityCheckStarted = $false
        IntegrityCheckPassed = $false
        CorruptedFiles = 0
        MissingFiles = 0
        Errors = @()
    }
    
    try {
        # Start integrity verification
        $verifyResponse = Invoke-WebRequest -Uri "http://localhost:8200/api/v1/backup/$JobID/verify" -Method POST -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop
        
        if ($verifyResponse.StatusCode -eq 200) {
            $integrityResult.IntegrityCheckStarted = $true
            
            # Monitor verification progress
            $maxWaitTime = 180  # 3 minutes
            $checkInterval = 10  # 10 seconds
            $elapsedTime = 0
            
            do {
                Start-Sleep -Seconds $checkInterval
                $elapsedTime += $checkInterval
                
                # Check verification status
                $statusResponse = Invoke-WebRequest -Uri "http://localhost:8200/api/v1/backup/$JobID/status" -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop
                
                if ($statusResponse.StatusCode -eq 200) {
                    $status = $statusResponse.Content | ConvertFrom-Json
                    
                    if ($status.Phase -eq "Verify_Complete") {
                        $integrityResult.IntegrityCheckPassed = ($status.CorruptedFiles -eq 0 -and $status.MissingFiles -eq 0)
                        $integrityResult.CorruptedFiles = $status.CorruptedFiles
                        $integrityResult.MissingFiles = $status.MissingFiles
                        break
                    } elseif ($status.Phase -eq "Verify_Error") {
                        $integrityResult.Errors += "Integrity check failed: $($status.ErrorMessage)"
                        break
                    }
                }
            } while ($elapsedTime -lt $maxWaitTime)
            
            if ($elapsedTime -ge $maxWaitTime -and -not $integrityResult.IntegrityCheckPassed) {
                $integrityResult.Errors += "Integrity check timed out after $maxWaitTime seconds"
            }
        } else {
            $integrityResult.Errors += "Failed to start integrity check"
        }
    } catch {
        $integrityResult.Errors += "Error checking integrity: $($_.Exception.Message)"
    }
    
    return $integrityResult
}

function Test-BackupRestoration {
    param([string]$JobID, [string]$RestorePath)
    
    if ($SkipRestore) {
        Write-Warning "Skipping restoration test as requested"
        return @{
            JobID = $JobID
            RestorationSkipped = $true
            RestorationSuccessful = $false
            FilesRestored = 0
            Errors = @()
        }
    }
    
    Write-Log "Testing backup restoration for job: $JobID to path: $RestorePath"
    $restoreResult = @{
        JobID = $JobID
        RestorationSkipped = $false
        RestorationStarted = $false
        RestorationSuccessful = $false
        FilesRestored = 0
        RestorePath = $RestorePath
        Errors = @()
    }
    
    try {
        # Create temporary restore directory
        $tempRestorePath = Join-Path $env:TEMP "duplicati-restore-test-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        New-Item -ItemType Directory -Path $tempRestorePath -Force | Out-Null
        
        # Prepare restore request
        $restoreData = @{
            paths = @("*")
            time = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            restore_path = $tempRestorePath
            overwrite = $true
        } | ConvertTo-Json
        
        # Start restoration
        $restoreResponse = Invoke-WebRequest -Uri "http://localhost:8200/api/v1/backup/$JobID/restore" -Method POST -Body $restoreData -ContentType "application/json" -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop
        
        if ($restoreResponse.StatusCode -eq 200) {
            $restoreResult.RestorationStarted = $true
            
            # Monitor restoration progress
            $maxWaitTime = 300  # 5 minutes
            $checkInterval = 10  # 10 seconds
            $elapsedTime = 0
            
            do {
                Start-Sleep -Seconds $checkInterval
                $elapsedTime += $checkInterval
                
                # Check restoration status
                $statusResponse = Invoke-WebRequest -Uri "http://localhost:8200/api/v1/backup/$JobID/status" -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop
                
                if ($statusResponse.StatusCode -eq 200) {
                    $status = $statusResponse.Content | ConvertFrom-Json
                    
                    if ($status.Phase -eq "Restore_Complete") {
                        $restoreResult.RestorationSuccessful = $true
                        $restoreResult.FilesRestored = $status.FilesRestored
                        
                        # Verify restored files exist
                        if (Test-Path $tempRestorePath) {
                            $restoredFiles = Get-ChildItem -Path $tempRestorePath -Recurse -File
                            if ($restoredFiles.Count -gt 0) {
                                Write-Log "Successfully restored $($restoredFiles.Count) files"
                            } else {
                                $restoreResult.Errors += "No files found in restore directory"
                            }
                        } else {
                            $restoreResult.Errors += "Restore directory was not created"
                        }
                        break
                    } elseif ($status.Phase -eq "Restore_Error") {
                        $restoreResult.Errors += "Restoration failed: $($status.ErrorMessage)"
                        break
                    }
                }
            } while ($elapsedTime -lt $maxWaitTime)
            
            if ($elapsedTime -ge $maxWaitTime -and -not $restoreResult.RestorationSuccessful) {
                $restoreResult.Errors += "Restoration timed out after $maxWaitTime seconds"
            }
        } else {
            $restoreResult.Errors += "Failed to start restoration"
        }
        
        # Cleanup temporary directory
        if (Test-Path $tempRestorePath) {
            Remove-Item -Path $tempRestorePath -Recurse -Force -ErrorAction SilentlyContinue
        }
        
    } catch {
        $restoreResult.Errors += "Error during restoration: $($_.Exception.Message)"
    }
    
    return $restoreResult
}

function Create-TestData {
    Write-Log "Creating test data for backup verification..."
    
    $testDataPath = "./data/test-backup-data"
    
    try {
        # Create test directory
        if (-not (Test-Path $testDataPath)) {
            New-Item -ItemType Directory -Path $testDataPath -Force | Out-Null
        }
        
        # Create test files with known content
        $testFiles = @{
            "test-config.yml" = @"
# Test configuration file for backup verification
test_setting: true
backup_test_timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
test_data:
  - item1
  - item2
  - item3
"@
            "test-data.json" = @{
                test_id = [System.Guid]::NewGuid().ToString()
                created_at = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'
                test_values = @(1, 2, 3, 4, 5)
            } | ConvertTo-Json -Depth 3
            
            "test-log.txt" = @"
$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Test log entry 1
$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Test log entry 2
$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Test log entry 3
"@
        }
        
        foreach ($fileName in $testFiles.Keys) {
            $filePath = Join-Path $testDataPath $fileName
            $testFiles[$fileName] | Out-File -FilePath $filePath -Encoding UTF8
            Write-Log "Created test file: $fileName"
        }
        
        Write-Success "Test data created successfully in: $testDataPath"
        return $true
    } catch {
        Write-Error "Failed to create test data: $($_.Exception.Message)"
        return $false
    }
}

# Main execution
Write-Host "=== Backup Integrity Verification Testing ===" -ForegroundColor White
Write-Host "Testing backup system configuration, integrity, and restoration..." -ForegroundColor Cyan
Write-Host ""

$overallSuccess = $true

# Create test data if requested
if ($CreateTestData) {
    Write-Host "Creating test data..." -ForegroundColor Yellow
    if (-not (Create-TestData)) {
        Write-Error "Failed to create test data"
        $overallSuccess = $false
    }
    Write-Host ""
}

# Test 1: Duplicati Service
Write-Host "1. Testing Duplicati service..." -ForegroundColor Yellow
$serviceResults = Test-DuplicatiService

if ($serviceResults.ContainerRunning) {
    Write-Success "Duplicati container is running"
} else {
    Write-Error "Duplicati container is not running"
    $overallSuccess = $false
}

if ($serviceResults.WebUIAccessible) {
    Write-Success "Web UI is accessible"
} else {
    Write-Error "Web UI is not accessible"
    $overallSuccess = $false
}

if ($serviceResults.APIAccessible) {
    Write-Success "API is accessible"
} else {
    Write-Error "API is not accessible"
    $overallSuccess = $false
}

foreach ($error in $serviceResults.Errors) {
    Write-Error "  $error"
}

Write-Host ""

# Test 2: Backup Jobs Configuration
Write-Host "2. Testing backup job configurations..." -ForegroundColor Yellow
$backupJobs = Get-BackupJobs

if ($backupJobs.Count -gt 0) {
    Write-Success "Found $($backupJobs.Count) backup job(s)"
    
    $configResults = Test-BackupJobConfiguration $backupJobs
    
    foreach ($config in $configResults) {
        if ($config.IsConfigured -and $config.HasValidSource -and $config.HasValidTarget) {
            Write-Success "Job '$($config.JobName)' is properly configured"
        } else {
            Write-Error "Job '$($config.JobName)' has configuration issues"
            foreach ($error in $config.Errors) {
                Write-Error "  $error"
            }
            $overallSuccess = $false
        }
    }
} else {
    Write-Warning "No backup jobs found - this may be expected for a new installation"
}

Write-Host ""

# Test 3: Backup Execution (if jobs exist and specific job requested)
if ($BackupJob -and $backupJobs.Count -gt 0) {
    Write-Host "3. Testing backup execution..." -ForegroundColor Yellow
    
    $targetJob = $backupJobs | Where-Object { $_.Name -eq $BackupJob -or $_.ID -eq $BackupJob }
    
    if ($targetJob) {
        $executionResult = Test-BackupExecution $targetJob.ID
        
        if ($executionResult.ExecutionStarted) {
            Write-Success "Backup execution started"
            
            if ($executionResult.ExecutionCompleted) {
                Write-Success "Backup completed successfully"
                Write-Info "Files backed up: $($executionResult.FilesBackedUp)"
                Write-Info "Data size: $($executionResult.DataSize) bytes"
                Write-Info "Execution time: $($executionResult.ExecutionTime.TotalSeconds) seconds"
            } else {
                Write-Error "Backup execution failed or timed out"
                $overallSuccess = $false
            }
        } else {
            Write-Error "Failed to start backup execution"
            $overallSuccess = $false
        }
        
        foreach ($error in $executionResult.Errors) {
            Write-Error "  $error"
        }
        
        # Test 4: Backup Integrity
        Write-Host ""
        Write-Host "4. Testing backup integrity..." -ForegroundColor Yellow
        
        $integrityResult = Test-BackupIntegrity $targetJob.ID
        
        if ($integrityResult.IntegrityCheckStarted) {
            Write-Success "Integrity check started"
            
            if ($integrityResult.IntegrityCheckPassed) {
                Write-Success "Backup integrity verified"
            } else {
                Write-Error "Backup integrity check failed"
                Write-Error "Corrupted files: $($integrityResult.CorruptedFiles)"
                Write-Error "Missing files: $($integrityResult.MissingFiles)"
                $overallSuccess = $false
            }
        } else {
            Write-Error "Failed to start integrity check"
            $overallSuccess = $false
        }
        
        foreach ($error in $integrityResult.Errors) {
            Write-Error "  $error"
        }
        
        # Test 5: Backup Restoration
        Write-Host ""
        Write-Host "5. Testing backup restoration..." -ForegroundColor Yellow
        
        $restoreResult = Test-BackupRestoration $targetJob.ID "temp-restore"
        
        if ($restoreResult.RestorationSkipped) {
            Write-Warning "Restoration test skipped"
        } elseif ($restoreResult.RestorationStarted) {
            Write-Success "Restoration started"
            
            if ($restoreResult.RestorationSuccessful) {
                Write-Success "Restoration completed successfully"
                Write-Info "Files restored: $($restoreResult.FilesRestored)"
            } else {
                Write-Error "Restoration failed"
                $overallSuccess = $false
            }
        } else {
            Write-Error "Failed to start restoration"
            $overallSuccess = $false
        }
        
        foreach ($error in $restoreResult.Errors) {
            Write-Error "  $error"
        }
    } else {
        Write-Error "Backup job '$BackupJob' not found"
        $overallSuccess = $false
    }
} else {
    Write-Info "Skipping backup execution tests (no specific job requested or no jobs configured)"
}

# Summary
Write-Host ""
Write-Host "=== Backup Integrity Test Summary ===" -ForegroundColor White

if ($overallSuccess) {
    Write-Success "All backup integrity tests passed!"
    Write-Info "Backup system is properly configured and functional."
} else {
    Write-Error "Some backup integrity tests failed."
    Write-Info "Please review the errors above and fix backup configuration issues."
}

# Recommendations
Write-Host ""
Write-Host "Recommendations:" -ForegroundColor Cyan

if ($backupJobs.Count -eq 0) {
    Write-Info "• Configure backup jobs for critical data"
    Write-Info "• Set up automated backup schedules"
}

if (-not $serviceResults.APIAccessible) {
    Write-Info "• Check Duplicati container logs: docker logs duplicati"
    Write-Info "• Verify Duplicati configuration and network connectivity"
}

if ($overallSuccess -and $backupJobs.Count -gt 0) {
    Write-Info "• Consider setting up backup monitoring and alerting"
    Write-Info "• Test restoration procedures regularly"
    Write-Info "• Verify backup retention policies"
}

exit $(if ($overallSuccess) { 0 } else { 1 })