#!/usr/bin/env pwsh
# Comprehensive Service Health and Connectivity Testing Script
# Tests all services defined in docker-compose.yml for health and connectivity

param(
    [switch]$Verbose = $false,
    [switch]$SkipTunnel = $false,
    [string]$Service = "",
    [int]$Timeout = 30
)

# Color functions for output
function Write-Success { param([string]$Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Error { param([string]$Message) Write-Host "✗ $Message" -ForegroundColor Red }
function Write-Warning { param([string]$Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }
function Write-Info { param([string]$Message) Write-Host "ℹ $Message" -ForegroundColor Cyan }
function Write-Log { param([string]$Message) if ($Verbose) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor Gray } }

# Service definitions with health check endpoints and expected responses
$Services = @{
    "cloudflared" = @{
        Port = 8080
        HealthPath = "/metrics"
        ExpectedStatus = 200
        Network = "frontend"
        Critical = $true
        Description = "Cloudflare Tunnel"
    }
    "prometheus" = @{
        Port = 9090
        HealthPath = "/-/healthy"
        ExpectedStatus = 200
        Network = "monitoring"
        Critical = $true
        Description = "Prometheus Metrics"
    }
    "grafana" = @{
        Port = 3000
        HealthPath = "/api/health"
        ExpectedStatus = 200
        Network = "monitoring"
        Critical = $true
        Description = "Grafana Dashboard"
    }
    "loki" = @{
        Port = 3100
        HealthPath = "/ready"
        ExpectedStatus = 200
        Network = "monitoring"
        Critical = $true
        Description = "Loki Log Aggregation"
    }
    "promtail" = @{
        Port = 9080
        HealthPath = "/ready"
        ExpectedStatus = 200
        Network = "monitoring"
        Critical = $false
        Description = "Promtail Log Collection"
    }
    "node-exporter" = @{
        Port = 9100
        HealthPath = "/metrics"
        ExpectedStatus = 200
        Network = "monitoring"
        Critical = $false
        Description = "Node Exporter"
    }
    "cadvisor" = @{
        Port = 8080
        HealthPath = "/healthz"
        ExpectedStatus = 200
        Network = "monitoring"
        Critical = $false
        Description = "cAdvisor Container Metrics"
    }
    "homer" = @{
        Port = 8080
        HealthPath = "/"
        ExpectedStatus = 200
        Network = "frontend"
        Critical = $false
        Description = "Homer Dashboard"
    }
    "dashy" = @{
        Port = 80
        HealthPath = "/"
        ExpectedStatus = 200
        Network = "frontend"
        Critical = $false
        Description = "Dashy Dashboard"
    }
    "portainer" = @{
        Port = 9000
        HealthPath = "/api/status"
        ExpectedStatus = 200
        Network = "frontend"
        Critical = $true
        Description = "Portainer Container Management"
    }
    "filebrowser" = @{
        Port = 80
        HealthPath = "/health"
        ExpectedStatus = 200
        Network = "frontend"
        Critical = $false
        Description = "FileBrowser"
    }
    "linkding" = @{
        Port = 9090
        HealthPath = "/health"
        ExpectedStatus = 200
        Network = "frontend"
        Critical = $false
        Description = "Linkding Bookmarks"
    }
    "actual" = @{
        Port = 5006
        HealthPath = "/"
        ExpectedStatus = 200
        Network = "frontend"
        Critical = $false
        Description = "Actual Budget"
    }
    "duplicati" = @{
        Port = 8200
        HealthPath = "/"
        ExpectedStatus = 200
        Network = "frontend"
        Critical = $true
        Description = "Duplicati Backup"
    }
}

function Test-DockerRunning {
    Write-Log "Checking Docker status..."
    try {
        docker info 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Docker is running"
            return $true
        } else {
            Write-Error "Docker is not running"
            return $false
        }
    } catch {
        Write-Error "Docker is not accessible: $($_.Exception.Message)"
        return $false
    }
}

function Test-ComposeFile {
    Write-Log "Validating Docker Compose configuration..."
    try {
        docker-compose config --quiet 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Docker Compose file is valid"
            return $true
        } else {
            Write-Error "Docker Compose file has validation errors"
            return $false
        }
    } catch {
        Write-Error "Failed to validate Docker Compose file: $($_.Exception.Message)"
        return $false
    }
}

