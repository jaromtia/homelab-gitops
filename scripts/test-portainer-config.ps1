# Portainer Configuration Test Script
# This script tests Portainer configuration without requiring Docker to be running

Write-Host "=== Portainer Configuration Test ===" -ForegroundColor Green
Write-Host "Testing Portainer configuration files and setup..." -ForegroundColor Yellow

$ErrorCount = 0

# Function to log test results
function Write-TestResult {
    param(
        [string]$Test,
        [string]$Status,
        [string]$Message = ""
    )
    
    $color = switch ($Status) {
        "PASS" { "Green" }
        "FAIL" { "Red"; $script:ErrorCount++ }
        "WARN" { "Yellow" }
        default { "White" }
    }
    
    Write-Host "[$Status] $Test" -ForegroundColor $color
    if ($Message) {
        Write-Host "    $Message" -ForegroundColor Gray
    }
}

# Test 1: Docker Compose Configuration
Write-Host "`n1. Testing Docker Compose configuration..." -ForegroundColor Cyan
try {
    $composeFile = "docker-compose.yml"
    if (Test-Path $composeFile) {
        $composeContent = Get-Content $composeFile -Raw
        
        # Check if Portainer service is defined
        if ($composeContent -match "portainer:") {
            Write-TestResult "Portainer Service Definition" "PASS" "Service found in docker-compose.yml"
            
            # Check key configuration elements
            if ($composeContent -match "portainer/portainer-ce:latest") {
                Write-TestResult "Container Image" "PASS" "Using official Portainer CE image"
            } else {
                Write-TestResult "Container Image" "FAIL" "Portainer image not properly configured"
            }
            
            if ($composeContent -match "/var/run/docker.sock:/var/run/docker.sock") {
                Write-TestResult "Docker Socket Mount" "PASS" "Docker socket properly mounted"
            } else {
                Write-TestResult "Docker Socket Mount" "FAIL" "Docker socket mount missing"
            }
            
            if ($composeContent -match "portainer_data:/data") {
                Write-TestResult "Data Persistence" "PASS" "Data volume properly configured"
            } else {
                Write-TestResult "Data Persistence" "FAIL" "Data volume not configured"
            }
            
            if ($composeContent -match "9000:9000") {
                Write-TestResult "Port Configuration" "PASS" "Port 9000 properly mapped"
            } else {
                Write-TestResult "Port Configuration" "FAIL" "Port mapping not configured"
            }
            
        } else {
            Write-TestResult "Portainer Service Definition" "FAIL" "Portainer service not found in docker-compose.yml"
        }
    } else {
        Write-TestResult "Docker Compose File" "FAIL" "docker-compose.yml not found"
    }
} catch {
    Write-TestResult "Docker Compose Configuration" "FAIL" "Error reading configuration: $($_.Exception.Message)"
}

# Test 2: Configuration Files
Write-Host "`n2. Testing configuration files..." -ForegroundColor Cyan
$configFiles = @{
    "config/portainer/README.md" = "Documentation file"
    "config/portainer/setup-portainer.ps1" = "Setup script"
    "config/portainer/manage-containers.ps1" = "Management utilities"
    "config/portainer/monitoring-dashboard.json" = "Grafana dashboard"
}

foreach ($file in $configFiles.Keys) {
    if (Test-Path $file) {
        $fileSize = (Get-Item $file).Length
        Write-TestResult "Config File: $(Split-Path -Leaf $file)" "PASS" "$($configFiles[$file]) ($fileSize bytes)"
    } else {
        Write-TestResult "Config File: $(Split-Path -Leaf $file)" "FAIL" "$($configFiles[$file]) missing"
    }
}

# Test 3: Cloudflare Tunnel Configuration
Write-Host "`n3. Testing Cloudflare tunnel configuration..." -ForegroundColor Cyan
try {
    $tunnelConfig = "config/cloudflared/config.yml"
    if (Test-Path $tunnelConfig) {
        $tunnelContent = Get-Content $tunnelConfig -Raw
        
        if ($tunnelContent -match "portainer\.\$\{DOMAIN\}") {
            Write-TestResult "Tunnel Hostname" "PASS" "Portainer hostname configured in tunnel"
        } else {
            Write-TestResult "Tunnel Hostname" "FAIL" "Portainer hostname not found in tunnel config"
        }
        
        if ($tunnelContent -match "http://portainer:9000") {
            Write-TestResult "Tunnel Service" "PASS" "Portainer service properly routed"
        } else {
            Write-TestResult "Tunnel Service" "FAIL" "Portainer service routing not configured"
        }
    } else {
        Write-TestResult "Tunnel Configuration" "FAIL" "Cloudflare tunnel config not found"
    }
} catch {
    Write-TestResult "Tunnel Configuration" "FAIL" "Error reading tunnel config: $($_.Exception.Message)"
}

