#!/usr/bin/env pwsh
# Fresh Deployment Testing Script
# Tests complete infrastructure deployment on clean systems

param(
    [switch]$Verbose = $false,
    [switch]$CleanupAfter = $false,
    [switch]$SkipPrerequisites = $false,
    [string]$TestEnvironment = "test",  # test, staging, production
    [int]$Timeout = 600  # 10 minutes
)

# Color functions for output
function Write-Success { param([string]$Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Error { param([string]$Message) Write-Host "✗ $Message" -ForegroundColor Red }
function Write-Warning { param([string]$Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }
function Write-Info { param([string]$Message) Write-Host "ℹ $Message" -ForegroundColor Cyan }
function Write-Log { param([string]$Message) if ($Verbose) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor Gray } }

# Deployment phases and their expected outcomes
$DeploymentPhases = @{
    "prerequisites" = @{
        Description = "System Prerequisites Check"
        Required = $true
        EstimatedTime = 30
        Tests = @("docker", "docker-compose", "git", "powershell")
    }
    "environment-setup" = @{
        Description = "Environment Configuration Setup"
        Required = $true
        EstimatedTime = 60
        Tests = @("env-file", "directories", "permissions")
    }
    "configuration-validation" = @{
        Description = "Configuration Files Validation"
        Required = $true
        EstimatedTime = 45
        Tests = @("compose-file", "config-files", "secrets")
    }
    "service-deployment" = @{
        Description = "Service Container Deployment"
        Required = $true
        EstimatedTime = 300
        Tests = @("image-pull", "container-start", "health-checks")
    }
    "network-configuration" = @{
        Description = "Network and Connectivity Setup"
        Required = $true
        EstimatedTime = 90
        Tests = @("networks", "inter-service", "external-access")
    }
    "data-persistence" = @{
        Description = "Data Persistence Verification"
        Required = $true
        EstimatedTime = 60
        Tests = @("volumes", "bind-mounts", "data-integrity")
    }
    "monitoring-setup" = @{
        Description = "Monitoring Stack Deployment"
        Required = $false
        EstimatedTime = 120
        Tests = @("prometheus", "grafana", "loki", "dashboards")
    }
}

function Test-Prerequisites {
    Write-Log "Testing system prerequisites..."
    $prereqResults = @{
        DockerInstalled = $false
        DockerRunning = $false
        DockerComposeAvailable = $false
        GitAvailable = $false
        PowerShellVersion = ""
        SystemResources = @{}
        Errors = @()
    }
    
    # Test Docker installation
    try {
        $dockerVersion = docker --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $prereqResults.DockerInstalled = $true
            Write-Log "Docker version: $dockerVersion"
        } else {
            $prereqResults.Errors += "Docker is not installed"
        }
    } catch {
        $prereqResults.Errors += "Docker command not found: $($_.Exception.Message)"
    }
    
    # Test Docker daemon
    try {
        docker info 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $prereqResults.DockerRunning = $true
        } else {
            $prereqResults.Errors += "Docker daemon is not running"
        }
    } catch {
        $prereqResults.Errors += "Cannot connect to Docker daemon: $($_.Exception.Message)"
    }
    
    # Test Docker Compose
    try {
        $composeVersion = docker-compose --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $prereqResults.DockerComposeAvailable = $true
            Write-Log "Docker Compose version: $composeVersion"
        } else {
            $prereqResults.Errors += "Docker Compose is not available"
        }
    } catch {
        $prereqResults.Errors += "Docker Compose command not found: $($_.Exception.Message)"
    }
    
    # Test Git
    try {
        $gitVersion = git --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $prereqResults.GitAvailable = $true
            Write-Log "Git version: $gitVersion"
        } else {
            $prereqResults.Errors += "Git is not installed"
        }
    } catch {
        $prereqResults.Errors += "Git command not found: $($_.Exception.Message)"
    }
    
    # Test PowerShell version
    $prereqResults.PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    Write-Log "PowerShell version: $($prereqResults.PowerShellVersion)"
    
    # Test system resources
    try {
        $memoryGB = [math]::Round((Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
        $diskSpaceGB = [math]::Round((Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB, 2)
        
        $prereqResults.SystemResources = @{
            MemoryGB = $memoryGB
            DiskSpaceGB = $diskSpaceGB
        }
        
        Write-Log "System memory: ${memoryGB}GB"
        Write-Log "Available disk space: ${diskSpaceGB}GB"
        
        # Check minimum requirements
        if ($memoryGB -lt 4) {
            $prereqResults.Errors += "Insufficient memory: ${memoryGB}GB (minimum 4GB recommended)"
        }
        
        if ($diskSpaceGB -lt 10) {
            $prereqResults.Errors += "Insufficient disk space: ${diskSpaceGB}GB (minimum 10GB recommended)"
        }
    } catch {
        $prereqResults.Errors += "Unable to check system resources: $($_.Exception.Message)"
    }
    
    return $prereqResults
}

function Test-EnvironmentSetup {
    Write-Log "Testing environment setup..."
    $envResults = @{
        EnvFileExists = $false
        EnvFileValid = $false
        DirectoriesCreated = $false
        PermissionsCorrect = $false
        RequiredVariables = @()
        MissingVariables = @()
        Errors = @()
    }
    
    # Check .env file
    if (Test-Path ".env") {
        $envResults.EnvFileExists = $true
        
        try {
            $envContent = Get-Content ".env" -Raw
            $requiredVars = @("DOMAIN", "CLOUDFLARE_TUNNEL_TOKEN", "GRAFANA_ADMIN_PASSWORD", "LINKDING_SUPERUSER_PASSWORD", "ACTUAL_PASSWORD")
            
            foreach ($var in $requiredVars) {
                if ($envContent -match "^$var=.+$") {
                    $envResults.RequiredVariables += $var
                } else {
                    $envResults.MissingVariables += $var
                }
            }
            
            $envResults.EnvFileValid = ($envResults.MissingVariables.Count -eq 0)
        } catch {
            $envResults.Errors += "Error reading .env file: $($_.Exception.Message)"
        }
    } else {
        $envResults.Errors += ".env file does not exist"
    }
    
    # Check required directories
    $requiredDirs = @("config", "data", "scripts", "config/cloudflared", "config/prometheus", "config/grafana", "data/files", "data/backups")
    $missingDirs = @()
    
    foreach ($dir in $requiredDirs) {
        if (-not (Test-Path $dir)) {
            $missingDirs += $dir
        }
    }
    
    if ($missingDirs.Count -eq 0) {
        $envResults.DirectoriesCreated = $true
    } else {
        $envResults.Errors += "Missing directories: $($missingDirs -join ', ')"
    }
    
    # Check permissions (basic check for Windows)
    try {
        $testFile = "test-permissions.tmp"
        "test" | Out-File -FilePath $testFile -ErrorAction Stop
        Remove-Item $testFile -ErrorAction Stop
        $envResults.PermissionsCorrect = $true
    } catch {
        $envResults.Errors += "Insufficient permissions in current directory: $($_.Exception.Message)"
    }
    
    return $envResults
}

function Test-ConfigurationValidation {
    Write-Log "Testing configuration validation..."
    $configResults = @{
        ComposeFileValid = $false
        ConfigFilesPresent = $false
        SecretsConfigured = $false
        TunnelConfigured = $false
        Errors = @()
    }
    
    # Validate Docker Compose file
    try {
        docker-compose config --quiet 2>$null
        if ($LASTEXITCODE -eq 0) {
            $configResults.ComposeFileValid = $true
        } else {
            $configResults.Errors += "Docker Compose file validation failed"
        }
    } catch {
        $configResults.Errors += "Error validating Docker Compose file: $($_.Exception.Message)"
    }
    
    # Check essential config files
    $configFiles = @(
        "config/cloudflared/config.yml",
        "config/prometheus/prometheus.yml",
        "config/grafana/provisioning/datasources/datasources.yml"
    )
    
    $missingConfigs = @()
    foreach ($configFile in $configFiles) {
        if (-not (Test-Path $configFile)) {
            $missingConfigs += $configFile
        }
    }
    
    if ($missingConfigs.Count -eq 0) {
        $configResults.ConfigFilesPresent = $true
    } else {
        $configResults.Errors += "Missing config files: $($missingConfigs -join ', ')"
    }
    
    # Check tunnel configuration
    if (Test-Path "config/cloudflared/config.yml") {
        try {
            $tunnelConfig = Get-Content "config/cloudflared/config.yml" -Raw
            if ($tunnelConfig -match 'tunnel:\s*[a-f0-9-]+' -and $tunnelConfig -notmatch 'YOUR_TUNNEL_ID') {
                $configResults.TunnelConfigured = $true
            } else {
                $configResults.Errors += "Tunnel configuration contains placeholder values"
            }
        } catch {
            $configResults.Errors += "Error reading tunnel configuration: $($_.Exception.Message)"
        }
    }
    
    # Check secrets configuration
    if (Test-Path "config/cloudflared/credentials.json") {
        try {
            $credentials = Get-Content "config/cloudflared/credentials.json" -Raw | ConvertFrom-Json
            if ($credentials.AccountTag -and $credentials.TunnelSecret) {
                $configResults.SecretsConfigured = $true
            } else {
                $configResults.Errors += "Tunnel credentials are incomplete"
            }
        } catch {
            $configResults.Errors += "Error reading tunnel credentials: $($_.Exception.Message)"
        }
    } else {
        $configResults.Errors += "Tunnel credentials file not found"
    }
    
    return $configResults
}

function Test-ServiceDeployment {
    Write-Log "Testing service deployment..."
    $deployResults = @{
        ImagesDownloaded = $false
        ContainersStarted = $false
        HealthChecksPass = $false
        CriticalServicesRunning = $false
        DeploymentTime = 0
        ServiceStatus = @{}
        Errors = @()
    }
    
    $startTime = Get-Date
    
    try {
        # Pull images
        Write-Log "Pulling Docker images..."
        docker-compose pull 2>$null
        if ($LASTEXITCODE -eq 0) {
            $deployResults.ImagesDownloaded = $true
        } else {
            $deployResults.Errors += "Failed to pull Docker images"
        }
        
        # Start services
        Write-Log "Starting services..."
        docker-compose up -d 2>$null
        if ($LASTEXITCODE -eq 0) {
            $deployResults.ContainersStarted = $true
        } else {
            $deployResults.Errors += "Failed to start containers"
        }
        
        # Wait for services to stabilize
        Write-Log "Waiting for services to stabilize..."
        Start-Sleep -Seconds 30
        
        # Check service status
        $services = @("cloudflared", "prometheus", "grafana", "portainer", "homer", "dashy", "duplicati")
        $runningServices = 0
        $healthyServices = 0
        
        foreach ($service in $services) {
            try {
                $containerInfo = docker-compose ps --format json $service 2>$null | ConvertFrom-Json
                
                if ($containerInfo) {
                    $isRunning = ($containerInfo.State -eq "running")
                    $isHealthy = ($containerInfo.Health -eq "healthy" -or $containerInfo.Health -eq "")
                    
                    $deployResults.ServiceStatus[$service] = @{
                        Running = $isRunning
                        Healthy = $isHealthy
                        State = $containerInfo.State
                        Health = $containerInfo.Health
                    }
                    
                    if ($isRunning) { $runningServices++ }
                    if ($isHealthy) { $healthyServices++ }
                } else {
                    $deployResults.ServiceStatus[$service] = @{
                        Running = $false
                        Healthy = $false
                        State = "not found"
                        Health = "unknown"
                    }
                }
            } catch {
                $deployResults.Errors += "Error checking service $service: $($_.Exception.Message)"
            }
        }
        
        $deployResults.HealthChecksPass = ($healthyServices -eq $services.Count)
        $deployResults.CriticalServicesRunning = ($runningServices -ge ($services.Count * 0.8))  # 80% of services running
        
    } catch {
        $deployResults.Errors += "Error during service deployment: $($_.Exception.Message)"
    } finally {
        $deployResults.DeploymentTime = ((Get-Date) - $startTime).TotalSeconds
    }
    
    return $deployResults
}

function Test-NetworkConfiguration {
    Write-Log "Testing network configuration..."
    $networkResults = @{
        NetworksCreated = $false
        InterServiceConnectivity = $false
        ExternalAccess = $false
        NetworkIsolation = $false
        Errors = @()
    }
    
    try {
        # Check if networks are created
        $expectedNetworks = @("homelab_frontend", "homelab_backend", "homelab_monitoring")
        $existingNetworks = docker network ls --format "{{.Name}}" 2>$null
        
        $missingNetworks = @()
        foreach ($network in $expectedNetworks) {
            if ($existingNetworks -notcontains $network) {
                $missingNetworks += $network
            }
        }
        
        if ($missingNetworks.Count -eq 0) {
            $networkResults.NetworksCreated = $true
        } else {
            $networkResults.Errors += "Missing networks: $($missingNetworks -join ', ')"
        }
        
        # Test inter-service connectivity (basic ping test)
        try {
            $pingResult = docker exec cloudflared ping -c 1 prometheus 2>$null
            if ($LASTEXITCODE -eq 0) {
                $networkResults.InterServiceConnectivity = $true
            } else {
                $networkResults.Errors += "Inter-service connectivity test failed"
            }
        } catch {
            $networkResults.Errors += "Unable to test inter-service connectivity: $($_.Exception.Message)"
        }
        
        # Test external access (check if services respond on expected ports)
        $externalPorts = @(80, 3000, 9000, 9090)
        $accessiblePorts = 0
        
        foreach ($port in $externalPorts) {
            try {
                $response = Invoke-WebRequest -Uri "http://localhost:$port" -TimeoutSec 10 -UseBasicParsing -ErrorAction SilentlyContinue
                if ($response.StatusCode -eq 200) {
                    $accessiblePorts++
                }
            } catch {
                # Expected for some services that may not be ready yet
            }
        }
        
        $networkResults.ExternalAccess = ($accessiblePorts -ge ($externalPorts.Count * 0.5))  # 50% of ports accessible
        
        # Test network isolation (check internal networks)
        $internalNetworks = docker network ls --filter "label=homelab.network.access=internal" --format "{{.Name}}" 2>$null
        $networkResults.NetworkIsolation = ($internalNetworks.Count -gt 0)
        
    } catch {
        $networkResults.Errors += "Error testing network configuration: $($_.Exception.Message)"
    }
    
    return $networkResults
}

function Test-DataPersistence {
    Write-Log "Testing data persistence..."
    $persistenceResults = @{
        VolumesCreated = $false
        BindMountsWorking = $false
        DataIntegrity = $false
        Errors = @()
    }
    
    try {
        # Check if volumes are created
        $expectedVolumes = @("homelab_prometheus_data", "homelab_grafana_data", "homelab_portainer_data")
        $existingVolumes = docker volume ls --format "{{.Name}}" 2>$null
        
        $missingVolumes = @()
        foreach ($volume in $expectedVolumes) {
            if ($existingVolumes -notcontains $volume) {
                $missingVolumes += $volume
            }
        }
        
        if ($missingVolumes.Count -eq 0) {
            $persistenceResults.VolumesCreated = $true
        } else {
            $persistenceResults.Errors += "Missing volumes: $($missingVolumes -join ', ')"
        }
        
        # Test bind mounts
        $bindMountPaths = @("./config", "./data")
        $workingMounts = 0
        
        foreach ($path in $bindMountPaths) {
            if (Test-Path $path) {
                $workingMounts++
            }
        }
        
        $persistenceResults.BindMountsWorking = ($workingMounts -eq $bindMountPaths.Count)
        
        # Test data integrity (create a test file and verify it persists)
        try {
            $testDataPath = "./data/deployment-test.txt"
            "Deployment test - $(Get-Date)" | Out-File -FilePath $testDataPath -Encoding UTF8
            
            if (Test-Path $testDataPath) {
                $testContent = Get-Content $testDataPath -Raw
                if ($testContent -match "Deployment test") {
                    $persistenceResults.DataIntegrity = $true
                    Remove-Item $testDataPath -ErrorAction SilentlyContinue
                } else {
                    $persistenceResults.Errors += "Data integrity test failed - content mismatch"
                }
            } else {
                $persistenceResults.Errors += "Data integrity test failed - file not created"
            }
        } catch {
            $persistenceResults.Errors += "Data integrity test error: $($_.Exception.Message)"
        }
        
    } catch {
        $persistenceResults.Errors += "Error testing data persistence: $($_.Exception.Message)"
    }
    
    return $persistenceResults
}

function Cleanup-TestEnvironment {
    if (-not $CleanupAfter) {
        Write-Info "Skipping cleanup (use -CleanupAfter to enable)"
        return
    }
    
    Write-Log "Cleaning up test environment..."
    
    try {
        # Stop and remove containers
        docker-compose down --volumes --remove-orphans 2>$null
        
        # Remove test networks (keep default ones)
        $testNetworks = docker network ls --filter "name=homelab_" --format "{{.Name}}" 2>$null
        foreach ($network in $testNetworks) {
            docker network rm $network 2>$null | Out-Null
        }
        
        # Remove test volumes
        $testVolumes = docker volume ls --filter "name=homelab_" --format "{{.Name}}" 2>$null
        foreach ($volume in $testVolumes) {
            docker volume rm $volume 2>$null | Out-Null
        }
        
        Write-Success "Test environment cleaned up"
    } catch {
        Write-Warning "Error during cleanup: $($_.Exception.Message)"
    }
}

# Main execution
Write-Host "=== Fresh Deployment Testing ===" -ForegroundColor White
Write-Host "Testing complete infrastructure deployment on clean system..." -ForegroundColor Cyan
Write-Host "Test Environment: $TestEnvironment" -ForegroundColor Cyan
Write-Host ""

$overallSuccess = $true
$phaseResults = @{}

# Calculate total estimated time
$totalEstimatedTime = 0
foreach ($phase in $DeploymentPhases.Keys) {
    $totalEstimatedTime += $DeploymentPhases[$phase].EstimatedTime
}
Write-Info "Estimated total time: $([math]::Round($totalEstimatedTime / 60, 1)) minutes"
Write-Host ""

# Execute deployment phases
foreach ($phaseName in $DeploymentPhases.Keys) {
    $phaseConfig = $DeploymentPhases[$phaseName]
    
    Write-Host "Phase: $($phaseConfig.Description)" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Gray
    
    $phaseStartTime = Get-Date
    $phaseSuccess = $true
    
    switch ($phaseName) {
        "prerequisites" {
            if ($SkipPrerequisites) {
                Write-Warning "Skipping prerequisites check as requested"
                $phaseResults[$phaseName] = @{ Skipped = $true; Success = $true }
                break
            }
            
            $result = Test-Prerequisites
            $phaseResults[$phaseName] = $result
            
            if ($result.DockerInstalled -and $result.DockerRunning -and $result.DockerComposeAvailable) {
                Write-Success "All prerequisites met"
            } else {
                Write-Error "Prerequisites not met"
                $phaseSuccess = $false
            }
        }
        
        "environment-setup" {
            $result = Test-EnvironmentSetup
            $phaseResults[$phaseName] = $result
            
            if ($result.EnvFileExists -and $result.EnvFileValid -and $result.DirectoriesCreated) {
                Write-Success "Environment setup complete"
            } else {
                Write-Error "Environment setup failed"
                $phaseSuccess = $false
            }
        }
        
        "configuration-validation" {
            $result = Test-ConfigurationValidation
            $phaseResults[$phaseName] = $result
            
            if ($result.ComposeFileValid -and $result.ConfigFilesPresent) {
                Write-Success "Configuration validation passed"
            } else {
                Write-Error "Configuration validation failed"
                $phaseSuccess = $false
            }
        }
        
        "service-deployment" {
            $result = Test-ServiceDeployment
            $phaseResults[$phaseName] = $result
            
            if ($result.ContainersStarted -and $result.CriticalServicesRunning) {
                Write-Success "Service deployment successful"
                Write-Info "Deployment time: $([math]::Round($result.DeploymentTime, 1)) seconds"
            } else {
                Write-Error "Service deployment failed"
                $phaseSuccess = $false
            }
        }
        
        "network-configuration" {
            $result = Test-NetworkConfiguration
            $phaseResults[$phaseName] = $result
            
            if ($result.NetworksCreated -and $result.InterServiceConnectivity) {
                Write-Success "Network configuration successful"
            } else {
                Write-Error "Network configuration failed"
                $phaseSuccess = $false
            }
        }
        
        "data-persistence" {
            $result = Test-DataPersistence
            $phaseResults[$phaseName] = $result
            
            if ($result.VolumesCreated -and $result.BindMountsWorking -and $result.DataIntegrity) {
                Write-Success "Data persistence verification passed"
            } else {
                Write-Error "Data persistence verification failed"
                $phaseSuccess = $false
            }
        }
        
        "monitoring-setup" {
            # This is a non-critical phase, so we'll just check if monitoring services are running
            $monitoringServices = @("prometheus", "grafana", "loki")
            $runningMonitoring = 0
            
            foreach ($service in $monitoringServices) {
                try {
                    $containerInfo = docker-compose ps --format json $service 2>$null | ConvertFrom-Json
                    if ($containerInfo -and $containerInfo.State -eq "running") {
                        $runningMonitoring++
                    }
                } catch {
                    # Service may not be configured
                }
            }
            
            $phaseResults[$phaseName] = @{
                MonitoringServicesRunning = $runningMonitoring
                TotalMonitoringServices = $monitoringServices.Count
                Success = ($runningMonitoring -gt 0)
            }
            
            if ($runningMonitoring -gt 0) {
                Write-Success "Monitoring setup successful ($runningMonitoring/$($monitoringServices.Count) services)"
            } else {
                Write-Warning "Monitoring setup incomplete (non-critical)"
            }
        }
    }
    
    # Display phase errors
    if ($phaseResults[$phaseName].Errors) {
        foreach ($error in $phaseResults[$phaseName].Errors) {
            Write-Error "  $error"
        }
    }
    
    $phaseDuration = ((Get-Date) - $phaseStartTime).TotalSeconds
    Write-Info "Phase completed in $([math]::Round($phaseDuration, 1)) seconds"
    
    if (-not $phaseSuccess -and $phaseConfig.Required) {
        $overallSuccess = $false
        Write-Error "Critical phase failed. Stopping deployment test."
        break
    }
    
    Write-Host ""
}

# Final Summary
Write-Host "=== Fresh Deployment Test Summary ===" -ForegroundColor White

$successfulPhases = 0
$totalPhases = $DeploymentPhases.Keys.Count

foreach ($phaseName in $DeploymentPhases.Keys) {
    $phaseConfig = $DeploymentPhases[$phaseName]
    $result = $phaseResults[$phaseName]
    
    if ($result -and ($result.Success -or $result.Skipped)) {
        $successfulPhases++
        $status = if ($result.Skipped) { "SKIPPED" } else { "PASS" }
        Write-Success "$status - $($phaseConfig.Description)"
    } else {
        $status = if ($phaseConfig.Required) { "FAIL" } else { "WARN" }
        $color = if ($phaseConfig.Required) { "Red" } else { "Yellow" }
        Write-Host "$status - $($phaseConfig.Description)" -ForegroundColor $color
    }
}

Write-Host ""
Write-Host "Phases completed: $successfulPhases/$totalPhases" -ForegroundColor White

if ($overallSuccess) {
    Write-Success "Fresh deployment test completed successfully!"
    Write-Info "Infrastructure is ready for production use."
} else {
    Write-Error "Fresh deployment test failed."
    Write-Info "Please review the errors above and fix issues before deployment."
}

# Cleanup if requested
Cleanup-TestEnvironment

# Recommendations
Write-Host ""
Write-Host "Recommendations:" -ForegroundColor Cyan

if (-not $overallSuccess) {
    Write-Info "• Fix critical deployment issues before proceeding"
    Write-Info "• Review Docker and system logs for detailed error information"
}

if ($phaseResults["monitoring-setup"] -and $phaseResults["monitoring-setup"].MonitoringServicesRunning -eq 0) {
    Write-Info "• Configure monitoring services for production deployment"
}

if ($overallSuccess) {
    Write-Info "• Run health and connectivity tests: .\scripts\run-health-tests.ps1"
    Write-Info "• Configure backup jobs in Duplicati"
    Write-Info "• Set up external domain and tunnel configuration"
}

exit $(if ($overallSuccess) { 0 } else { 1 })