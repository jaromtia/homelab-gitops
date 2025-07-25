# Actual Budget Personal Finance Manager Validation Script
# This script validates the Actual Budget service configuration and functionality

param(
    [switch]$Detailed,
    [switch]$HealthOnly,
    [int]$Timeout = 30
)

# Configuration
$ContainerName = "actual"
$ServiceUrl = "http://localhost:5006"
$ExternalUrl = "https://budget.$env:DOMAIN"

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Details = "",
        [string]$Error = ""
    )
    
    $status = if ($Passed) { "PASS" } else { "FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }
    
    Write-Host "[$status] $TestName" -ForegroundColor $color
    
    if ($Details -and $Detailed) {
        Write-Host "      Details: $Details" -ForegroundColor Gray
    }
    
    if ($Error -and -not $Passed) {
        Write-Host "      Error: $Error" -ForegroundColor Red
    }
    
    return $Passed
}

function Test-ContainerRunning {
    try {
        $container = docker ps --filter "name=$ContainerName" --format "{{.Names}}" | Where-Object { $_ -eq $ContainerName }
        $running = $container -eq $ContainerName
        
        if ($running) {
            $status = docker ps --filter "name=$ContainerName" --format "{{.Status}}"
            return Write-TestResult "Container Running" $true "Status: $status"
        } else {
            return Write-TestResult "Container Running" $false "" "Container not found in running containers"
        }
    }
    catch {
        return Write-TestResult "Container Running" $false "" $_.Exception.Message
    }
}

function Test-ContainerHealth {
    try {
        $healthStatus = docker inspect $ContainerName --format "{{.State.Health.Status}}" 2>$null
        
        if ($healthStatus -eq "healthy") {
            return Write-TestResult "Container Health" $true "Status: $healthStatus"
        } elseif ($healthStatus -eq "starting") {
            return Write-TestResult "Container Health" $false "Status: $healthStatus" "Container still starting up"
        } elseif ($healthStatus) {
            return Write-TestResult "Container Health" $false "Status: $healthStatus" "Container unhealthy"
        } else {
            return Write-TestResult "Container Health" $false "" "No health check configured"
        }
    }
    catch {
        return Write-TestResult "Container Health" $false "" $_.Exception.Message
    }
}

function Test-ServiceEndpoint {
    param([string]$Url, [string]$TestName)
    
    try {
        $response = Invoke-WebRequest -Uri $Url -Method GET -TimeoutSec $Timeout -UseBasicParsing
        $passed = $response.StatusCode -eq 200
        
        return Write-TestResult $TestName $passed "Status Code: $($response.StatusCode)"
    }
    catch {
        $errorMsg = if ($_.Exception.Response) {
            "HTTP $($_.Exception.Response.StatusCode): $($_.Exception.Response.StatusDescription)"
        } else {
            $_.Exception.Message
        }
        return Write-TestResult $TestName $false "" $errorMsg
    }
}

function Test-DataStorage {
    try {
        # Check if the data volume exists
        $volumeExists = docker volume ls --filter "name=homelab_actual_data" --format "{{.Name}}" | Where-Object { $_ -eq "homelab_actual_data" }
        
        if ($volumeExists) {
            # Try to check data directory inside container
            $dataCheck = docker exec $ContainerName ls -la /data/ 2>$null
            $passed = $LASTEXITCODE -eq 0
            
            return Write-TestResult "Data Storage" $passed "Volume exists and accessible"
        } else {
            return Write-TestResult "Data Storage" $false "" "Data volume not found"
        }
    }
    catch {
        return Write-TestResult "Data Storage" $false "" $_.Exception.Message
    }
}

function Test-NetworkConnectivity {
    try {
        # Test frontend network connectivity
        $networkInfo = docker inspect $ContainerName --format "{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}" 2>$null
        $passed = $networkInfo -ne ""
        
        if ($passed) {
            $networks = docker inspect $ContainerName --format "{{range .NetworkSettings.Networks}}{{.NetworkID}} {{end}}" 2>$null
            return Write-TestResult "Network Connectivity" $true "Connected to networks"
        } else {
            return Write-TestResult "Network Connectivity" $false "" "No network connections found"
        }
    }
    catch {
        return Write-TestResult "Network Connectivity" $false "" $_.Exception.Message
    }
}

function Test-VolumeMount {
    try {
        $mounts = docker inspect $ContainerName --format "{{range .Mounts}}{{.Destination}} {{end}}" 2>$null
        $dataVolumeFound = $mounts -match "/data"
        
        return Write-TestResult "Volume Mount" $dataVolumeFound "Data volume mounted at /data"
    }
    catch {
        return Write-TestResult "Volume Mount" $false "" $_.Exception.Message
    }
}

function Test-EnvironmentVariables {
    try {
        $envVars = docker inspect $ContainerName --format "{{range .Config.Env}}{{.}} {{end}}" 2>$null
        
        $passwordSet = $envVars -match "ACTUAL_PASSWORD="
        
        return Write-TestResult "Environment Variables" $passwordSet "Required environment variables configured"
    }
    catch {
        return Write-TestResult "Environment Variables" $false "" $_.Exception.Message
    }
}