# Test 4: Network Configuration
Write-Host "`n4. Testing network configuration..." -ForegroundColor Cyan
try {
    $composeContent = Get-Content "docker-compose.yml" -Raw
    
    if ($composeContent -match "networks:\s*-\s*frontend\s*-\s*backend") {
        Write-TestResult "Network Assignment" "PASS" "Portainer connected to frontend and backend networks"
    } elseif ($composeContent -match "frontend" -and $composeContent -match "backend") {
        Write-TestResult "Network Assignment" "PASS" "Portainer connected to required networks"
    } else {
        Write-TestResult "Network Assignment" "WARN" "Network configuration may need verification"
    }
} catch {
    Write-TestResult "Network Configuration" "FAIL" "Error checking network config: $($_.Exception.Message)"
}

# Test 5: Health Check Configuration
Write-Host "`n5. Testing health check configuration..." -ForegroundColor Cyan
try {
    $composeContent = Get-Content "docker-compose.yml" -Raw
    
    if ($composeContent -match "healthcheck:") {
        Write-TestResult "Health Check Definition" "PASS" "Health check configured"
        
        if ($composeContent -match "/api/status") {
            Write-TestResult "Health Check Endpoint" "PASS" "Using Portainer API status endpoint"
        } else {
            Write-TestResult "Health Check Endpoint" "WARN" "Health check endpoint may need verification"
        }
    } else {
        Write-TestResult "Health Check Definition" "FAIL" "Health check not configured"
    }
} catch {
    Write-TestResult "Health Check Configuration" "FAIL" "Error checking health check config: $($_.Exception.Message)"
}

# Test 6: Validation Scripts
Write-Host "`n6. Testing validation scripts..." -ForegroundColor Cyan
$validationScripts = @(
    "scripts/validate-portainer.ps1"
)

foreach ($script in $validationScripts) {
    if (Test-Path $script) {
        try {
            # Test script syntax by parsing it
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $script -Raw), [ref]$null)
            Write-TestResult "Validation Script: $(Split-Path -Leaf $script)" "PASS" "Script syntax is valid"
        } catch {
            Write-TestResult "Validation Script: $(Split-Path -Leaf $script)" "FAIL" "Script has syntax errors"
        }
    } else {
        Write-TestResult "Validation Script: $(Split-Path -Leaf $script)" "FAIL" "Script not found"
    }
}

# Test 7: Documentation
Write-Host "`n7. Testing documentation..." -ForegroundColor Cyan
$docFiles = @(
    "docs/portainer-implementation.md"
)

foreach ($doc in $docFiles) {
    if (Test-Path $doc) {
        $docSize = (Get-Item $doc).Length
        Write-TestResult "Documentation: $(Split-Path -Leaf $doc)" "PASS" "Documentation available ($docSize bytes)"
    } else {
        Write-TestResult "Documentation: $(Split-Path -Leaf $doc)" "FAIL" "Documentation missing"
    }
}

# Summary
Write-Host "`n" + ("=" * 60) -ForegroundColor Gray
Write-Host "CONFIGURATION TEST SUMMARY" -ForegroundColor White
Write-Host ("=" * 60) -ForegroundColor Gray

if ($ErrorCount -eq 0) {
    Write-Host "✓ All configuration tests passed!" -ForegroundColor Green
    Write-Host "Portainer is properly configured and ready for deployment." -ForegroundColor Green
} else {
    Write-Host "✗ Configuration tests completed with $ErrorCount error(s)" -ForegroundColor Red
    Write-Host "Please fix the configuration issues before deploying Portainer." -ForegroundColor Red
}

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Start Docker Desktop" -ForegroundColor White
Write-Host "2. Run: docker-compose up -d portainer" -ForegroundColor White
Write-Host "3. Run: .\scripts\validate-portainer.ps1" -ForegroundColor White
Write-Host "4. Access: http://localhost:9000" -ForegroundColor White

exit $ErrorCount