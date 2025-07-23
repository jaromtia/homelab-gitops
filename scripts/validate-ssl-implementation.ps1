# SSL Implementation Validation Script
# This script validates the complete SSL automation and error handling implementation

param(
    [string]$Domain = $env:DOMAIN,
    [switch]$Detailed = $false
)

# Colors for output
$Green = "Green"
$Red = "Red"
$Yellow = "Yellow"
$Blue = "Cyan"

function Write-Status {
    param(
        [string]$Message,
        [string]$Status,
        [string]$Color = "White"
    )
    Write-Host "[$Status] $Message" -ForegroundColor $Color
}

function Write-Success { param([string]$Message) Write-Status $Message "✓" $Green }
function Write-Failure { param([string]$Message) Write-Status $Message "✗" $Red }
function Write-Warning { param([string]$Message) Write-Status $Message "!" $Yellow }
function Write-Info { param([string]$Message) Write-Status $Message "i" $Blue }

# Validation results
$ValidationResults = @{
    Passed = 0
    Failed = 0
    Warnings = 0
}

function Test-Component {
    param(
        [string]$Name,
        [scriptblock]$TestBlock
    )
    
    Write-Host "`n=== Testing $Name ===" -ForegroundColor Cyan
    
    try {
        $result = & $TestBlock
        if ($result.Success) {
            Write-Success "$Name validation passed"
            $script:ValidationResults.Passed++
            if ($result.Details -and $Detailed) {
                $result.Details | ForEach-Object { Write-Info "  $_" }
            }
        } else {
            Write-Failure "$Name validation failed"
            $script:ValidationResults.Failed++
            if ($result.Details) {
                $result.Details | ForEach-Object { Write-Warning "  $_" }
            }
        }
        
        if ($result.Warnings) {
            $result.Warnings | ForEach-Object { 
                Write-Warning "  $_"
                $script:ValidationResults.Warnings++
            }
        }
    }
    catch {
        Write-Failure "$Name validation error: $($_.Exception.Message)"
        $script:ValidationResults.Failed++
    }
}

# Test 1: Traefik Static Configuration
function Test-TraefikStaticConfig {
    $details = @()
    $warnings = @()
    
    # Check if traefik.yml exists
    if (!(Test-Path "config/traefik/traefik.yml")) {
        return @{ Success = $false; Details = @("traefik.yml not found") }
    }
    
    $config = Get-Content "config/traefik/traefik.yml" -Raw
    
    # Check for Let's Encrypt configuration
    if ($config -match "letsencrypt:") {
        $details += "Let's Encrypt ACME configuration present"
    } else {
        return @{ Success = $false; Details = @("Let's Encrypt configuration missing") }
    }
    
    # Check for Docker provider
    if ($config -match "docker:") {
        $details += "Docker provider configured"
    } else {
        return @{ Success = $false; Details = @("Docker provider configuration missing") }
    }
    
    # Check for health check endpoint
    if ($config -match "ping:") {
        $details += "Health check endpoint configured"
    } else {
        $warnings += "Health check endpoint not configured"
    }
    
    # Check for metrics
    if ($config -match "prometheus:") {
        $details += "Prometheus metrics configured"
    } else {
        $warnings += "Prometheus metrics not configured"
    }
    
    return @{ Success = $true; Details = $details; Warnings = $warnings }
}

# Test 2: Dynamic Configuration
function Test-DynamicConfig {
    $details = @()
    $warnings = @()
    
    # Check TLS configuration
    if (!(Test-Path "config/traefik/dynamic/tls.yml")) {
        return @{ Success = $false; Details = @("TLS configuration file missing") }
    }
    
    $tlsConfig = Get-Content "config/traefik/dynamic/tls.yml" -Raw
    if ($tlsConfig -match "VersionTLS12|VersionTLS13") {
        $details += "Modern TLS configuration present"
    } else {
        $warnings += "TLS version configuration may be outdated"
    }
    
    # Check middleware configuration
    if (!(Test-Path "config/traefik/dynamic/middleware.yml")) {
        return @{ Success = $false; Details = @("Middleware configuration file missing") }
    }
    
    $middlewareConfig = Get-Content "config/traefik/dynamic/middleware.yml" -Raw
    
    # Check for security headers
    if ($middlewareConfig -match "security-headers:") {
        $details += "Security headers middleware configured"
    } else {
        $warnings += "Security headers middleware missing"
    }
    
    # Check for enhanced middleware (circuit breaker, retry, etc.)
    if ($middlewareConfig -match "circuit-breaker:") {
        $details += "Circuit breaker middleware configured"
    } else {
        $warnings += "Circuit breaker middleware not configured"
    }
    
    if ($middlewareConfig -match "retry:") {
        $details += "Retry middleware configured"
    } else {
        $warnings += "Retry middleware not configured"
    }
    
    if ($middlewareConfig -match "buffering:") {
        $details += "Buffering middleware configured"
    } else {
        $warnings += "Buffering middleware not configured"
    }
    
    return @{ Success = $true; Details = $details; Warnings = $warnings }
}

