# Traefik Configuration Test Script (PowerShell)
# This script validates Traefik configuration and SSL setup on Windows

param(
    [string]$Domain = $env:DOMAIN,
    [string]$TraefikContainer = "traefik",
    [int]$TestTimeout = 30
)

# Test results
$TestsPassed = 0
$TestsFailed = 0

# Logging functions
function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

# Test function wrapper
function Invoke-Test {
    param(
        [string]$TestName,
        [scriptblock]$TestFunction
    )
    
    Write-Host "Running test: $TestName"
    try {
        $result = & $TestFunction
        if ($result) {
            Write-Info "✓ $TestName PASSED"
            $script:TestsPassed++
        } else {
            Write-Error "✗ $TestName FAILED"
            $script:TestsFailed++
        }
    }
    catch {
        Write-Error "✗ $TestName FAILED: $($_.Exception.Message)"
        $script:TestsFailed++
    }
    Write-Host ""
}

# Test 1: Configuration file validation
function Test-ConfigFiles {
    $configFiles = @(
        "config/traefik/traefik.yml",
        "config/traefik/dynamic/tls.yml",
        "config/traefik/dynamic/middleware.yml",
        "docker-compose.traefik.yml"
    )
    
    foreach ($file in $configFiles) {
        if (!(Test-Path $file)) {
            Write-Error "Configuration file missing: $file"
            return $false
        }
    }
    
    return $true
}

# Test 2: Docker Compose validation
function Test-DockerCompose {
    try {
        $result = docker-compose -f docker-compose.traefik.yml config 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Docker Compose configuration is invalid"
            return $false
        }
        return $true
    }
    catch {
        Write-Error "Docker Compose validation failed: $($_.Exception.Message)"
        return $false
    }
}

# Test 3: Environment variables
function Test-Environment {
    $requiredVars = @("DOMAIN", "ACME_EMAIL", "TRAEFIK_DASHBOARD_USER", "TRAEFIK_DASHBOARD_PASSWORD_HASH")
    
    foreach ($var in $requiredVars) {
        $value = [Environment]::GetEnvironmentVariable($var)
        if ([string]::IsNullOrEmpty($value)) {
            Write-Error "Required environment variable not set: $var"
            return $false
        }
    }
    
    return $true
}

# Test 4: Container startup
function Test-ContainerStartup {
    Write-Info "Starting Traefik container..."
    
    try {
        docker-compose -f docker-compose.traefik.yml up -d 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to start Traefik container"
            return $false
        }
        
        # Wait for container to be ready
        $retries = $TestTimeout
        while ($retries -gt 0) {
            $containers = docker ps --filter "name=$TraefikContainer" --filter "status=running" --format "{{.Names}}"
            if ($containers -contains $TraefikContainer) {
                Write-Info "Container started successfully"
                return $true
            }
            Start-Sleep -Seconds 1
            $retries--
        }
        
        Write-Error "Container failed to start within timeout"
        return $false
    }
    catch {
        Write-Error "Container startup failed: $($_.Exception.Message)"
        return $false
    }
}

# Test 5: Health check endpoint
function Test-HealthEndpoint {
    $retries = $TestTimeout
    
    while ($retries -gt 0) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:8080/ping" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                Write-Info "Health endpoint responding"
                return $true
            }
        }
        catch {
            # Continue trying
        }
        Start-Sleep -Seconds 1
        $retries--
    }
    
    Write-Error "Health endpoint not responding"
    return $false
}

# Test 6: Dashboard access
function Test-DashboardAccess {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080/dashboard/" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Info "Dashboard accessible"
            return $true
        }
    }
    catch {
        Write-Error "Dashboard not accessible: $($_.Exception.Message)"
        return $false
    }
    
    return $false
}

# Test 7: Metrics endpoint
function Test-MetricsEndpoint {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080/metrics" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ($response.Content -match "traefik_") {
            Write-Info "Metrics endpoint working"
            return $true
        }
    }
    catch {
        Write-Error "Metrics endpoint not working: $($_.Exception.Message)"
        return $false
    }
    
    return $false
}

