#!/usr/bin/env pwsh
# Network Connectivity Testing Script
# Tests inter-service communication and network isolation

param(
    [switch]$Verbose = $false,
    [switch]$SkipExternal = $false,
    [int]$Timeout = 10
)

# Color functions for output
function Write-Success { param([string]$Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Error { param([string]$Message) Write-Host "✗ $Message" -ForegroundColor Red }
function Write-Warning { param([string]$Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }
function Write-Info { param([string]$Message) Write-Host "ℹ $Message" -ForegroundColor Cyan }
function Write-Log { param([string]$Message) if ($Verbose) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor Gray } }

# Network definitions
$Networks = @{
    "homelab_frontend" = @{
        Subnet = "172.20.0.0/16"
        Type = "external"
        Services = @("cloudflared", "homer", "dashy", "portainer", "filebrowser", "linkding", "actual", "duplicati", "prometheus", "grafana")
        Description = "Frontend services accessible via Cloudflare tunnel"
    }
    "homelab_backend" = @{
        Subnet = "172.21.0.0/16"
        Type = "internal"
        Services = @("portainer", "linkding", "duplicati")
        Description = "Internal backend services communication"
    }
    "homelab_monitoring" = @{
        Subnet = "172.22.0.0/16"
        Type = "internal"
        Services = @("prometheus", "grafana", "loki", "promtail", "node-exporter", "cadvisor")
        Description = "Monitoring stack isolation"
    }
}

# Service communication matrix - defines which services should be able to communicate
$CommunicationMatrix = @{
    "prometheus" = @("node-exporter", "cadvisor", "grafana")
    "grafana" = @("prometheus", "loki")
    "promtail" = @("loki")
    "cloudflared" = @("homer", "dashy", "portainer", "filebrowser", "linkding", "actual", "duplicati", "prometheus", "grafana")
    "duplicati" = @("prometheus", "grafana", "portainer", "linkding", "actual", "filebrowser")
}

function Test-DockerNetworks {
    Write-Log "Testing Docker network configuration..."
    $networkResults = @()
    
    foreach ($networkName in $Networks.Keys) {
        $networkConfig = $Networks[$networkName]
        $result = @{
            Name = $networkName
            Exists = $false
            Subnet = ""
            Driver = ""
            Internal = $false
            ConnectedContainers = @()
            Errors = @()
        }
        
        try {
            $networkInfo = docker network inspect $networkName --format '{{json .}}' 2>$null | ConvertFrom-Json
            
            if ($networkInfo) {
                $result.Exists = $true
                $result.Driver = $networkInfo.Driver
                $result.Internal = $networkInfo.Internal
                
                # Get subnet information
                if ($networkInfo.IPAM.Config) {
                    $result.Subnet = $networkInfo.IPAM.Config[0].Subnet
                }
                
                # Get connected containers
                if ($networkInfo.Containers) {
                    $result.ConnectedContainers = $networkInfo.Containers.PSObject.Properties | ForEach-Object { $_.Value.Name }
                }
                
                # Validate configuration
                if ($result.Subnet -ne $networkConfig.Subnet) {
                    $result.Errors += "Subnet mismatch: expected $($networkConfig.Subnet), got $($result.Subnet)"
                }
                
                if ($networkConfig.Type -eq "internal" -and -not $result.Internal) {
                    $result.Errors += "Network should be internal but is not"
                }
                
                if ($networkConfig.Type -eq "external" -and $result.Internal) {
                    $result.Errors += "Network should be external but is internal"
                }
            } else {
                $result.Errors += "Network does not exist"
            }
        } catch {
            $result.Errors += "Error inspecting network: $($_.Exception.Message)"
        }
        
        $networkResults += $result
    }
    
    return $networkResults
}

function Test-ServiceNetworkMembership {
    Write-Log "Testing service network membership..."
    $membershipResults = @()
    
    foreach ($networkName in $Networks.Keys) {
        $networkConfig = $Networks[$networkName]
        
        foreach ($serviceName in $networkConfig.Services) {
            $result = @{
                Service = $serviceName
                Network = $networkName
                Connected = $false
                IPAddress = ""
                Error = ""
            }
            
            try {
                # Get container name for service
                $containerInfo = docker-compose ps --format json $serviceName 2>$null | ConvertFrom-Json
                
                if ($containerInfo -and $containerInfo.State -eq "running") {
                    $containerName = $containerInfo.Name
                    
                    # Check if container is connected to network
                    $networkInfo = docker network inspect $networkName --format '{{json .Containers}}' 2>$null | ConvertFrom-Json
                    
                    if ($networkInfo) {
                        foreach ($container in $networkInfo.PSObject.Properties) {
                            if ($container.Value.Name -eq $containerName) {
                                $result.Connected = $true
                                $result.IPAddress = $container.Value.IPv4Address -replace '/.*$', ''
                                break
                            }
                        }
                    }
                    
                    if (-not $result.Connected) {
                        $result.Error = "Container not found in network"
                    }
                } else {
                    $result.Error = "Container not running"
                }
            } catch {
                $result.Error = $_.Exception.Message
            }
            
            $membershipResults += $result
        }
    }
    
    return $membershipResults
}

function Test-InterServiceCommunication {
    Write-Log "Testing inter-service communication..."
    $communicationResults = @()
    
    foreach ($sourceService in $CommunicationMatrix.Keys) {
        $targetServices = $CommunicationMatrix[$sourceService]
        
        foreach ($targetService in $targetServices) {
            $result = @{
                Source = $sourceService
                Target = $targetService
                CanCommunicate = $false
                ResponseTime = 0
                Method = ""
                Error = ""
            }
            
            try {
                # Get source container info
                $sourceContainer = docker-compose ps --format json $sourceService 2>$null | ConvertFrom-Json
                
                if ($sourceContainer -and $sourceContainer.State -eq "running") {
                    $sourceContainerName = $sourceContainer.Name
                    
                    # Determine target port based on service
                    $targetPort = switch ($targetService) {
                        "prometheus" { 9090 }
                        "grafana" { 3000 }
                        "loki" { 3100 }
                        "node-exporter" { 9100 }
                        "cadvisor" { 8080 }
                        "homer" { 8080 }
                        "dashy" { 80 }
                        "portainer" { 9000 }
                        "filebrowser" { 80 }
                        "linkding" { 9090 }
                        "actual" { 5006 }
                        "duplicati" { 8200 }
                        default { 80 }
                    }
                    
                    # Test communication using docker exec
                    $testCommand = "wget --quiet --tries=1 --timeout=$Timeout --spider http://${targetService}:${targetPort}/"
                    
                    Write-Log "Testing communication: $sourceService -> $targetService:$targetPort"
                    
                    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    $execResult = docker exec $sourceContainerName sh -c $testCommand 2>$null
                    $stopwatch.Stop()
                    
                    if ($LASTEXITCODE -eq 0) {
                        $result.CanCommunicate = $true
                        $result.ResponseTime = $stopwatch.ElapsedMilliseconds
                        $result.Method = "HTTP"
                    } else {
                        # Try ping as fallback
                        $pingCommand = "ping -c 1 -W $Timeout $targetService"
                        $pingResult = docker exec $sourceContainerName sh -c $pingCommand 2>$null
                        
                        if ($LASTEXITCODE -eq 0) {
                            $result.CanCommunicate = $true
                            $result.Method = "PING"
                        } else {
                            $result.Error = "No response to HTTP or ping"
                        }
                    }
                } else {
                    $result.Error = "Source container not running"
                }
            } catch {
                $result.Error = $_.Exception.Message
            }
            
            $communicationResults += $result
        }
    }
    
    return $communicationResults
}

function Test-NetworkIsolation {
    Write-Log "Testing network isolation..."
    $isolationResults = @()
    
    # Test that backend and monitoring networks are properly isolated
    $internalNetworks = @("homelab_backend", "homelab_monitoring")
    
    foreach ($networkName in $internalNetworks) {
        $result = @{
            Network = $networkName
            IsIsolated = $false
            ExternalAccess = $false
            Error = ""
        }
        
        try {
            # Check if network is marked as internal
            $networkInfo = docker network inspect $networkName --format '{{.Internal}}' 2>$null
            
            if ($networkInfo -eq "true") {
                $result.IsIsolated = $true
                
                # Try to test external access from a container in this network
                $networkContainers = docker network inspect $networkName --format '{{range .Containers}}{{.Name}} {{end}}' 2>$null
                
                if ($networkContainers) {
                    $firstContainer = ($networkContainers -split ' ')[0]
                    
                    if ($firstContainer) {
                        # Try to reach external site
                        $externalTest = docker exec $firstContainer sh -c "wget --quiet --tries=1 --timeout=5 --spider http://google.com" 2>$null
                        
                        if ($LASTEXITCODE -eq 0) {
                            $result.ExternalAccess = $true
                            $result.Error = "Network allows external access (isolation may be compromised)"
                        }
                    }
                }
            } else {
                $result.Error = "Network is not marked as internal"
            }
        } catch {
            $result.Error = $_.Exception.Message
        }
        
        $isolationResults += $result
    }
    
    return $isolationResults
}

function Test-DNSResolution {
    Write-Log "Testing DNS resolution between services..."
    $dnsResults = @()
    
    # Test DNS resolution from cloudflared to all frontend services
    $sourceService = "cloudflared"
    $sourceContainer = docker-compose ps --format json $sourceService 2>$null | ConvertFrom-Json
    
    if ($sourceContainer -and $sourceContainer.State -eq "running") {
        $sourceContainerName = $sourceContainer.Name
        
        foreach ($targetService in $Networks["homelab_frontend"].Services) {
            if ($targetService -eq $sourceService) { continue }
            
            $result = @{
                Source = $sourceService
                Target = $targetService
                DNSResolved = $false
                IPAddress = ""
                Error = ""
            }
            
            try {
                # Test DNS resolution
                $dnsCommand = "nslookup $targetService"
                $dnsOutput = docker exec $sourceContainerName sh -c $dnsCommand 2>$null
                
                if ($LASTEXITCODE -eq 0 -and $dnsOutput -match "Address.*?(\d+\.\d+\.\d+\.\d+)") {
                    $result.DNSResolved = $true
                    $result.IPAddress = $matches[1]
                } else {
                    $result.Error = "DNS resolution failed"
                }
            } catch {
                $result.Error = $_.Exception.Message
            }
            
            $dnsResults += $result
        }
    }
    
    return $dnsResults
}

# Main execution
Write-Host "=== Network Connectivity Testing ===" -ForegroundColor White
Write-Host "Testing network configuration and inter-service communication..." -ForegroundColor Cyan
Write-Host ""

$overallSuccess = $true

# Test 1: Docker Networks
Write-Host "1. Testing Docker network configuration..." -ForegroundColor Yellow
$networkResults = Test-DockerNetworks

foreach ($network in $networkResults) {
    if ($network.Exists) {
        Write-Success "Network $($network.Name) exists"
        
        if ($network.Errors.Count -eq 0) {
            Write-Success "  Configuration is correct"
        } else {
            foreach ($error in $network.Errors) {
                Write-Error "  $error"
                $overallSuccess = $false
            }
        }
        
        Write-Info "  Subnet: $($network.Subnet), Driver: $($network.Driver), Internal: $($network.Internal)"
        Write-Info "  Connected containers: $($network.ConnectedContainers.Count)"
    } else {
        Write-Error "Network $($network.Name) does not exist"
        $overallSuccess = $false
    }
}

Write-Host ""

# Test 2: Service Network Membership
Write-Host "2. Testing service network membership..." -ForegroundColor Yellow
$membershipResults = Test-ServiceNetworkMembership

$membershipByNetwork = $membershipResults | Group-Object Network

foreach ($networkGroup in $membershipByNetwork) {
    $networkName = $networkGroup.Name
    $connected = ($networkGroup.Group | Where-Object { $_.Connected }).Count
    $total = $networkGroup.Group.Count
    
    Write-Info "Network $networkName: $connected/$total services connected"
    
    foreach ($membership in $networkGroup.Group) {
        if ($membership.Connected) {
            Write-Success "  $($membership.Service) connected ($($membership.IPAddress))"
        } else {
            Write-Error "  $($membership.Service) not connected: $($membership.Error)"
            $overallSuccess = $false
        }
    }
}

Write-Host ""

# Test 3: Inter-Service Communication
Write-Host "3. Testing inter-service communication..." -ForegroundColor Yellow
$communicationResults = Test-InterServiceCommunication

$successfulComms = ($communicationResults | Where-Object { $_.CanCommunicate }).Count
$totalComms = $communicationResults.Count

Write-Info "Communication tests: $successfulComms/$totalComms successful"

foreach ($comm in $communicationResults) {
    if ($comm.CanCommunicate) {
        $timeInfo = if ($comm.ResponseTime -gt 0) { " ($($comm.ResponseTime)ms)" } else { "" }
        Write-Success "$($comm.Source) -> $($comm.Target) [$($comm.Method)]$timeInfo"
    } else {
        Write-Error "$($comm.Source) -> $($comm.Target): $($comm.Error)"
        $overallSuccess = $false
    }
}

Write-Host ""

# Test 4: Network Isolation
Write-Host "4. Testing network isolation..." -ForegroundColor Yellow
$isolationResults = Test-NetworkIsolation

foreach ($isolation in $isolationResults) {
    if ($isolation.IsIsolated -and -not $isolation.ExternalAccess) {
        Write-Success "Network $($isolation.Network) is properly isolated"
    } else {
        Write-Error "Network $($isolation.Network) isolation issue: $($isolation.Error)"
        $overallSuccess = $false
    }
}

Write-Host ""

# Test 5: DNS Resolution
Write-Host "5. Testing DNS resolution..." -ForegroundColor Yellow
$dnsResults = Test-DNSResolution

$successfulDNS = ($dnsResults | Where-Object { $_.DNSResolved }).Count
$totalDNS = $dnsResults.Count

Write-Info "DNS resolution tests: $successfulDNS/$totalDNS successful"

foreach ($dns in $dnsResults) {
    if ($dns.DNSResolved) {
        Write-Success "$($dns.Source) can resolve $($dns.Target) -> $($dns.IPAddress)"
    } else {
        Write-Warning "$($dns.Source) cannot resolve $($dns.Target): $($dns.Error)"
    }
}

# Summary
Write-Host ""
Write-Host "=== Network Connectivity Test Summary ===" -ForegroundColor White

if ($overallSuccess) {
    Write-Success "All critical network connectivity tests passed!"
    Write-Info "Network configuration is correct and services can communicate properly."
} else {
    Write-Error "Some network connectivity tests failed."
    Write-Info "Please review the errors above and fix network configuration issues."
}

exit $(if ($overallSuccess) { 0 } else { 1 })