function Get-ContainerStatus {
    param([string]$ServiceName)
    
    Write-Log "Getting container status for $ServiceName..."
    try {
        $containerInfo = docker-compose ps --format json $ServiceName 2>$null | ConvertFrom-Json
        if ($containerInfo) {
            return @{
                Name = $containerInfo.Name
                State = $containerInfo.State
                Status = $containerInfo.Status
                Health = $containerInfo.Health
                Running = ($containerInfo.State -eq "running")
            }
        } else {
            return @{
                Name = $ServiceName
                State = "not found"
                Status = "Container not found"
                Health = "unknown"
                Running = $false
            }
        }
    } catch {
        Write-Log "Error getting container status: $($_.Exception.Message)"
        return @{
            Name = $ServiceName
            State = "error"
            Status = "Error retrieving status"
            Health = "unknown"
            Running = $false
        }
    }
}

function Test-ServiceHealth {
    param(
        [string]$ServiceName,
        [hashtable]$ServiceConfig
    )
    
    Write-Log "Testing health for service: $ServiceName"
    $results = @{
        Service = $ServiceName
        Description = $ServiceConfig.Description
        ContainerRunning = $false
        HealthEndpointAccessible = $false
        ResponseTime = 0
        StatusCode = 0
        Critical = $ServiceConfig.Critical
        Errors = @()
    }
    
    # Check container status
    $containerStatus = Get-ContainerStatus $ServiceName
    $results.ContainerRunning = $containerStatus.Running
    
    if (-not $containerStatus.Running) {
        $results.Errors += "Container is not running (State: $($containerStatus.State))"
        return $results
    }
    
    # Test health endpoint
    $url = "http://localhost:$($ServiceConfig.Port)$($ServiceConfig.HealthPath)"
    Write-Log "Testing health endpoint: $url"
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-WebRequest -Uri $url -TimeoutSec $Timeout -UseBasicParsing -ErrorAction Stop
        $stopwatch.Stop()
        
        $results.ResponseTime = $stopwatch.ElapsedMilliseconds
        $results.StatusCode = $response.StatusCode
        $results.HealthEndpointAccessible = ($response.StatusCode -eq $ServiceConfig.ExpectedStatus)
        
        if ($results.HealthEndpointAccessible) {
            Write-Log "Health check passed for $ServiceName (${$results.ResponseTime}ms)"
        } else {
            $results.Errors += "Unexpected status code: $($response.StatusCode) (expected: $($ServiceConfig.ExpectedStatus))"
        }
    } catch {
        $stopwatch.Stop() if $stopwatch
        $results.Errors += "Health endpoint not accessible: $($_.Exception.Message)"
        Write-Log "Health check failed for $ServiceName: $($_.Exception.Message)"
    }
    
    return $results
}

function Test-NetworkConnectivity {
    param([string]$ServiceName)
    
    Write-Log "Testing network connectivity for $ServiceName..."
    $results = @{
        Service = $ServiceName
        NetworkTests = @()
    }
    
    # Get service networks from compose file
    try {
        $composeConfig = docker-compose config --format json | ConvertFrom-Json
        $serviceConfig = $composeConfig.services.$ServiceName
        
        if ($serviceConfig.networks) {
            foreach ($network in $serviceConfig.networks.PSObject.Properties.Name) {
                $networkTest = @{
                    Network = $network
                    Connected = $false
                    Error = ""
                }
                
                try {
                    # Check if container is connected to network
                    $networkInfo = docker network inspect "homelab_$network" --format '{{json .Containers}}' 2>$null | ConvertFrom-Json
                    $containerConnected = $false
                    
                    if ($networkInfo) {
                        foreach ($container in $networkInfo.PSObject.Properties) {
                            if ($container.Value.Name -like "*$ServiceName*") {
                                $containerConnected = $true
                                break
                            }
                        }
                    }
                    
                    $networkTest.Connected = $containerConnected
                    if (-not $containerConnected) {
                        $networkTest.Error = "Container not found in network"
                    }
                } catch {
                    $networkTest.Error = $_.Exception.Message
                }
                
                $results.NetworkTests += $networkTest
            }
        }
    } catch {
        Write-Log "Error testing network connectivity: $($_.Exception.Message)"
    }
    
    return $results
}

