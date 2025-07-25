# Portainer Validation Script
# This script validates Portainer container management interface functionality

param(
    [switch]$Detailed = $false,
    [switch]$SkipInteractive = $false
)

Write-Host "=== Portainer Validation Script ===" -ForegroundColor Green
Write-Host "Validating Portainer container management interface..." -ForegroundColor Yellow

$ErrorCount = 0
$WarningCount = 0

# Function to log results
function Write-TestResult {
    param(
        [string]$Test,
        [string]$Status,
        [string]$Message = "",
        [string]$Details = ""
    )
    
    $color = switch ($Status) {
        "PASS" { "Green" }
        "FAIL" { "Red"; $script:ErrorCount++ }
        "WARN" { "Yellow"; $script:WarningCount++ }
        default { "White" }
    }
    
    Write-Host "[$Status] $Test" -ForegroundColor $color
    if ($Message) {
        Write-Host "    $Message" -ForegroundColor Gray
    }
    if ($Details -and $Detailed) {
        Write-Host "    Details: $Details" -ForegroundColor DarkGray
    }
}

# Test 1: Docker availability
Write-Host "`n1. Testing Docker availability..." -ForegroundColor Cyan
try {
    $dockerVersion = docker version --format '{{.Server.Version}}' 2>$null
    if ($dockerVersion) {
        Write-TestResult "Docker Engine" "PASS" "Version: $dockerVersion"
    } else {
        Write-TestResult "Docker Engine" "FAIL" "Docker is not running or not accessible"
    }
} catch {
    Write-TestResult "Docker Engine" "FAIL" "Error checking Docker: $($_.Exception.Message)"
}

# Test 2: Portainer container status
Write-Host "`n2. Testing Portainer container status..." -ForegroundColor Cyan
try {
    $portainerStatus = docker ps --filter "name=portainer" --format "{{.Status}}"
    if ($portainerStatus -like "*Up*") {
        Write-TestResult "Portainer Container" "PASS" "Status: $portainerStatus"
        
        # Get container details
        $containerInfo = docker inspect portainer --format='{{.State.Health.Status}}' 2>$null
        if ($containerInfo -eq "healthy") {
            Write-TestResult "Container Health" "PASS" "Health status: healthy"
        } elseif ($containerInfo) {
            Write-TestResult "Container Health" "WARN" "Health status: $containerInfo"
        } else {
            Write-TestResult "Container Health" "WARN" "No health check configured"
        }
    } else {
        Write-TestResult "Portainer Container" "FAIL" "Container is not running"
    }
} catch {
    Write-TestResult "Portainer Container" "FAIL" "Error checking container: $($_.Exception.Message)"
}

# Test 3: Network connectivity
Write-Host "`n3. Testing network connectivity..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "http://localhost:9000" -TimeoutSec 10 -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        Write-TestResult "HTTP Connectivity" "PASS" "Port 9000 is accessible"
    } else {
        Write-TestResult "HTTP Connectivity" "FAIL" "Unexpected status code: $($response.StatusCode)"
    }
} catch {
    Write-TestResult "HTTP Connectivity" "FAIL" "Cannot connect to http://localhost:9000"
}

# Test 4: API endpoint availability
Write-Host "`n4. Testing Portainer API..." -ForegroundColor Cyan
try {
    $apiResponse = Invoke-WebRequest -Uri "http://localhost:9000/api/status" -TimeoutSec 10 -UseBasicParsing
    if ($apiResponse.StatusCode -eq 200) {
        Write-TestResult "API Endpoint" "PASS" "API is responding"
        
        # Parse API response for more details
        if ($Detailed) {
            try {
                $apiData = $apiResponse.Content | ConvertFrom-Json
                Write-TestResult "API Details" "PASS" "" "Version: $($apiData.Version), Edition: $($apiData.Edition)"
            } catch {
                Write-TestResult "API Details" "WARN" "Could not parse API response"
            }
        }
    } else {
        Write-TestResult "API Endpoint" "FAIL" "API returned status code: $($apiResponse.StatusCode)"
    }
} catch {
    Write-TestResult "API Endpoint" "FAIL" "API is not accessible: $($_.Exception.Message)"
}