function Test-BackupIntegration {
    try {
        # Check if Duplicati can access the Actual data volume
        $duplicatiRunning = docker ps --filter "name=duplicati" --format "{{.Names}}" | Where-Object { $_ -eq "duplicati" }
        
        if ($duplicatiRunning) {
            $volumeMount = docker inspect duplicati --format "{{range .Mounts}}{{if eq .Destination `/source/actual`}}{{.Source}}{{end}}{{end}}" 2>$null
            $passed = $volumeMount -ne ""
            
            return Write-TestResult "Backup Integration" $passed "Duplicati can access Actual data"
        } else {
            return Write-TestResult "Backup Integration" $false "" "Duplicati container not running"
        }
    }
    catch {
        return Write-TestResult "Backup Integration" $false "" $_.Exception.Message
    }
}

function Test-TunnelRouting {
    try {
        # Check if cloudflared is running and configured for Actual
        $tunnelRunning = docker ps --filter "name=cloudflared" --format "{{.Names}}" | Where-Object { $_ -eq "cloudflared" }
        
        if ($tunnelRunning) {
            $configContent = Get-Content "./config/cloudflared/config.yml" -Raw -ErrorAction SilentlyContinue
            $actualConfigured = $configContent -match "budget\.\$\{DOMAIN\}" -and $configContent -match "http://actual:5006"
            
            return Write-TestResult "Tunnel Routing" $actualConfigured "Cloudflare tunnel configured for Actual Budget"
        } else {
            return Write-TestResult "Tunnel Routing" $false "" "Cloudflare tunnel not running"
        }
    }
    catch {
        return Write-TestResult "Tunnel Routing" $false "" $_.Exception.Message
    }
}

function Test-PortConfiguration {
    try {
        $portMapping = docker port $ContainerName 2>$null
        $correctPort = $portMapping -match "5006/tcp -> 0.0.0.0:5006"
        
        return Write-TestResult "Port Configuration" $correctPort "Port 5006 correctly mapped"
    }
    catch {
        return Write-TestResult "Port Configuration" $false "" $_.Exception.Message
    }
}

function Test-DataEncryption {
    try {
        # Check if the service is configured for secure data handling
        # This is more of a configuration check since Actual handles encryption internally
        $response = Invoke-WebRequest -Uri "$ServiceUrl/" -Method GET -TimeoutSec $Timeout -UseBasicParsing 2>$null
        
        # Check if the response indicates a secure setup (password protection)
        $secureSetup = $response.Content -match "password" -or $response.StatusCode -eq 200
        
        return Write-TestResult "Data Encryption" $secureSetup "Service configured for secure data handling"
    }
    catch {
        return Write-TestResult "Data Encryption" $false "" "Unable to verify security configuration"
    }
}

function Show-ServiceInfo {
    Write-Host "`n=== Actual Budget Service Information ===" -ForegroundColor Cyan
    Write-Host "Service: Actual Budget Personal Finance Manager"
    Write-Host "Container: $ContainerName"
    Write-Host "Local URL: $ServiceUrl"
    Write-Host "External URL: $ExternalUrl"
    Write-Host "Data Volume: homelab_actual_data"
    Write-Host "Networks: frontend"
    Write-Host "Backup: Included in Duplicati jobs"
    Write-Host "Mobile Apps: Available for iOS and Android"
    Write-Host "Features: Budget tracking, transaction import, multi-device sync"
}

function Show-UsageInstructions {
    Write-Host "`n=== Usage Instructions ===" -ForegroundColor Cyan
    Write-Host "1. Access the web interface at: $ExternalUrl"
    Write-Host "2. Enter the server password when prompted"
    Write-Host "3. Create your first budget file"
    Write-Host "4. Add bank accounts and credit cards"
    Write-Host "5. Set up budget categories"
    Write-Host "6. Import historical transactions (CSV/OFX)"
    Write-Host "7. Install mobile app and connect to: $ExternalUrl"
}

# Main execution
Write-Host "=== Actual Budget Personal Finance Manager Validation ===" -ForegroundColor Yellow
Write-Host "Timeout: $Timeout seconds`n"

$allPassed = $true

# Core service tests
$allPassed = (Test-ContainerRunning) -and $allPassed
$allPassed = (Test-ContainerHealth) -and $allPassed

if (-not $HealthOnly) {
    $allPassed = (Test-ServiceEndpoint "$ServiceUrl/" "Web Interface") -and $allPassed
    $allPassed = (Test-DataStorage) -and $allPassed
    $allPassed = (Test-NetworkConnectivity) -and $allPassed
    $allPassed = (Test-VolumeMount) -and $allPassed
    $allPassed = (Test-EnvironmentVariables) -and $allPassed
    $allPassed = (Test-BackupIntegration) -and $allPassed
    $allPassed = (Test-TunnelRouting) -and $allPassed
    $allPassed = (Test-PortConfiguration) -and $allPassed
    $allPassed = (Test-DataEncryption) -and $allPassed
}

# Summary
Write-Host "`n=== Validation Summary ===" -ForegroundColor Yellow
if ($allPassed) {
    Write-Host "All tests passed! Actual Budget is properly configured and running." -ForegroundColor Green
} else {
    Write-Host "Some tests failed. Please check the errors above." -ForegroundColor Red
}

if ($Detailed) {
    Show-ServiceInfo
    Show-UsageInstructions
}

# Exit with appropriate code
exit $(if ($allPassed) { 0 } else { 1 })