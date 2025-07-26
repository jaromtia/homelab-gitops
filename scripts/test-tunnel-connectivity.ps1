#!/usr/bin/env pwsh
# Cloudflare Tunnel Connectivity Testing Script
# Tests tunnel configuration, connectivity, and service routing

param(
    [switch]$Verbose = $false,
    [switch]$SkipExternal = $false,
    [string]$Domain = "",
    [int]$Timeout = 30
)

# Color functions for output
function Write-Success { param([string]$Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Error { param([string]$Message) Write-Host "✗ $Message" -ForegroundColor Red }
function Write-Warning { param([string]$Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }
function Write-Info { param([string]$Message) Write-Host "ℹ $Message" -ForegroundColor Cyan }
function Write-Log { param([string]$Message) if ($Verbose) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor Gray } }

# Load environment variables
function Load-Environment {
    $envFile = ".env"
    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            if ($_ -match '^([^#][^=]+)=(.*)$') {
                [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
            }
        }
    }
}

# Service routing configuration - maps services to their expected tunnel routes
$TunnelServices = @{
    "homer" = @{
        Subdomain = "dashboard"
        Port = 8080
        Path = "/"
        Critical = $false
        Description = "Homer Dashboard"
    }
    "dashy" = @{
        Subdomain = "dashy"
        Port = 80
        Path = "/"
        Critical = $false
        Description = "Dashy Dashboard"
    }
    "grafana" = @{
        Subdomain = "grafana"
        Port = 3000
        Path = "/api/health"
        Critical = $true
        Description = "Grafana Monitoring"
    }
    "prometheus" = @{
        Subdomain = "prometheus"
        Port = 9090
        Path = "/-/healthy"
        Critical = $true
        Description = "Prometheus Metrics"
    }
    "portainer" = @{
        Subdomain = "portainer"
        Port = 9000
        Path = "/api/status"
        Critical = $true
        Description = "Portainer Management"
    }
    "filebrowser" = @{
        Subdomain = "files"
        Port = 80
        Path = "/health"
        Critical = $false
        Description = "File Browser"
    }
    "linkding" = @{
        Subdomain = "bookmarks"
        Port = 9090
        Path = "/health"
        Critical = $false
        Description = "Linkding Bookmarks"
    }
    "actual" = @{
        Subdomain = "budget"
        Port = 5006
        Path = "/"
        Critical = $false
        Description = "Actual Budget"
    }
    "duplicati" = @{
        Subdomain = "backup"
        Port = 8200
        Path = "/"
        Critical = $true
        Description = "Duplicati Backup"
    }
}

function Test-TunnelConfiguration {
    Write-Log "Testing Cloudflare tunnel configuration..."
    $configResults = @{
        ConfigFileExists = $false
        CredentialsExist = $false
        TunnelID = ""
        ConfigValid = $false
        IngressRules = @()
        Errors = @()
    }
    
    # Check configuration file
    $configFile = "config/cloudflared/config.yml"
    if (Test-Path $configFile) {
        $configResults.ConfigFileExists = $true
        
        try {
            $configContent = Get-Content $configFile -Raw
            
            # Extract tunnel ID
            if ($configContent -match 'tunnel:\s*([a-f0-9-]+)') {
                $configResults.TunnelID = $matches[1]
                
                if ($configResults.TunnelID -ne "YOUR_TUNNEL_ID") {
                    Write-Log "Found tunnel ID: $($configResults.TunnelID)"
                } else {
                    $configResults.Errors += "Tunnel ID is still placeholder value"
                }
            } else {
                $configResults.Errors += "Tunnel ID not found in configuration"
            }
            
            # Parse ingress rules
            $ingressSection = $false
            foreach ($line in ($configContent -split "`n")) {
                $line = $line.Trim()
                
                if ($line -eq "ingress:") {
                    $ingressSection = $true
                    continue
                }
                
                if ($ingressSection -and $line -match '^\s*-\s*hostname:\s*(.+)') {
                    $hostname = $matches[1].Trim()
                    $configResults.IngressRules += $hostname
                }
            }
            
            $configResults.ConfigValid = ($configResults.Errors.Count -eq 0)
        } catch {
            $configResults.Errors += "Error parsing configuration: $($_.Exception.Message)"
        }
    } else {
        $configResults.Errors += "Configuration file not found: $configFile"
    }
    
    # Check credentials file
    $credentialsFile = "config/cloudflared/credentials.json"
    if (Test-Path $credentialsFile) {
        $configResults.CredentialsExist = $true
        
        try {
            $credentialsContent = Get-Content $credentialsFile -Raw | ConvertFrom-Json
            if (-not $credentialsContent.AccountTag -or -not $credentialsContent.TunnelSecret) {
                $configResults.Errors += "Credentials file is missing required fields"
            }
        } catch {
            $configResults.Errors += "Error parsing credentials file: $($_.Exception.Message)"
        }
    } else {
        $configResults.Errors += "Credentials file not found: $credentialsFile"
    }
    
    return $configResults
}

function Test-TunnelContainer {
    Write-Log "Testing Cloudflare tunnel container..."
    $containerResults = @{
        ContainerRunning = $false
        ContainerHealthy = $false
        MetricsAccessible = $false
        LogsAvailable = $false
        Errors = @()
    }
    
    try {
        # Check container status
        $containerInfo = docker-compose ps --format json cloudflared 2>$null | ConvertFrom-Json
        
        if ($containerInfo) {
            $containerResults.ContainerRunning = ($containerInfo.State -eq "running")
            $containerResults.ContainerHealthy = ($containerInfo.Health -eq "healthy")
            
            if ($containerResults.ContainerRunning) {
                # Test metrics endpoint
                try {
                    $metricsResponse = Invoke-WebRequest -Uri "http://localhost:8080/metrics" -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop
                    $containerResults.MetricsAccessible = ($metricsResponse.StatusCode -eq 200)
                } catch {
                    $containerResults.Errors += "Metrics endpoint not accessible: $($_.Exception.Message)"
                }
                
                # Check logs
                try {
                    $logs = docker logs cloudflared --tail 10 2>$null
                    $containerResults.LogsAvailable = ($logs -ne $null -and $logs.Length -gt 0)
                    
                    # Check for connection errors in logs
                    if ($logs -match "error|failed|unable") {
                        $containerResults.Errors += "Errors found in container logs"
                    }
                } catch {
                    $containerResults.Errors += "Unable to retrieve container logs: $($_.Exception.Message)"
                }
            } else {
                $containerResults.Errors += "Container is not running (State: $($containerInfo.State))"
            }
        } else {
            $containerResults.Errors += "Container not found"
        }
    } catch {
        $containerResults.Errors += "Error checking container: $($_.Exception.Message)"
    }
    
    return $containerResults
}

function Test-LocalServiceRouting {
    Write-Log "Testing local service routing through tunnel..."
    $routingResults = @()
    
    foreach ($serviceName in $TunnelServices.Keys) {
        $serviceConfig = $TunnelServices[$serviceName]
        $result = @{
            Service = $serviceName
            Description = $serviceConfig.Description
            LocalAccessible = $false
            ResponseTime = 0
            StatusCode = 0
            Critical = $serviceConfig.Critical
            Error = ""
        }
        
        # Test local service accessibility
        $localUrl = "http://localhost:$($serviceConfig.Port)$($serviceConfig.Path)"
        
        try {
            Write-Log "Testing local access: $localUrl"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $response = Invoke-WebRequest -Uri $localUrl -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop
            $stopwatch.Stop()
            
            $result.LocalAccessible = $true
            $result.ResponseTime = $stopwatch.ElapsedMilliseconds
            $result.StatusCode = $response.StatusCode
        } catch {
            $result.Error = "Local service not accessible: $($_.Exception.Message)"
            Write-Log "Local access failed for $serviceName: $($_.Exception.Message)"
        }
        
        $routingResults += $result
    }
    
    return $routingResults
}

function Test-ExternalTunnelAccess {
    param([string]$Domain)
    
    if ($SkipExternal -or -not $Domain) {
        Write-Warning "Skipping external tunnel access tests (no domain provided or skip flag set)"
        return @()
    }
    
    Write-Log "Testing external tunnel access for domain: $Domain"
    $externalResults = @()
    
    foreach ($serviceName in $TunnelServices.Keys) {
        $serviceConfig = $TunnelServices[$serviceName]
        $result = @{
            Service = $serviceName
            Description = $serviceConfig.Description
            ExternalAccessible = $false
            ResponseTime = 0
            StatusCode = 0
            SSL = $false
            Critical = $serviceConfig.Critical
            Error = ""
        }
        
        # Construct external URL
        $externalUrl = "https://$($serviceConfig.Subdomain).$Domain$($serviceConfig.Path)"
        
        try {
            Write-Log "Testing external access: $externalUrl"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $response = Invoke-WebRequest -Uri $externalUrl -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop
            $stopwatch.Stop()
            
            $result.ExternalAccessible = $true
            $result.ResponseTime = $stopwatch.ElapsedMilliseconds
            $result.StatusCode = $response.StatusCode
            $result.SSL = $externalUrl.StartsWith("https://")
        } catch {
            $result.Error = "External access failed: $($_.Exception.Message)"
            Write-Log "External access failed for $serviceName: $($_.Exception.Message)"
        }
        
        $externalResults += $result
    }
    
    return $externalResults
}

function Test-TunnelMetrics {
    Write-Log "Testing tunnel metrics and performance..."
    $metricsResults = @{
        MetricsAvailable = $false
        ActiveConnections = 0
        TunnelState = "unknown"
        Errors = @()
    }
    
    try {
        $metricsResponse = Invoke-WebRequest -Uri "http://localhost:8080/metrics" -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop
        
        if ($metricsResponse.StatusCode -eq 200) {
            $metricsResults.MetricsAvailable = $true
            $metricsContent = $metricsResponse.Content
            
            # Parse metrics for tunnel state
            if ($metricsContent -match 'cloudflared_tunnel_user_hostnames_counts\{.*\}\s+(\d+)') {
                $metricsResults.ActiveConnections = [int]$matches[1]
            }
            
            # Check for tunnel state indicators
            if ($metricsContent -match 'cloudflared_tunnel_.*connected.*1') {
                $metricsResults.TunnelState = "connected"
            } elseif ($metricsContent -match 'cloudflared_tunnel_.*disconnected.*1') {
                $metricsResults.TunnelState = "disconnected"
                $metricsResults.Errors += "Tunnel is disconnected"
            }
        }
    } catch {
        $metricsResults.Errors += "Unable to retrieve metrics: $($_.Exception.Message)"
    }
    
    return $metricsResults
}

# Main execution
Write-Host "=== Cloudflare Tunnel Connectivity Testing ===" -ForegroundColor White
Write-Host "Testing tunnel configuration, connectivity, and service routing..." -ForegroundColor Cyan
Write-Host ""

# Load environment variables
Load-Environment

# Get domain from environment if not provided
if (-not $Domain) {
    $Domain = [Environment]::GetEnvironmentVariable("DOMAIN")
}

$overallSuccess = $true

# Test 1: Tunnel Configuration
Write-Host "1. Testing tunnel configuration..." -ForegroundColor Yellow
$configResults = Test-TunnelConfiguration

if ($configResults.ConfigFileExists) {
    Write-Success "Configuration file exists"
} else {
    Write-Error "Configuration file missing"
    $overallSuccess = $false
}

if ($configResults.CredentialsExist) {
    Write-Success "Credentials file exists"
} else {
    Write-Error "Credentials file missing"
    $overallSuccess = $false
}

if ($configResults.ConfigValid) {
    Write-Success "Configuration is valid"
    Write-Info "Tunnel ID: $($configResults.TunnelID)"
    Write-Info "Ingress rules: $($configResults.IngressRules.Count)"
} else {
    Write-Error "Configuration has errors"
    foreach ($error in $configResults.Errors) {
        Write-Error "  $error"
    }
    $overallSuccess = $false
}

Write-Host ""

# Test 2: Tunnel Container
Write-Host "2. Testing tunnel container..." -ForegroundColor Yellow
$containerResults = Test-TunnelContainer

if ($containerResults.ContainerRunning) {
    Write-Success "Tunnel container is running"
} else {
    Write-Error "Tunnel container is not running"
    $overallSuccess = $false
}

if ($containerResults.ContainerHealthy) {
    Write-Success "Tunnel container is healthy"
} else {
    Write-Warning "Tunnel container health check failed"
}

if ($containerResults.MetricsAccessible) {
    Write-Success "Metrics endpoint is accessible"
} else {
    Write-Error "Metrics endpoint is not accessible"
    $overallSuccess = $false
}

foreach ($error in $containerResults.Errors) {
    Write-Error "  $error"
}

Write-Host ""

# Test 3: Local Service Routing
Write-Host "3. Testing local service routing..." -ForegroundColor Yellow
$routingResults = Test-LocalServiceRouting

$accessibleServices = ($routingResults | Where-Object { $_.LocalAccessible }).Count
$totalServices = $routingResults.Count

Write-Info "Local services accessible: $accessibleServices/$totalServices"

foreach ($routing in $routingResults) {
    if ($routing.LocalAccessible) {
        Write-Success "$($routing.Service) accessible locally ($($routing.ResponseTime)ms)"
    } else {
        if ($routing.Critical) {
            Write-Error "$($routing.Service) not accessible locally: $($routing.Error)"
            $overallSuccess = $false
        } else {
            Write-Warning "$($routing.Service) not accessible locally: $($routing.Error)"
        }
    }
}

Write-Host ""

# Test 4: External Tunnel Access
Write-Host "4. Testing external tunnel access..." -ForegroundColor Yellow
$externalResults = Test-ExternalTunnelAccess $Domain

if ($externalResults.Count -gt 0) {
    $externalAccessible = ($externalResults | Where-Object { $_.ExternalAccessible }).Count
    $totalExternal = $externalResults.Count
    
    Write-Info "External services accessible: $externalAccessible/$totalExternal"
    
    foreach ($external in $externalResults) {
        if ($external.ExternalAccessible) {
            $sslInfo = if ($external.SSL) { " [SSL]" } else { "" }
            Write-Success "$($external.Service) accessible externally ($($external.ResponseTime)ms)$sslInfo"
        } else {
            if ($external.Critical) {
                Write-Error "$($external.Service) not accessible externally: $($external.Error)"
                $overallSuccess = $false
            } else {
                Write-Warning "$($external.Service) not accessible externally: $($external.Error)"
            }
        }
    }
} else {
    Write-Info "External access tests skipped"
}

Write-Host ""

# Test 5: Tunnel Metrics
Write-Host "5. Testing tunnel metrics..." -ForegroundColor Yellow
$metricsResults = Test-TunnelMetrics

if ($metricsResults.MetricsAvailable) {
    Write-Success "Tunnel metrics are available"
    Write-Info "Tunnel state: $($metricsResults.TunnelState)"
    Write-Info "Active connections: $($metricsResults.ActiveConnections)"
} else {
    Write-Warning "Tunnel metrics are not available"
}

foreach ($error in $metricsResults.Errors) {
    Write-Error "  $error"
    $overallSuccess = $false
}

# Summary
Write-Host ""
Write-Host "=== Tunnel Connectivity Test Summary ===" -ForegroundColor White

if ($overallSuccess) {
    Write-Success "All critical tunnel connectivity tests passed!"
    Write-Info "Cloudflare tunnel is properly configured and services are accessible."
} else {
    Write-Error "Some tunnel connectivity tests failed."
    Write-Info "Please review the errors above and fix tunnel configuration issues."
}

# Recommendations
Write-Host ""
Write-Host "Recommendations:" -ForegroundColor Cyan
if (-not $Domain) {
    Write-Info "• Set DOMAIN environment variable to test external access"
}
if ($configResults.Errors.Count -gt 0) {
    Write-Info "• Fix tunnel configuration errors before proceeding"
}
if (-not $containerResults.ContainerHealthy) {
    Write-Info "• Check tunnel container logs: docker logs cloudflared"
}

exit $(if ($overallSuccess) { 0 } else { 1 })