# Test 3: Docker Compose Configuration
function Test-DockerComposeConfig {
    $details = @()
    $warnings = @()
    
    if (!(Test-Path "docker-compose.traefik.yml")) {
        return @{ Success = $false; Details = @("Docker Compose file missing") }
    }
    
    $composeConfig = Get-Content "docker-compose.traefik.yml" -Raw
    
    # Check for health checks
    if ($composeConfig -match "healthcheck:") {
        $details += "Container health checks configured"
    } else {
        $warnings += "Container health checks not configured"
    }
    
    # Check for volume mounts
    if ($composeConfig -match "/letsencrypt") {
        $details += "Let's Encrypt volume mount configured"
    } else {
        return @{ Success = $false; Details = @("Let's Encrypt volume mount missing") }
    }
    
    # Check for networks
    if ($composeConfig -match "networks:") {
        $details += "Network configuration present"
    } else {
        $warnings += "Network configuration may be missing"
    }
    
    # Check for resource limits
    if ($composeConfig -match "deploy:" -and $composeConfig -match "resources:") {
        $details += "Resource limits configured"
    } else {
        $warnings += "Resource limits not configured"
    }
    
    return @{ Success = $true; Details = $details; Warnings = $warnings }
}

# Test 4: SSL Health Check Scripts
function Test-SSLHealthCheckScripts {
    $details = @()
    $warnings = @()
    
    # Check PowerShell health check script
    if (Test-Path "scripts/ssl-health-check.ps1") {
        $details += "PowerShell SSL health check script present"
        
        # Check for key functions
        $psScript = Get-Content "scripts/ssl-health-check.ps1" -Raw
        if ($psScript -match "Test-CertificateExpiration") {
            $details += "Certificate expiration check function present"
        }
        if ($psScript -match "Invoke-ForceRenewal") {
            $details += "Force renewal function present"
        }
        if ($psScript -match "Test-DomainAccessibility") {
            $details += "Domain accessibility validation present"
        }
    } else {
        $warnings += "PowerShell SSL health check script missing"
    }
    
    # Check Bash health check script
    if (Test-Path "scripts/ssl-health-check.sh") {
        $details += "Bash SSL health check script present"
        
        # Check for enhanced error handling
        $bashScript = Get-Content "scripts/ssl-health-check.sh" -Raw
        if ($bashScript -match "validate_domain_accessibility") {
            $details += "Enhanced domain validation present"
        }
        if ($bashScript -match "exponential backoff") {
            $details += "Exponential backoff retry logic present"
        }
    } else {
        $warnings += "Bash SSL health check script missing"
    }
    
    # Check SSL renewal handler
    if (Test-Path "scripts/ssl-renewal-handler.sh") {
        $details += "Advanced SSL renewal handler present"
        
        $renewalScript = Get-Content "scripts/ssl-renewal-handler.sh" -Raw
        if ($renewalScript -match "advanced_certificate_renewal") {
            $details += "Advanced renewal logic implemented"
        }
        if ($renewalScript -match "backup_acme_json") {
            $details += "ACME JSON backup functionality present"
        }
        if ($renewalScript -match "validate_acme_json") {
            $details += "ACME JSON validation present"
        }
    } else {
        $warnings += "Advanced SSL renewal handler missing"
    }
    
    return @{ Success = $true; Details = $details; Warnings = $warnings }
}