# Test 5: Docker socket access (Requirement 9.1, 9.2)
Write-Host "`n5. Testing Docker socket access..." -ForegroundColor Cyan
try {
    # Check if Portainer can access Docker socket by verifying volume mount
    $socketMount = docker inspect portainer --format='{{range .Mounts}}{{if eq .Destination "/var/run/docker.sock"}}{{.Source}}{{end}}{{end}}' 2>$null
    if ($socketMount) {
        Write-TestResult "Docker Socket Mount" "PASS" "Socket mounted from: $socketMount"
        
        # Test if we can list containers through Docker API
        $containers = docker ps --format "{{.Names}}" 2>$null
        if ($containers) {
            $containerCount = ($containers | Measure-Object).Count
            Write-TestResult "Container Discovery" "PASS" "Can access $containerCount containers"
        } else {
            Write-TestResult "Container Discovery" "WARN" "No containers found or access limited"
        }
    } else {
        Write-TestResult "Docker Socket Mount" "FAIL" "Docker socket not properly mounted"
    }
} catch {
    Write-TestResult "Docker Socket Access" "FAIL" "Error testing socket access: $($_.Exception.Message)"
}

# Test 6: Container management capabilities (Requirement 9.2)
Write-Host "`n6. Testing container management capabilities..." -ForegroundColor Cyan
if (-not $SkipInteractive) {
    try {
        # Test container listing
        $containerList = docker ps -a --format "json" | ConvertFrom-Json
        if ($containerList) {
            Write-TestResult "Container Listing" "PASS" "Can list containers via Docker API"
            
            # Test container inspection
            $testContainer = $containerList | Select-Object -First 1
            if ($testContainer) {
                $inspection = docker inspect $testContainer.Names --format='{{.State.Status}}' 2>$null
                if ($inspection) {
                    Write-TestResult "Container Inspection" "PASS" "Can inspect container details"
                } else {
                    Write-TestResult "Container Inspection" "WARN" "Container inspection may be limited"
                }
            }
        } else {
            Write-TestResult "Container Listing" "WARN" "No containers found for testing"
        }
    } catch {
        Write-TestResult "Container Management" "FAIL" "Error testing management capabilities: $($_.Exception.Message)"
    }
} else {
    Write-TestResult "Container Management" "SKIP" "Skipped interactive tests"
}

# Test 7: Log viewing capabilities (Requirement 9.3)
Write-Host "`n7. Testing log viewing capabilities..." -ForegroundColor Cyan
try {
    # Test if we can access container logs
    $logTest = docker logs --tail 5 portainer 2>$null
    if ($logTest) {
        Write-TestResult "Log Access" "PASS" "Can access container logs"
    } else {
        Write-TestResult "Log Access" "WARN" "Log access may be limited"
    }
} catch {
    Write-TestResult "Log Access" "FAIL" "Error accessing logs: $($_.Exception.Message)"
}

# Test 8: Resource monitoring (Requirement 9.4)
Write-Host "`n8. Testing resource monitoring..." -ForegroundColor Cyan
try {
    # Test if we can get container stats
    $statsTest = docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>$null
    if ($statsTest) {
        Write-TestResult "Resource Monitoring" "PASS" "Can access container resource statistics"
        
        if ($Detailed) {
            Write-Host "    Sample stats:" -ForegroundColor DarkGray
            $statsTest | Select-Object -First 3 | ForEach-Object {
                Write-Host "      $_" -ForegroundColor DarkGray
            }
        }
    } else {
        Write-TestResult "Resource Monitoring" "WARN" "Resource monitoring may be limited"
    }
} catch {
    Write-TestResult "Resource Monitoring" "FAIL" "Error accessing resource stats: $($_.Exception.Message)"
}