function Test-ServiceDependencies {
    Write-Log "Testing service dependencies..."
    $dependencyResults = @()
    
    try {
        $composeConfig = docker-compose config --format json | ConvertFrom-Json
        
        foreach ($serviceName in $composeConfig.services.PSObject.Properties.Name) {
            $serviceConfig = $composeConfig.services.$serviceName
            
            if ($serviceConfig.depends_on) {
                foreach ($dependency in $serviceConfig.depends_on.PSObject.Properties.Name) {
                    $depStatus = Get-ContainerStatus $dependency
                    $dependencyResults += @{
                        Service = $serviceName
                        Dependency = $dependency
                        DependencyRunning = $depStatus.Running
                        DependencyHealth = $depStatus.Health
                    }
                }
            }
        }
    } catch {
        Write-Error "Failed to test service dependencies: $($_.Exception.Message)"
    }
    
    return $dependencyResults
}

# Main execution
Write-Host "=== Homelab Infrastructure Service Health Testing ===" -ForegroundColor White
Write-Host "Testing all services for health and connectivity..." -ForegroundColor Cyan
Write-Host ""

$overallSuccess = $true
$testResults = @()

# Pre-flight checks
if (-not (Test-DockerRunning)) {
    Write-Error "Docker is not running. Please start Docker and try again."
    exit 1
}

if (-not (Test-ComposeFile)) {
    Write-Error "Docker Compose configuration is invalid. Please fix and try again."
    exit 1
}

# Test specific service or all services
$servicesToTest = if ($Service) { @($Service) } else { $Services.Keys }

foreach ($serviceName in $servicesToTest) {
    if (-not $Services.ContainsKey($serviceName)) {
        Write-Warning "Unknown service: $serviceName"
        continue
    }
    
    Write-Host "Testing $serviceName ($($Services[$serviceName].Description))..." -ForegroundColor Yellow
    
    # Test service health
    $healthResult = Test-ServiceHealth $serviceName $Services[$serviceName]
    $testResults += $healthResult
    
    # Test network connectivity
    $networkResult = Test-NetworkConnectivity $serviceName
    
    # Display results
    if ($healthResult.ContainerRunning) {
        Write-Success "Container is running"
    } else {
        Write-Error "Container is not running"
        $overallSuccess = $false
    }
    
    if ($healthResult.HealthEndpointAccessible) {
        Write-Success "Health endpoint accessible ($($healthResult.ResponseTime)ms)"
    } else {
        if ($healthResult.Critical) {
            Write-Error "Health endpoint not accessible (Critical service)"
            $overallSuccess = $false
        } else {
            Write-Warning "Health endpoint not accessible (Non-critical service)"
        }
    }
    
    # Display network connectivity results
    foreach ($networkTest in $networkResult.NetworkTests) {
        if ($networkTest.Connected) {
            Write-Success "Connected to $($networkTest.Network) network"
        } else {
            Write-Error "Not connected to $($networkTest.Network) network: $($networkTest.Error)"
            $overallSuccess = $false
        }
    }
    
    # Display errors
    foreach ($error in $healthResult.Errors) {
        Write-Error "  $error"
    }
    
    Write-Host ""
}

# Test service dependencies
Write-Host "Testing service dependencies..." -ForegroundColor Yellow
$dependencyResults = Test-ServiceDependencies

foreach ($depResult in $dependencyResults) {
    if ($depResult.DependencyRunning) {
        Write-Success "$($depResult.Service) dependency $($depResult.Dependency) is running"
    } else {
        Write-Error "$($depResult.Service) dependency $($depResult.Dependency) is not running"
        $overallSuccess = $false
    }
}

# Summary
Write-Host "=== Test Summary ===" -ForegroundColor White
$criticalServices = $testResults | Where-Object { $_.Critical }
$nonCriticalServices = $testResults | Where-Object { -not $_.Critical }

$criticalHealthy = ($criticalServices | Where-Object { $_.ContainerRunning -and $_.HealthEndpointAccessible }).Count
$nonCriticalHealthy = ($nonCriticalServices | Where-Object { $_.ContainerRunning -and $_.HealthEndpointAccessible }).Count

Write-Host "Critical services: $criticalHealthy/$($criticalServices.Count) healthy" -ForegroundColor $(if ($criticalHealthy -eq $criticalServices.Count) { "Green" } else { "Red" })
Write-Host "Non-critical services: $nonCriticalHealthy/$($nonCriticalServices.Count) healthy" -ForegroundColor $(if ($nonCriticalHealthy -eq $nonCriticalServices.Count) { "Green" } else { "Yellow" })

if ($overallSuccess) {
    Write-Success "All critical services are healthy!"
    exit 0
} else {
    Write-Error "Some services have issues. Please check the output above."
    exit 1
}