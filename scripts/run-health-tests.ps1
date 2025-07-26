#!/usr/bin/env pwsh
# Comprehensive Health and Connectivity Test Runner
# Orchestrates all health and connectivity tests for the homelab infrastructure

param(
    [switch]$Verbose = $false,
    [switch]$SkipTunnel = $false,
    [switch]$SkipExternal = $false,
    [switch]$ContinueOnError = $false,
    [string]$TestSuite = "all",  # all, basic, critical, network, tunnel
    [string]$OutputFormat = "console",  # console, json, html
    [string]$OutputFile = ""
)

# Color functions for output
function Write-Success { param([string]$Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Error { param([string]$Message) Write-Host "✗ $Message" -ForegroundColor Red }
function Write-Warning { param([string]$Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }
function Write-Info { param([string]$Message) Write-Host "ℹ $Message" -ForegroundColor Cyan }
function Write-Log { param([string]$Message) if ($Verbose) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor Gray } }

# Test suite definitions
$TestSuites = @{
    "basic" = @("service-health")
    "critical" = @("service-health", "network-connectivity")
    "network" = @("network-connectivity")
    "tunnel" = @("tunnel-connectivity")
    "all" = @("service-health", "network-connectivity", "tunnel-connectivity")
}

# Test script definitions
$TestScripts = @{
    "service-health" = @{
        Script = "scripts/test-service-health.ps1"
        Description = "Service Health and Container Status"
        Critical = $true
        EstimatedTime = 60
    }
    "network-connectivity" = @{
        Script = "scripts/test-network-connectivity.ps1"
        Description = "Network Configuration and Inter-Service Communication"
        Critical = $true
        EstimatedTime = 90
    }
    "tunnel-connectivity" = @{
        Script = "scripts/test-tunnel-connectivity.ps1"
        Description = "Cloudflare Tunnel Configuration and Routing"
        Critical = $false
        EstimatedTime = 120
    }
}

function Initialize-TestEnvironment {
    Write-Log "Initializing test environment..."
    
    # Check if required scripts exist
    $missingScripts = @()
    foreach ($testName in $TestScripts.Keys) {
        $scriptPath = $TestScripts[$testName].Script
        if (-not (Test-Path $scriptPath)) {
            $missingScripts += $scriptPath
        }
    }
    
    if ($missingScripts.Count -gt 0) {
        Write-Error "Missing test scripts:"
        foreach ($script in $missingScripts) {
            Write-Error "  $script"
        }
        return $false
    }
    
    # Check Docker availability
    try {
        docker info 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Docker is not running or not accessible"
            return $false
        }
    } catch {
        Write-Error "Docker is not available: $($_.Exception.Message)"
        return $false
    }
    
    return $true
}

function Get-TestsToRun {
    param([string]$Suite)
    
    if ($TestSuites.ContainsKey($Suite)) {
        return $TestSuites[$Suite]
    } else {
        Write-Warning "Unknown test suite: $Suite. Using 'all' instead."
        return $TestSuites["all"]
    }
}

function Invoke-TestScript {
    param(
        [string]$TestName,
        [hashtable]$TestConfig
    )
    
    $result = @{
        TestName = $TestName
        Description = $TestConfig.Description
        StartTime = Get-Date
        EndTime = $null
        Duration = 0
        ExitCode = 0
        Success = $false
        Output = ""
        Errors = @()
        Critical = $TestConfig.Critical
    }
    
    Write-Host ""
    Write-Host "Running: $($TestConfig.Description)" -ForegroundColor White
    Write-Host ("=" * 60) -ForegroundColor Gray
    
    try {
        $scriptArgs = @()
        
        # Add common arguments
        if ($Verbose) { $scriptArgs += "-Verbose" }
        if ($SkipExternal) { $scriptArgs += "-SkipExternal" }
        if ($TestName -eq "tunnel-connectivity" -and $SkipTunnel) {
            Write-Warning "Skipping tunnel connectivity tests as requested"
            $result.Success = $true
            $result.EndTime = Get-Date
            $result.Duration = 0
            return $result
        }
        
        # Execute the test script
        $scriptPath = $TestConfig.Script
        Write-Log "Executing: $scriptPath $($scriptArgs -join ' ')"
        
        $output = & $scriptPath @scriptArgs 2>&1
        $result.ExitCode = $LASTEXITCODE
        $result.Output = $output -join "`n"
        $result.Success = ($result.ExitCode -eq 0)
        
        if ($result.Success) {
            Write-Success "Test completed successfully"
        } else {
            Write-Error "Test failed with exit code: $($result.ExitCode)"
            if ($result.Critical -and -not $ContinueOnError) {
                Write-Error "Critical test failed. Stopping test execution."
            }
        }
        
    } catch {
        $result.Errors += $_.Exception.Message
        Write-Error "Test execution failed: $($_.Exception.Message)"
    } finally {
        $result.EndTime = Get-Date
        $result.Duration = ($result.EndTime - $result.StartTime).TotalSeconds
    }
    
    return $result
}

function Format-TestResults {
    param(
        [array]$Results,
        [string]$Format,
        [string]$OutputFile
    )
    
    switch ($Format.ToLower()) {
        "json" {
            $jsonOutput = $Results | ConvertTo-Json -Depth 10
            if ($OutputFile) {
                $jsonOutput | Out-File -FilePath $OutputFile -Encoding UTF8
                Write-Info "Results saved to: $OutputFile"
            } else {
                Write-Host $jsonOutput
            }
        }
        "html" {
            $htmlOutput = Generate-HtmlReport $Results
            if ($OutputFile) {
                $htmlOutput | Out-File -FilePath $OutputFile -Encoding UTF8
                Write-Info "HTML report saved to: $OutputFile"
            } else {
                Write-Host $htmlOutput
            }
        }
        default {
            # Console output is already displayed during execution
            if ($OutputFile) {
                $consoleOutput = Generate-ConsoleReport $Results
                $consoleOutput | Out-File -FilePath $OutputFile -Encoding UTF8
                Write-Info "Console report saved to: $OutputFile"
            }
        }
    }
}

function Generate-ConsoleReport {
    param([array]$Results)
    
    $report = @()
    $report += "=== Homelab Infrastructure Test Results ==="
    $report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $report += ""
    
    $totalTests = $Results.Count
    $passedTests = ($Results | Where-Object { $_.Success }).Count
    $failedTests = $totalTests - $passedTests
    $criticalFailed = ($Results | Where-Object { -not $_.Success -and $_.Critical }).Count
    
    $report += "Summary:"
    $report += "  Total Tests: $totalTests"
    $report += "  Passed: $passedTests"
    $report += "  Failed: $failedTests"
    $report += "  Critical Failures: $criticalFailed"
    $report += ""
    
    foreach ($result in $Results) {
        $status = if ($result.Success) { "PASS" } else { "FAIL" }
        $critical = if ($result.Critical) { " [CRITICAL]" } else { "" }
        
        $report += "$status - $($result.Description)$critical"
        $report += "  Duration: $([math]::Round($result.Duration, 2))s"
        $report += "  Exit Code: $($result.ExitCode)"
        
        if ($result.Errors.Count -gt 0) {
            $report += "  Errors:"
            foreach ($error in $result.Errors) {
                $report += "    - $error"
            }
        }
        $report += ""
    }
    
    return $report -join "`n"
}

function Generate-HtmlReport {
    param([array]$Results)
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Homelab Infrastructure Test Results</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { margin: 20px 0; }
        .test-result { margin: 10px 0; padding: 15px; border-radius: 5px; }
        .pass { background-color: #d4edda; border-left: 5px solid #28a745; }
        .fail { background-color: #f8d7da; border-left: 5px solid #dc3545; }
        .critical { font-weight: bold; }
        .errors { margin-top: 10px; }
        .error-item { color: #dc3545; margin-left: 20px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Homelab Infrastructure Test Results</h1>
        <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    </div>
    
    <div class="summary">
        <h2>Summary</h2>
        <p>Total Tests: $($Results.Count)</p>
        <p>Passed: $(($Results | Where-Object { $_.Success }).Count)</p>
        <p>Failed: $(($Results | Where-Object { -not $_.Success }).Count)</p>
        <p>Critical Failures: $(($Results | Where-Object { -not $_.Success -and $_.Critical }).Count)</p>
    </div>
    
    <div class="results">
        <h2>Test Results</h2>
"@
    
    foreach ($result in $Results) {
        $cssClass = if ($result.Success) { "pass" } else { "fail" }
        $criticalClass = if ($result.Critical) { " critical" } else { "" }
        $status = if ($result.Success) { "PASS" } else { "FAIL" }
        
        $html += @"
        <div class="test-result $cssClass$criticalClass">
            <h3>$status - $($result.Description)</h3>
            <p>Duration: $([math]::Round($result.Duration, 2)) seconds</p>
            <p>Exit Code: $($result.ExitCode)</p>
"@
        
        if ($result.Errors.Count -gt 0) {
            $html += "<div class='errors'><strong>Errors:</strong>"
            foreach ($error in $result.Errors) {
                $html += "<div class='error-item'>• $([System.Web.HttpUtility]::HtmlEncode($error))</div>"
            }
            $html += "</div>"
        }
        
        $html += "</div>"
    }
    
    $html += @"
    </div>
</body>
</html>
"@
    
    return $html
}

# Main execution
Write-Host "=== Homelab Infrastructure Health and Connectivity Testing ===" -ForegroundColor White
Write-Host "Test Suite: $TestSuite" -ForegroundColor Cyan
Write-Host "Output Format: $OutputFormat" -ForegroundColor Cyan
if ($OutputFile) {
    Write-Host "Output File: $OutputFile" -ForegroundColor Cyan
}
Write-Host ""

# Initialize test environment
if (-not (Initialize-TestEnvironment)) {
    Write-Error "Failed to initialize test environment"
    exit 1
}

# Get tests to run
$testsToRun = Get-TestsToRun $TestSuite
Write-Info "Tests to run: $($testsToRun -join ', ')"

# Estimate total time
$estimatedTime = 0
foreach ($testName in $testsToRun) {
    $estimatedTime += $TestScripts[$testName].EstimatedTime
}
Write-Info "Estimated total time: $([math]::Round($estimatedTime / 60, 1)) minutes"

# Run tests
$testResults = @()
$overallSuccess = $true

foreach ($testName in $testsToRun) {
    $testConfig = $TestScripts[$testName]
    $result = Invoke-TestScript $testName $testConfig
    $testResults += $result
    
    if (-not $result.Success) {
        $overallSuccess = $false
        
        if ($result.Critical -and -not $ContinueOnError) {
            Write-Error "Critical test failed. Stopping execution."
            break
        }
    }
}

# Generate final summary
Write-Host ""
Write-Host "=== Final Test Summary ===" -ForegroundColor White

$totalTests = $testResults.Count
$passedTests = ($testResults | Where-Object { $_.Success }).Count
$failedTests = $totalTests - $passedTests
$criticalFailed = ($testResults | Where-Object { -not $_.Success -and $_.Critical }).Count
$totalDuration = ($testResults | Measure-Object Duration -Sum).Sum

Write-Host "Total Tests: $totalTests" -ForegroundColor White
Write-Host "Passed: $passedTests" -ForegroundColor Green
Write-Host "Failed: $failedTests" -ForegroundColor $(if ($failedTests -gt 0) { "Red" } else { "Green" })
Write-Host "Critical Failures: $criticalFailed" -ForegroundColor $(if ($criticalFailed -gt 0) { "Red" } else { "Green" })
Write-Host "Total Duration: $([math]::Round($totalDuration, 1)) seconds" -ForegroundColor White

if ($overallSuccess) {
    Write-Success "All tests completed successfully!"
} else {
    Write-Error "Some tests failed. Please review the results above."
}

# Format and output results
Format-TestResults $testResults $OutputFormat $OutputFile

# Recommendations
Write-Host ""
Write-Host "Recommendations:" -ForegroundColor Cyan

if ($criticalFailed -gt 0) {
    Write-Info "• Fix critical failures before proceeding with deployment"
}

if ($failedTests -gt 0) {
    Write-Info "• Review failed tests and fix underlying issues"
    Write-Info "• Run individual test scripts with -Verbose for detailed output"
}

if ($overallSuccess) {
    Write-Info "• Infrastructure is ready for production use"
    Write-Info "• Consider setting up monitoring alerts for ongoing health checks"
}

exit $(if ($overallSuccess) { 0 } else { 1 })