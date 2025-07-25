# Linkding Bookmark Manager Validation Script
# This script validates the Linkding service configuration and functionality

param(
    [switch]$Detailed,
    [switch]$HealthOnly,
    [int]$Timeout = 30
)

# Configuration
$ContainerName = "linkding"
$ServiceUrl = "http://localhost:9091"
$ExternalUrl = "https://bookmarks.$env:DOMAIN"
$HealthEndpoint = "/health"

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

function Test-DatabaseConnection {
    try {
        # Check if the data volume exists and has data
        $volumeExists = docker volume ls --filter "name=homelab_linkding_data" --format "{{.Name}}" | Where-Object { $_ -eq "homelab_linkding_data" }
        
        if ($volumeExists) {
            # Try to check database file existence inside container
            $dbCheck = docker exec $ContainerName ls -la /etc/linkding/data/ 2>$null
            $passed = $LASTEXITCODE -eq 0
            
            return Write-TestResult "Database Connection" $passed "Volume exists and accessible"
        } else {
            return Write-TestResult "Database Connection" $false "" "Data volume not found"
        }
    }
    catch {
        return Write-TestResult "Database Connection" $false "" $_.Exception.Message
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
        $dataVolumeFound = $mounts -match "/etc/linkding/data"
        
        return Write-TestResult "Volume Mount" $dataVolumeFound "Data volume mounted at /etc/linkding/data"
    }
    catch {
        return Write-TestResult "Volume Mount" $false "" $_.Exception.Message
    }
}

function Test-EnvironmentVariables {
    try {
        $envVars = docker inspect $ContainerName --format "{{range .Config.Env}}{{.}} {{end}}" 2>$null
        
        $superuserSet = $envVars -match "LD_SUPERUSER_NAME="
        $passwordSet = $envVars -match "LD_SUPERUSER_PASSWORD="
        
        $passed = $superuserSet -and $passwordSet
        
        return Write-TestResult "Environment Variables" $passed "Required environment variables configured"
    }
    catch {
        return Write-TestResult "Environment Variables" $false "" $_.Exception.Message
    }
}

function Test-BackupIntegration {
    try {
        # Check if Duplicati can access the Linkding data volume
        $duplicatiRunning = docker ps --filter "name=duplicati" --format "{{.Names}}" | Where-Object { $_ -eq "duplicati" }
        
        if ($duplicatiRunning) {
            $volumeMount = docker inspect duplicati --format "{{range .Mounts}}{{if eq .Destination `/source/linkding`}}{{.Source}}{{end}}{{end}}" 2>$null
            $passed = $volumeMount -ne ""
            
            return Write-TestResult "Backup Integration" $passed "Duplicati can access Linkding data"
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
        # Check if cloudflared is running and configured for Linkding
        $tunnelRunning = docker ps --filter "name=cloudflared" --format "{{.Names}}" | Where-Object { $_ -eq "cloudflared" }
        
        if ($tunnelRunning) {
            $configContent = Get-Content "./config/cloudflared/config.yml" -Raw -ErrorAction SilentlyContinue
            $linkdingConfigured = $configContent -match "bookmarks\.\$\{DOMAIN\}" -and $configContent -match "http://linkding:9090"
            
            return Write-TestResult "Tunnel Routing" $linkdingConfigured "Cloudflare tunnel configured for Linkding"
        } else {
            return Write-TestResult "Tunnel Routing" $false "" "Cloudflare tunnel not running"
        }
    }
    catch {
        return Write-TestResult "Tunnel Routing" $false "" $_.Exception.Message
    }
}

function Show-ServiceInfo {
    Write-Host "`n=== Linkding Service Information ===" -ForegroundColor Cyan
    Write-Host "Service: Linkding Bookmark Manager"
    Write-Host "Container: $ContainerName"
    Write-Host "Local URL: $ServiceUrl"
    Write-Host "External URL: $ExternalUrl"
    Write-Host "Health Endpoint: $ServiceUrl$HealthEndpoint"
    Write-Host "Data Volume: homelab_linkding_data"
    Write-Host "Networks: frontend, backend"
    Write-Host "Backup: Included in Duplicati jobs"
}

# Main execution
Write-Host "=== Linkding Bookmark Manager Validation ===" -ForegroundColor Yellow
Write-Host "Timeout: $Timeout seconds`n"

$allPassed = $true

# Core service tests
$allPassed = (Test-ContainerRunning) -and $allPassed
$allPassed = (Test-ContainerHealth) -and $allPassed

if (-not $HealthOnly) {
    $allPassed = (Test-ServiceEndpoint "$ServiceUrl$HealthEndpoint" "Health Endpoint") -and $allPassed
    $allPassed = (Test-ServiceEndpoint "$ServiceUrl/" "Web Interface") -and $allPassed
    $allPassed = (Test-DatabaseConnection) -and $allPassed
    $allPassed = (Test-NetworkConnectivity) -and $allPassed
    $allPassed = (Test-VolumeMount) -and $allPassed
    $allPassed = (Test-EnvironmentVariables) -and $allPassed
    $allPassed = (Test-BackupIntegration) -and $allPassed
    $allPassed = (Test-TunnelRouting) -and $allPassed
}

# Summary
Write-Host "`n=== Validation Summary ===" -ForegroundColor Yellow
if ($allPassed) {
    Write-Host "All tests passed! Linkding is properly configured and running." -ForegroundColor Green
} else {
    Write-Host "Some tests failed. Please check the errors above." -ForegroundColor Red
}

if ($Detailed) {
    Show-ServiceInfo
}

# Exit with appropriate code
exit $(if ($allPassed) { 0 } else { 1 })