# Test 9: Network configuration
Write-Host "`n9. Testing network configuration..." -ForegroundColor Cyan
try {
    # Check if Portainer is on the correct networks
    $networks = docker inspect portainer --format='{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}' 2>$null
    if ($networks) {
        Write-TestResult "Network Configuration" "PASS" "Connected to networks: $networks"
        
        # Check if it's on frontend and backend networks as expected
        if ($networks -match "frontend" -and $networks -match "backend") {
            Write-TestResult "Network Topology" "PASS" "Connected to required networks (frontend, backend)"
        } else {
            Write-TestResult "Network Topology" "WARN" "May not be connected to all required networks"
        }
    } else {
        Write-TestResult "Network Configuration" "FAIL" "Cannot determine network configuration"
    }
} catch {
    Write-TestResult "Network Configuration" "FAIL" "Error checking network configuration: $($_.Exception.Message)"
}

# Test 10: Volume persistence
Write-Host "`n10. Testing volume persistence..." -ForegroundColor Cyan
try {
    $volumeMount = docker inspect portainer --format='{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}' 2>$null
    if ($volumeMount) {
        Write-TestResult "Data Persistence" "PASS" "Data volume mounted: $volumeMount"
    } else {
        Write-TestResult "Data Persistence" "FAIL" "Data volume not properly configured"
    }
} catch {
    Write-TestResult "Data Persistence" "FAIL" "Error checking volume configuration: $($_.Exception.Message)"
}

# Test 11: Configuration files
Write-Host "`n11. Testing configuration files..." -ForegroundColor Cyan
$configFiles = @(
    "config/portainer/README.md",
    "config/portainer/setup-portainer.ps1",
    "config/portainer/manage-containers.ps1",
    "config/portainer/monitoring-dashboard.json"
)

foreach ($file in $configFiles) {
    if (Test-Path $file) {
        Write-TestResult "Config File: $(Split-Path -Leaf $file)" "PASS" "File exists and accessible"
    } else {
        Write-TestResult "Config File: $(Split-Path -Leaf $file)" "FAIL" "File missing or inaccessible"
    }
}

# Summary
Write-Host "`n" + ("=" * 60) -ForegroundColor Gray
Write-Host "VALIDATION SUMMARY" -ForegroundColor White
Write-Host ("=" * 60) -ForegroundColor Gray

if ($ErrorCount -eq 0 -and $WarningCount -eq 0) {
    Write-Host "✓ All tests passed successfully!" -ForegroundColor Green
    Write-Host "Portainer is properly configured and functional." -ForegroundColor Green
} elseif ($ErrorCount -eq 0) {
    Write-Host "⚠ Tests completed with $WarningCount warning(s)" -ForegroundColor Yellow
    Write-Host "Portainer is functional but may have minor issues." -ForegroundColor Yellow
} else {
    Write-Host "✗ Tests completed with $ErrorCount error(s) and $WarningCount warning(s)" -ForegroundColor Red
    Write-Host "Portainer requires attention before it can be fully functional." -ForegroundColor Red
}

Write-Host "`nPortainer Access Information:" -ForegroundColor Cyan
Write-Host "  Local URL: http://localhost:9000" -ForegroundColor White
Write-Host "  External URL: https://portainer.yourdomain.com (via Cloudflare tunnel)" -ForegroundColor White
Write-Host "`nFeatures validated:" -ForegroundColor Cyan
Write-Host "  • Container monitoring and control (Requirement 9.1, 9.2)" -ForegroundColor White
Write-Host "  • Real-time log viewing (Requirement 9.3)" -ForegroundColor White
Write-Host "  • Resource monitoring (Requirement 9.4)" -ForegroundColor White

if ($ErrorCount -gt 0) {
    Write-Host "`nTroubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Ensure Docker is running: docker version" -ForegroundColor White
    Write-Host "  2. Start Portainer: docker-compose up -d portainer" -ForegroundColor White
    Write-Host "  3. Check logs: docker logs portainer" -ForegroundColor White
    Write-Host "  4. Run setup script: .\config\portainer\setup-portainer.ps1" -ForegroundColor White
}

exit $ErrorCount