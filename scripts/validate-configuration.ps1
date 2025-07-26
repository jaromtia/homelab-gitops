#!/usr/bin/env pwsh
# Configuration Validation Script
# Validates all configuration files and service startup sequences

param(
    [switch]$Verbose = $false,
    [switch]$FixIssues = $false,
    [string]$ConfigType = "all",  # all, docker, tunnel, monitoring, apps
    [switch]$CheckSyntax = $true
)

# Color functions for output
function Write-Success { param([string]$Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Error { param([string]$Message) Write-Host "✗ $Message" -ForegroundColor Red }
function Write-Warning { param([string]$Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }
function Write-Info { param([string]$Message) Write-Host "ℹ $Message" -ForegroundColor Cyan }
function Write-Log { param([string]$Message) if ($Verbose) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor Gray } }

# Configuration file definitions
$ConfigFiles = @{
    "docker-compose" = @{
        Path = "docker-compose.yml"
        Type = "yaml"
        Critical = $true
        Description = "Docker Compose orchestration file"
        Validations = @("syntax", "services", "networks", "volumes", "dependencies")
    }
    "environment" = @{
        Path = ".env"
        Type = "env"
        Critical = $true
        Description = "Environment variables file"
        Validations = @("syntax", "required-vars", "security")
    }
    "tunnel-config" = @{
        Path = "config/cloudflared/config.yml"
        Type = "yaml"
        Critical = $true
        Description = "Cloudflare tunnel configuration"
        Validations = @("syntax", "tunnel-id", "ingress-rules", "credentials")
    }
    "tunnel-credentials" = @{
        Path = "config/cloudflared/credentials.json"
        Type = "json"
        Critical = $true
        Description = "Cloudflare tunnel credentials"
        Validations = @("syntax", "credentials-format", "security")
    }
    "prometheus-config" = @{
        Path = "config/prometheus/prometheus.yml"
        Type = "yaml"
        Critical = $false
        Description = "Prometheus monitoring configuration"
        Validations = @("syntax", "scrape-configs", "targets")
    }
    "grafana-datasources" = @{
        Path = "config/grafana/provisioning/datasources/datasources.yml"
        Type = "yaml"
        Critical = $false
        Description = "Grafana data sources configuration"
        Validations = @("syntax", "datasource-config")
    }
    "loki-config" = @{
        Path = "config/loki/loki.yml"
        Type = "yaml"
        Critical = $false
        Description = "Loki log aggregation configuration"
        Validations = @("syntax", "storage-config")
    }
    "promtail-config" = @{
        Path = "config/promtail/promtail.yml"
        Type = "yaml"
        Critical = $false
        Description = "Promtail log collection configuration"
        Validations = @("syntax", "scrape-configs")
    }
    "dashy-config" = @{
        Path = "config/dashy/conf.yml"
        Type = "yaml"
        Critical = $false
        Description = "Dashy dashboard configuration"
        Validations = @("syntax", "services-config")
    }
    "filebrowser-config" = @{
        Path = "config/filebrowser/filebrowser.json"
        Type = "json"
        Critical = $false
        Description = "FileBrowser configuration"
        Validations = @("syntax", "settings")
    }
}

function Test-YamlSyntax {
    param([string]$FilePath)
    
    Write-Log "Testing YAML syntax for: $FilePath"
    
    try {
        # Use PowerShell-Yaml module if available, otherwise basic validation
        if (Get-Module -ListAvailable -Name powershell-yaml) {
            Import-Module powershell-yaml -ErrorAction SilentlyContinue
            $content = Get-Content $FilePath -Raw
            $null = ConvertFrom-Yaml $content
            return @{ Valid = $true; Error = "" }
        } else {
            # Basic YAML validation using docker-compose config for compose files
            if ($FilePath -eq "docker-compose.yml") {
                docker-compose -f $FilePath config --quiet 2>$null
                if ($LASTEXITCODE -eq 0) {
                    return @{ Valid = $true; Error = "" }
                } else {
                    return @{ Valid = $false; Error = "Docker Compose validation failed" }
                }
            } else {
                # Basic structure check for other YAML files
                $content = Get-Content $FilePath -Raw
                if ($content -match '^\s*[^:]+:\s*' -and -not ($content -match '\t')) {
                    return @{ Valid = $true; Error = "" }
                } else {
                    return @{ Valid = $false; Error = "Invalid YAML structure or contains tabs" }
                }
            }
        }
    } catch {
        return @{ Valid = $false; Error = $_.Exception.Message }
    }
}

function Test-JsonSyntax {
    param([string]$FilePath)
    
    Write-Log "Testing JSON syntax for: $FilePath"
    
    try {
        $content = Get-Content $FilePath -Raw
        $null = ConvertFrom-Json $content
        return @{ Valid = $true; Error = "" }
    } catch {
        return @{ Valid = $false; Error = $_.Exception.Message }
    }
}

function Test-EnvironmentFile {
    param([string]$FilePath)
    
    Write-Log "Testing environment file: $FilePath"
    $result = @{
        SyntaxValid = $false
        RequiredVarsPresent = $false
        SecurityIssues = @()
        MissingVars = @()
        Errors = @()
    }
    
    try {
        if (-not (Test-Path $FilePath)) {
            $result.Errors += "Environment file does not exist"
            return $result
        }
        
        $content = Get-Content $FilePath
        $result.SyntaxValid = $true
        
        # Check required variables
        $requiredVars = @(
            "DOMAIN",
            "CLOUDFLARE_TUNNEL_TOKEN",
            "CLOUDFLARE_TUNNEL_ID",
            "CLOUDFLARE_ACCOUNT_TAG",
            "GRAFANA_ADMIN_PASSWORD",
            "LINKDING_SUPERUSER_PASSWORD",
            "ACTUAL_PASSWORD"
        )
        
        $presentVars = @()
        foreach ($line in $content) {
            if ($line -match '^([^#][^=]+)=(.*)$') {
                $varName = $matches[1].Trim()
                $varValue = $matches[2].Trim()
                
                if ($varName -in $requiredVars) {
                    $presentVars += $varName
                    
                    # Check for placeholder values
                    if ($varValue -match '^(YOUR_|CHANGE_|REPLACE_|TODO|FIXME)' -or $varValue -eq "") {
                        $result.SecurityIssues += "Variable $varName contains placeholder or empty value"
                    }
                    
                    # Check password strength
                    if ($varName -match "PASSWORD" -and $varValue.Length -lt 8) {
                        $result.SecurityIssues += "Password $varName is too short (minimum 8 characters)"
                    }
                }
            }
        }
        
        $result.MissingVars = $requiredVars | Where-Object { $_ -notin $presentVars }
        $result.RequiredVarsPresent = ($result.MissingVars.Count -eq 0)
        
    } catch {
        $result.Errors += "Error reading environment file: $($_.Exception.Message)"
    }
    
    return $result
}

function Test-DockerComposeConfig {
    param([string]$FilePath)
    
    Write-Log "Testing Docker Compose configuration: $FilePath"
    $result = @{
        SyntaxValid = $false
        ServicesValid = $false
        NetworksValid = $false
        VolumesValid = $false
        DependenciesValid = $false
        ServiceCount = 0
        NetworkCount = 0
        VolumeCount = 0
        Errors = @()
    }
    
    try {
        # Test syntax first
        docker-compose -f $FilePath config --quiet 2>$null
        if ($LASTEXITCODE -eq 0) {
            $result.SyntaxValid = $true
        } else {
            $result.Errors += "Docker Compose syntax validation failed"
            return $result
        }
        
        # Parse configuration
        $configOutput = docker-compose -f $FilePath config --format json 2>$null | ConvertFrom-Json
        
        if ($configOutput) {
            # Check services
            if ($configOutput.services) {
                $result.ServiceCount = $configOutput.services.PSObject.Properties.Count
                $result.ServicesValid = ($result.ServiceCount -gt 0)
                
                # Validate critical services
                $criticalServices = @("cloudflared", "prometheus", "grafana", "portainer")
                $missingCritical = @()
                
                foreach ($service in $criticalServices) {
                    if (-not $configOutput.services.$service) {
                        $missingCritical += $service
                    }
                }
                
                if ($missingCritical.Count -gt 0) {
                    $result.Errors += "Missing critical services: $($missingCritical -join ', ')"
                }
            }
            
            # Check networks
            if ($configOutput.networks) {
                $result.NetworkCount = $configOutput.networks.PSObject.Properties.Count
                $result.NetworksValid = ($result.NetworkCount -ge 3)  # frontend, backend, monitoring
                
                $expectedNetworks = @("frontend", "backend", "monitoring")
                $missingNetworks = @()
                
                foreach ($network in $expectedNetworks) {
                    if (-not $configOutput.networks.$network) {
                        $missingNetworks += $network
                    }
                }
                
                if ($missingNetworks.Count -gt 0) {
                    $result.Errors += "Missing networks: $($missingNetworks -join ', ')"
                }
            }
            
            # Check volumes
            if ($configOutput.volumes) {
                $result.VolumeCount = $configOutput.volumes.PSObject.Properties.Count
                $result.VolumesValid = ($result.VolumeCount -gt 0)
            }
            
            # Check dependencies
            $dependencyIssues = @()
            foreach ($serviceName in $configOutput.services.PSObject.Properties.Name) {
                $service = $configOutput.services.$serviceName
                
                if ($service.depends_on) {
                    foreach ($dependency in $service.depends_on.PSObject.Properties.Name) {
                        if (-not $configOutput.services.$dependency) {
                            $dependencyIssues += "Service $serviceName depends on non-existent service $dependency"
                        }
                    }
                }
            }
            
            $result.DependenciesValid = ($dependencyIssues.Count -eq 0)
            $result.Errors += $dependencyIssues
        }
        
    } catch {
        $result.Errors += "Error parsing Docker Compose configuration: $($_.Exception.Message)"
    }
    
    return $result
}

function Test-TunnelConfiguration {
    param([string]$ConfigPath, [string]$CredentialsPath)
    
    Write-Log "Testing tunnel configuration: $ConfigPath"
    $result = @{
        ConfigValid = $false
        CredentialsValid = $false
        TunnelIDValid = $false
        IngressRulesValid = $false
        Errors = @()
    }
    
    try {
        # Test config file
        if (Test-Path $ConfigPath) {
            $configContent = Get-Content $ConfigPath -Raw
            
            # Check tunnel ID
            if ($configContent -match 'tunnel:\s*([a-f0-9-]+)') {
                $tunnelId = $matches[1]
                if ($tunnelId -ne "YOUR_TUNNEL_ID" -and $tunnelId.Length -eq 36) {
                    $result.TunnelIDValid = $true
                } else {
                    $result.Errors += "Invalid or placeholder tunnel ID"
                }
            } else {
                $result.Errors += "Tunnel ID not found in configuration"
            }
            
            # Check ingress rules
            if ($configContent -match 'ingress:') {
                $ingressLines = ($configContent -split "`n" | Where-Object { $_ -match '^\s*-\s*hostname:' }).Count
                if ($ingressLines -gt 0) {
                    $result.IngressRulesValid = $true
                } else {
                    $result.Errors += "No ingress rules found"
                }
            } else {
                $result.Errors += "Ingress section not found"
            }
            
            $result.ConfigValid = ($result.TunnelIDValid -and $result.IngressRulesValid)
        } else {
            $result.Errors += "Tunnel configuration file not found"
        }
        
        # Test credentials file
        if (Test-Path $CredentialsPath) {
            try {
                $credentials = Get-Content $CredentialsPath -Raw | ConvertFrom-Json
                
                if ($credentials.AccountTag -and $credentials.TunnelSecret -and $credentials.TunnelID) {
                    $result.CredentialsValid = $true
                } else {
                    $result.Errors += "Credentials file is missing required fields"
                }
            } catch {
                $result.Errors += "Error parsing credentials file: $($_.Exception.Message)"
            }
        } else {
            $result.Errors += "Tunnel credentials file not found"
        }
        
    } catch {
        $result.Errors += "Error testing tunnel configuration: $($_.Exception.Message)"
    }
    
    return $result
}

function Test-ServiceStartupSequence {
    Write-Log "Testing service startup sequence..."
    $result = @{
        SequenceValid = $false
        CircularDependencies = @()
        OrphanedServices = @()
        Errors = @()
    }
    
    try {
        # Parse Docker Compose to get dependency graph
        $configOutput = docker-compose config --format json 2>$null | ConvertFrom-Json
        
        if ($configOutput -and $configOutput.services) {
            $services = @{}
            $dependencies = @{}
            
            # Build dependency graph
            foreach ($serviceName in $configOutput.services.PSObject.Properties.Name) {
                $service = $configOutput.services.$serviceName
                $services[$serviceName] = $service
                $dependencies[$serviceName] = @()
                
                if ($service.depends_on) {
                    foreach ($dependency in $service.depends_on.PSObject.Properties.Name) {
                        $dependencies[$serviceName] += $dependency
                    }
                }
            }
            
            # Check for circular dependencies using topological sort
            $visited = @{}
            $recursionStack = @{}
            $circularDeps = @()
            
            function Test-CircularDependency {
                param([string]$ServiceName)
                
                $visited[$ServiceName] = $true
                $recursionStack[$ServiceName] = $true
                
                foreach ($dependency in $dependencies[$ServiceName]) {
                    if (-not $visited[$dependency]) {
                        if (Test-CircularDependency $dependency) {
                            return $true
                        }
                    } elseif ($recursionStack[$dependency]) {
                        $circularDeps += "$ServiceName -> $dependency"
                        return $true
                    }
                }
                
                $recursionStack[$ServiceName] = $false
                return $false
            }
            
            foreach ($serviceName in $services.Keys) {
                if (-not $visited[$serviceName]) {
                    Test-CircularDependency $serviceName | Out-Null
                }
            }
            
            $result.CircularDependencies = $circularDeps
            $result.SequenceValid = ($circularDeps.Count -eq 0)
            
            if ($circularDeps.Count -gt 0) {
                $result.Errors += "Circular dependencies detected: $($circularDeps -join ', ')"
            }
        }
        
    } catch {
        $result.Errors += "Error testing startup sequence: $($_.Exception.Message)"
    }
    
    return $result
}

function Fix-ConfigurationIssues {
    param([hashtable]$ValidationResults)
    
    if (-not $FixIssues) {
        Write-Info "Use -FixIssues flag to automatically fix common configuration issues"
        return
    }
    
    Write-Log "Attempting to fix configuration issues..."
    $fixedIssues = @()
    
    # Fix missing directories
    $requiredDirs = @(
        "config/cloudflared",
        "config/prometheus", 
        "config/grafana/provisioning/datasources",
        "config/loki",
        "config/promtail",
        "config/dashy",
        "config/filebrowser",
        "data/files",
        "data/backups",
        "data/logs"
    )
    
    foreach ($dir in $requiredDirs) {
        if (-not (Test-Path $dir)) {
            try {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                $fixedIssues += "Created missing directory: $dir"
            } catch {
                Write-Warning "Failed to create directory $dir: $($_.Exception.Message)"
            }
        }
    }
    
    # Create basic .env template if missing
    if (-not (Test-Path ".env") -and (Test-Path ".env.template")) {
        try {
            Copy-Item ".env.template" ".env"
            $fixedIssues += "Created .env file from template"
        } catch {
            Write-Warning "Failed to create .env file: $($_.Exception.Message)"
        }
    }
    
    if ($fixedIssues.Count -gt 0) {
        Write-Success "Fixed issues:"
        foreach ($fix in $fixedIssues) {
            Write-Success "  $fix"
        }
    } else {
        Write-Info "No issues were automatically fixable"
    }
}

# Main execution
Write-Host "=== Configuration Validation ===" -ForegroundColor White
Write-Host "Validating configuration files and service startup sequences..." -ForegroundColor Cyan
Write-Host "Configuration Type: $ConfigType" -ForegroundColor Cyan
Write-Host ""

$overallSuccess = $true
$validationResults = @{}

# Filter config files based on type
$configsToTest = switch ($ConfigType.ToLower()) {
    "docker" { @("docker-compose", "environment") }
    "tunnel" { @("tunnel-config", "tunnel-credentials") }
    "monitoring" { @("prometheus-config", "grafana-datasources", "loki-config", "promtail-config") }
    "apps" { @("dashy-config", "filebrowser-config") }
    default { $ConfigFiles.Keys }
}

# Test each configuration file
foreach ($configName in $configsToTest) {
    if (-not $ConfigFiles.ContainsKey($configName)) {
        Write-Warning "Unknown configuration type: $configName"
        continue
    }
    
    $configInfo = $ConfigFiles[$configName]
    $filePath = $configInfo.Path
    
    Write-Host "Testing: $($configInfo.Description)" -ForegroundColor Yellow
    
    $result = @{
        ConfigName = $configName
        FilePath = $filePath
        Exists = (Test-Path $filePath)
        Critical = $configInfo.Critical
        ValidationResults = @{}
        Errors = @()
        Success = $false
    }
    
    if (-not $result.Exists) {
        $result.Errors += "Configuration file does not exist: $filePath"
        if ($configInfo.Critical) {
            Write-Error "Critical configuration file missing: $filePath"
            $overallSuccess = $false
        } else {
            Write-Warning "Optional configuration file missing: $filePath"
        }
    } else {
        # Test syntax based on file type
        if ($CheckSyntax) {
            switch ($configInfo.Type) {
                "yaml" {
                    $syntaxResult = Test-YamlSyntax $filePath
                    $result.ValidationResults["syntax"] = $syntaxResult
                    
                    if ($syntaxResult.Valid) {
                        Write-Success "YAML syntax is valid"
                    } else {
                        Write-Error "YAML syntax error: $($syntaxResult.Error)"
                        $result.Errors += $syntaxResult.Error
                        $overallSuccess = $false
                    }
                }
                "json" {
                    $syntaxResult = Test-JsonSyntax $filePath
                    $result.ValidationResults["syntax"] = $syntaxResult
                    
                    if ($syntaxResult.Valid) {
                        Write-Success "JSON syntax is valid"
                    } else {
                        Write-Error "JSON syntax error: $($syntaxResult.Error)"
                        $result.Errors += $syntaxResult.Error
                        $overallSuccess = $false
                    }
                }
                "env" {
                    $envResult = Test-EnvironmentFile $filePath
                    $result.ValidationResults["environment"] = $envResult
                    
                    if ($envResult.SyntaxValid -and $envResult.RequiredVarsPresent) {
                        Write-Success "Environment file is valid"
                    } else {
                        Write-Error "Environment file validation failed"
                        $result.Errors += $envResult.Errors
                        $result.Errors += $envResult.MissingVars | ForEach-Object { "Missing variable: $_" }
                        $overallSuccess = $false
                    }
                    
                    if ($envResult.SecurityIssues.Count -gt 0) {
                        foreach ($issue in $envResult.SecurityIssues) {
                            Write-Warning "Security issue: $issue"
                        }
                    }
                }
            }
        }
        
        # Specific validations
        switch ($configName) {
            "docker-compose" {
                $composeResult = Test-DockerComposeConfig $filePath
                $result.ValidationResults["compose"] = $composeResult
                
                if ($composeResult.SyntaxValid -and $composeResult.ServicesValid -and $composeResult.NetworksValid) {
                    Write-Success "Docker Compose configuration is valid"
                    Write-Info "Services: $($composeResult.ServiceCount), Networks: $($composeResult.NetworkCount), Volumes: $($composeResult.VolumeCount)"
                } else {
                    Write-Error "Docker Compose configuration validation failed"
                    $result.Errors += $composeResult.Errors
                    $overallSuccess = $false
                }
            }
            "tunnel-config" {
                $tunnelResult = Test-TunnelConfiguration $filePath "config/cloudflared/credentials.json"
                $result.ValidationResults["tunnel"] = $tunnelResult
                
                if ($tunnelResult.ConfigValid -and $tunnelResult.CredentialsValid) {
                    Write-Success "Tunnel configuration is valid"
                } else {
                    Write-Error "Tunnel configuration validation failed"
                    $result.Errors += $tunnelResult.Errors
                    $overallSuccess = $false
                }
            }
        }
        
        $result.Success = ($result.Errors.Count -eq 0)
    }
    
    # Display errors
    foreach ($error in $result.Errors) {
        Write-Error "  $error"
    }
    
    $validationResults[$configName] = $result
    Write-Host ""
}

# Test service startup sequence
Write-Host "Testing service startup sequence..." -ForegroundColor Yellow
$startupResult = Test-ServiceStartupSequence
$validationResults["startup-sequence"] = $startupResult

if ($startupResult.SequenceValid) {
    Write-Success "Service startup sequence is valid"
} else {
    Write-Error "Service startup sequence has issues"
    foreach ($error in $startupResult.Errors) {
        Write-Error "  $error"
    }
    $overallSuccess = $false
}

Write-Host ""

# Attempt to fix issues if requested
Fix-ConfigurationIssues $validationResults

# Summary
Write-Host "=== Configuration Validation Summary ===" -ForegroundColor White

$totalConfigs = $validationResults.Keys.Count
$validConfigs = ($validationResults.Values | Where-Object { $_.Success -or $_.SequenceValid }).Count
$criticalIssues = ($validationResults.Values | Where-Object { -not $_.Success -and $_.Critical }).Count

Write-Host "Total configurations tested: $totalConfigs" -ForegroundColor White
Write-Host "Valid configurations: $validConfigs" -ForegroundColor $(if ($validConfigs -eq $totalConfigs) { "Green" } else { "Yellow" })
Write-Host "Critical issues: $criticalIssues" -ForegroundColor $(if ($criticalIssues -eq 0) { "Green" } else { "Red" })

if ($overallSuccess) {
    Write-Success "All critical configuration validations passed!"
    Write-Info "Configuration is ready for deployment."
} else {
    Write-Error "Configuration validation failed."
    Write-Info "Please fix the issues above before proceeding with deployment."
}

# Recommendations
Write-Host ""
Write-Host "Recommendations:" -ForegroundColor Cyan

if ($criticalIssues -gt 0) {
    Write-Info "• Fix critical configuration issues before deployment"
}

if (-not (Test-Path ".env")) {
    Write-Info "• Create .env file from .env.template and configure required variables"
}

if ($validationResults["tunnel-config"] -and -not $validationResults["tunnel-config"].Success) {
    Write-Info "• Configure Cloudflare tunnel credentials and settings"
}

if ($overallSuccess) {
    Write-Info "• Run fresh deployment test: .\scripts\test-fresh-deployment.ps1"
    Write-Info "• Test service health: .\scripts\run-health-tests.ps1"
}

exit $(if ($overallSuccess) { 0 } else { 1 })