# Test 8: Volume mounts
function Test-VolumeMounts {
    $volumes = @(
        "/var/run/docker.sock",
        "/etc/traefik/traefik.yml",
        "/etc/traefik/dynamic",
        "/letsencrypt"
    )
    
    foreach ($volume in $volumes) {
        try {
            docker exec $TraefikContainer ls $volume 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Volume mount not accessible: $volume"
                return $false
            }
        }
        catch {
            Write-Error "Volume mount check failed for: $volume"
            return $false
        }
    }
    
    Write-Info "All volume mounts accessible"
    return $true
}

# Test 9: Docker provider functionality
function Test-DockerProvider {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080/api/http/services" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ($response.Content -match "traefik") {
            Write-Info "Docker provider discovering services"
            return $true
        }
    }
    catch {
        Write-Error "Docker provider not working: $($_.Exception.Message)"
        return $false
    }
    
    return $false
}

# Test 10: SSL renewal error handling
function Test-SSLRenewalErrorHandling {
    Write-Info "Testing SSL renewal error handling capabilities..."
    
    # Test SSL health check script exists
    if (!(Test-Path "scripts/ssl-health-check.ps1")) {
        Write-Error "SSL health check script not found"
        return $false
    }
    
    # Test SSL renewal handler script exists
    if (!(Test-Path "scripts/ssl-renewal-handler.sh")) {
        Write-Error "SSL renewal handler script not found"
        return $false
    }
    
    # Test ACME storage directory accessibility
    try {
        docker exec $TraefikContainer ls /letsencrypt 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Info "ACME storage directory accessible for error recovery"
            return $true
        } else {
            Write-Error "ACME storage directory not accessible"
            return $false
        }
    }
    catch {
        Write-Error "ACME storage accessibility check failed"
        return $false
    }
}

# Test 11: Enhanced middleware functionality
function Test-EnhancedMiddleware {
    Write-Info "Testing enhanced middleware functionality..."
    
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080/api/http/middlewares" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ($response.Content -match "security-headers|rate-limit|circuit-breaker") {
            Write-Info "Enhanced middleware configurations loaded"
            return $true
        } else {
            Write-Error "Enhanced middleware configurations not loaded"
            return $false
        }
    }
    catch {
        Write-Error "Enhanced middleware test failed: $($_.Exception.Message)"
        return $false
    }
}

# Cleanup function
function Invoke-Cleanup {
    Write-Info "Cleaning up test environment..."
    try {
        docker-compose -f docker-compose.traefik.yml down -v 2>&1 | Out-Null
    }
    catch {
        Write-Warn "Cleanup may have failed: $($_.Exception.Message)"
    }
}

# Main test execution
function Main {
    Write-Host "Starting Traefik Configuration Tests (PowerShell)"
    Write-Host "=============================================="
    Write-Host ""
    
    # Load environment variables if .env exists
    if (Test-Path ".env") {
        Get-Content ".env" | ForEach-Object {
            if ($_ -match "^([^#][^=]+)=(.*)$") {
                [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
            }
        }
        Write-Info "Loaded environment variables from .env"
    }
    
    # Run tests
    Invoke-Test "Configuration Files" { Test-ConfigFiles }
    Invoke-Test "Docker Compose Validation" { Test-DockerCompose }
    Invoke-Test "Environment Variables" { Test-Environment }
    Invoke-Test "Container Startup" { Test-ContainerStartup }
    Invoke-Test "Health Endpoint" { Test-HealthEndpoint }
    Invoke-Test "Dashboard Access" { Test-DashboardAccess }
    Invoke-Test "Metrics Endpoint" { Test-MetricsEndpoint }
    Invoke-Test "Volume Mounts" { Test-VolumeMounts }
    Invoke-Test "Docker Provider" { Test-DockerProvider }
    Invoke-Test "SSL Renewal Error Handling" { Test-SSLRenewalErrorHandling }
    Invoke-Test "Enhanced Middleware" { Test-EnhancedMiddleware }
    
    # Test summary
    Write-Host "Test Summary"
    Write-Host "============"
    Write-Host "Tests Passed: $TestsPassed"
    Write-Host "Tests Failed: $TestsFailed"
    Write-Host ""
    
    if ($TestsFailed -eq 0) {
        Write-Info "All tests passed! Traefik configuration is working correctly."
        Invoke-Cleanup
        exit 0
    } else {
        Write-Error "Some tests failed. Please check the configuration."
        Invoke-Cleanup
        exit 1
    }
}

# Run main function
Main