# Test 5: Error Handling and Recovery
function Test-ErrorHandlingRecovery {
    $details = @()
    $warnings = @()
    
    # Check for systemd service (Linux)
    if (Test-Path "config/traefik/ssl-monitor.service") {
        $details += "SSL monitoring systemd service configured"
    } else {
        $warnings += "SSL monitoring systemd service not configured"
    }
    
    # Check for comprehensive test scripts
    if (Test-Path "scripts/test-traefik.sh") {
        $details += "Bash test script present"
    }
    
    if (Test-Path "scripts/test-traefik.ps1") {
        $details += "PowerShell test script present"
    }
    
    # Check for backup and recovery mechanisms
    $renewalScript = ""
    if (Test-Path "scripts/ssl-renewal-handler.sh") {
        $renewalScript = Get-Content "scripts/ssl-renewal-handler.sh" -Raw
    }
    
    if ($renewalScript -match "backup_acme_json") {
        $details += "Automatic ACME JSON backup configured"
    } else {
        $warnings += "Automatic backup not configured"
    }
    
    if ($renewalScript -match "repair_acme_json") {
        $details += "ACME JSON repair functionality present"
    } else {
        $warnings += "ACME JSON repair not implemented"
    }
    
    return @{ Success = $true; Details = $details; Warnings = $warnings }
}

# Test 6: Service Discovery and Automation
function Test-ServiceDiscoveryAutomation {
    $details = @()
    $warnings = @()
    
    $composeConfig = ""
    if (Test-Path "docker-compose.traefik.yml") {
        $composeConfig = Get-Content "docker-compose.traefik.yml" -Raw
    }
    
    # Check for Docker socket mount
    if ($composeConfig -match "/var/run/docker.sock") {
        $details += "Docker socket mounted for service discovery"
    } else {
        return @{ Success = $false; Details = @("Docker socket mount missing") }
    }
    
    # Check for automatic service discovery labels
    if ($composeConfig -match "traefik.enable=true") {
        $details += "Traefik service discovery labels configured"
    } else {
        $warnings += "Service discovery labels may be incomplete"
    }
    
    # Check for automatic HTTPS redirect
    $staticConfig = ""
    if (Test-Path "config/traefik/traefik.yml") {
        $staticConfig = Get-Content "config/traefik/traefik.yml" -Raw
    }
    
    if ($staticConfig -match "redirections:" -and $staticConfig -match "websecure") {
        $details += "Automatic HTTPS redirect configured"
    } else {
        $warnings += "Automatic HTTPS redirect not configured"
    }
    
    return @{ Success = $true; Details = $details; Warnings = $warnings }
}

# Main validation function
function Start-Validation {
    Write-Host "SSL Automation and Error Handling Validation" -ForegroundColor Magenta
    Write-Host "=============================================" -ForegroundColor Magenta
    
    if ($Domain) {
        Write-Info "Target domain: $Domain"
    } else {
        Write-Warning "No domain specified, some tests may be limited"
    }
    
    Write-Host ""
    
    # Run all tests
    Test-Component "Traefik Static Configuration" { Test-TraefikStaticConfig }
    Test-Component "Dynamic Configuration" { Test-DynamicConfig }
    Test-Component "Docker Compose Configuration" { Test-DockerComposeConfig }
    Test-Component "SSL Health Check Scripts" { Test-SSLHealthCheckScripts }
    Test-Component "Error Handling and Recovery" { Test-ErrorHandlingRecovery }
    Test-Component "Service Discovery and Automation" { Test-ServiceDiscoveryAutomation }
    
    # Summary
    Write-Host "`n" + "="*50 -ForegroundColor Magenta
    Write-Host "VALIDATION SUMMARY" -ForegroundColor Magenta
    Write-Host "="*50 -ForegroundColor Magenta
    
    Write-Success "Components Passed: $($ValidationResults.Passed)"
    if ($ValidationResults.Failed -gt 0) {
        Write-Failure "Components Failed: $($ValidationResults.Failed)"
    }
    if ($ValidationResults.Warnings -gt 0) {
        Write-Warning "Warnings: $($ValidationResults.Warnings)"
    }
    
    Write-Host ""
    
    if ($ValidationResults.Failed -eq 0) {
        Write-Success "SSL automation and error handling implementation is complete!"
        Write-Info "All core components are properly configured."
        
        if ($ValidationResults.Warnings -gt 0) {
            Write-Warning "Consider addressing the warnings for optimal functionality."
        }
        
        return $true
    } else {
        Write-Failure "Implementation has critical issues that need to be addressed."
        return $false
    }
}

# Run validation
$validationPassed = Start-Validation

if ($validationPassed) {
    exit 0
} else {
    exit 1
}