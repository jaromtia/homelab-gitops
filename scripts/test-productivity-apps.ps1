# Productivity Applications Test Script
# This script tests both Linkding and Actual Budget services

param(
    [switch]$Detailed,
    [switch]$SkipLinkding,
    [switch]$SkipActual,
    [int]$Timeout = 30
)

# Configuration
$LinkdingContainer = "linkding"
$ActualContainer = "actual"
$LinkdingUrl = "http://localhost:9091"
$ActualUrl = "http://localhost:5006"
$ExternalDomain = $env:DOMAIN

function Write-TestResult {
    param(
        [string]$Service,
        [string]$TestName,
        [bool]$Passed,
        [string]$Details = "",
        [string]$Error = ""
    )
    
    $status = if ($Passed) { "PASS" } else { "FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }
    
    Write-Host "[$Service] [$status] $TestName" -ForegroundColor $color
    
    if ($Details -and $Detailed) {
        Write-Host "        Details: $Details" -ForegroundColor Gray
    }
    
    if ($Error -and -not $Passed) {
        Write-Host "        Error: $Error" -ForegroundColor Red
    }
    
    return $Passed
}

function Test-ServiceHealth {
    param(
        [string]$Service,
        [string]$Container,
        [string]$Url,
        [string]$HealthPath = ""
    )
    
    $allPassed = $true
    
    # Test container running
    try {
        $containerRunning = docker ps --filter "name=$Container" --format "{{.Names}}" | Where-Object { $_ -eq $Container }
        $running = $containerRunning -eq $Container
        $allPassed = (Write-TestResult $Service "Container Running" $running) -and $allPassed
    }
    catch {
        $allPassed = (Write-TestResult $Service "Container Running" $false "" $_.Exception.Message) -and $allPassed
    }
    
    # Test container health
    try {
        $healthStatus = docker inspect $Container --format "{{.State.Health.Status}}" 2>$null
        $healthy = $healthStatus -eq "healthy"
        $allPassed = (Write-TestResult $Service "Container Health" $healthy "Status: $healthStatus") -and $allPassed
    }
    catch {
        $allPassed = (Write-TestResult $Service "Container Health" $false "" $_.Exception.Message) -and $allPassed
    }
    
    # Test service endpoint
    try {
        $testUrl = if ($HealthPath) { "$Url$HealthPath" } else { $Url }
        $response = Invoke-WebRequest -Uri $testUrl -Method GET -TimeoutSec $Timeout -UseBasicParsing
        $accessible = $response.StatusCode -eq 200
        $allPassed = (Write-TestResult $Service "Service Endpoint" $accessible "Status: $($response.StatusCode)") -and $allPassed
    }
    catch {
        $errorMsg = if ($_.Exception.Response) {
            "HTTP $($_.Exception.Response.StatusCode)"
        } else {
            $_.Exception.Message
        }
        $allPassed = (Write-TestResult $Service "Service Endpoint" $false "" $errorMsg) -and $allPassed
    }
    
    # Test data volume
    try {
        $volumeName = "homelab_$($Container.ToLower())_data"
        $volumeExists = docker volume ls --filter "name=$volumeName" --format "{{.Name}}" | Where-Object { $_ -eq $volumeName }
        $hasVolume = $volumeExists -eq $volumeName
        $allPassed = (Write-TestResult $Service "Data Volume" $hasVolume "Volume: $volumeName") -and $allPassed
    }
    catch {
        $allPassed = (Write-TestResult $Service "Data Volume" $false "" $_.Exception.Message) -and $allPassed
    }
    
    # Test network connectivity
    try {
        $networkInfo = docker inspect $Container --format "{{range .NetworkSettings.Networks}}{{.NetworkID}} {{end}}" 2>$null
        $hasNetwork = $networkInfo -ne ""
        $allPassed = (Write-TestResult $Service "Network Connectivity" $hasNetwork) -and $allPassed
    }
    catch {
        $allPassed = (Write-TestResult $Service "Network Connectivity" $false "" $_.Exception.Message) -and $allPassed
    }
    
    return $allPassed
}

function Test-TunnelConfiguration {
    param([string]$Service, [string]$Hostname, [string]$TargetService)
    
    try {
        $configPath = "./config/cloudflared/config.yml"
        if (Test-Path $configPath) {
            $configContent = Get-Content $configPath -Raw
            $hostnameConfigured = $configContent -match "$Hostname\.\$\{DOMAIN\}"
            $serviceConfigured = $configContent -match "http://$TargetService"
            $configured = $hostnameConfigured -and $serviceConfigured
            
            return Write-TestResult $Service "Tunnel Configuration" $configured "Hostname: $Hostname.`${DOMAIN}"
        } else {
            return Write-TestResult $Service "Tunnel Configuration" $false "" "Config file not found"
        }
    }
    catch {
        return Write-TestResult $Service "Tunnel Configuration" $false "" $_.Exception.Message
    }
}

function Test-BackupIntegration {
    param([string]$Service, [string]$Container)
    
    try {
        $duplicatiRunning = docker ps --filter "name=duplicati" --format "{{.Names}}" | Where-Object { $_ -eq "duplicati" }
        
        if ($duplicatiRunning) {
            $volumeMount = docker inspect duplicati --format "{{range .Mounts}}{{if eq .Destination `/source/$Container`}}{{.Source}}{{end}}{{end}}" 2>$null
            $integrated = $volumeMount -ne ""
            
            return Write-TestResult $Service "Backup Integration" $integrated "Duplicati configured"
        } else {
            return Write-TestResult $Service "Backup Integration" $false "" "Duplicati not running"
        }
    }
    catch {
        return Write-TestResult $Service "Backup Integration" $false "" $_.Exception.Message
    }
}

function Test-DashboardIntegration {
    param([string]$Service, [string]$ServiceName)
    
    try {
        $dashyConfigPath = "./config/dashy/conf-simple.yml"
        if (Test-Path $dashyConfigPath) {
            $configContent = Get-Content $dashyConfigPath -Raw
            $serviceConfigured = $configContent -match $ServiceName
            
            return Write-TestResult $Service "Dashboard Integration" $serviceConfigured "Listed in Dashy"
        } else {
            return Write-TestResult $Service "Dashboard Integration" $false "" "Dashy config not found"
        }
    }
    catch {
        return Write-TestResult $Service "Dashboard Integration" $false "" $_.Exception.Message
    }
}

function Show-ServiceSummary {
    param([string]$Service, [string]$Container, [string]$LocalUrl, [string]$ExternalUrl)
    
    Write-Host "`n=== $Service Service Summary ===" -ForegroundColor Cyan
    Write-Host "Container: $Container"
    Write-Host "Local URL: $LocalUrl"
    Write-Host "External URL: $ExternalUrl"
    
    # Show container status
    $containerStatus = docker ps --filter "name=$Container" --format "{{.Status}}" 2>$null
    if ($containerStatus) {
        Write-Host "Status: $containerStatus" -ForegroundColor Green
    } else {
        Write-Host "Status: Not running" -ForegroundColor Red
    }
    
    # Show volume info
    $volumeName = "homelab_$($Container.ToLower())_data"
    $volumeInfo = docker volume inspect $volumeName --format "{{.Mountpoint}}" 2>$null
    if ($volumeInfo) {
        Write-Host "Data Volume: $volumeName"
        if ($Detailed) {
            Write-Host "Mount Point: $volumeInfo"
        }
    }
}

# Main execution
Write-Host "=== Productivity Applications Test Suite ===" -ForegroundColor Yellow
Write-Host "Testing Linkding and Actual Budget services`n"

$overallPassed = $true

# Test Linkding
if (-not $SkipLinkding) {
    Write-Host "=== Testing Linkding Bookmark Manager ===" -ForegroundColor Yellow
    
    $linkdingPassed = $true
    $linkdingPassed = (Test-ServiceHealth "Linkding" $LinkdingContainer $LinkdingUrl "/health") -and $linkdingPassed
    $linkdingPassed = (Test-TunnelConfiguration "Linkding" "bookmarks" "linkding:9090") -and $linkdingPassed
    $linkdingPassed = (Test-BackupIntegration "Linkding" "linkding") -and $linkdingPassed
    $linkdingPassed = (Test-DashboardIntegration "Linkding" "Linkding") -and $linkdingPassed
    
    $overallPassed = $linkdingPassed -and $overallPassed
    
    if ($Detailed) {
        Show-ServiceSummary "Linkding" $LinkdingContainer $LinkdingUrl "https://bookmarks.$ExternalDomain"
    }
}

# Test Actual Budget
if (-not $SkipActual) {
    Write-Host "`n=== Testing Actual Budget Personal Finance Manager ===" -ForegroundColor Yellow
    
    $actualPassed = $true
    $actualPassed = (Test-ServiceHealth "Actual" $ActualContainer $ActualUrl) -and $actualPassed
    $actualPassed = (Test-TunnelConfiguration "Actual" "budget" "actual:5006") -and $actualPassed
    $actualPassed = (Test-BackupIntegration "Actual" "actual") -and $actualPassed
    $actualPassed = (Test-DashboardIntegration "Actual" "Actual Budget") -and $actualPassed
    
    $overallPassed = $actualPassed -and $overallPassed
    
    if ($Detailed) {
        Show-ServiceSummary "Actual Budget" $ActualContainer $ActualUrl "https://budget.$ExternalDomain"
    }
}

# Overall summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Yellow
if ($overallPassed) {
    Write-Host "All productivity applications are properly configured and running!" -ForegroundColor Green
    
    Write-Host "`nAccess URLs:" -ForegroundColor Cyan
    if (-not $SkipLinkding) {
        Write-Host "  Linkding (Local):    $LinkdingUrl"
        Write-Host "  Linkding (External): https://bookmarks.$ExternalDomain"
    }
    if (-not $SkipActual) {
        Write-Host "  Actual (Local):      $ActualUrl"
        Write-Host "  Actual (External):   https://budget.$ExternalDomain"
    }
    
    Write-Host "`nNext Steps:" -ForegroundColor Cyan
    Write-Host "  1. Access services via external URLs"
    Write-Host "  2. Configure initial settings and user accounts"
    Write-Host "  3. Import existing data if needed"
    Write-Host "  4. Set up mobile apps for on-the-go access"
    Write-Host "  5. Verify backup jobs are running correctly"
    
} else {
    Write-Host "Some tests failed. Please check the errors above and resolve issues." -ForegroundColor Red
}

# Exit with appropriate code
exit $(if ($overallPassed) { 0 } else { 1 })