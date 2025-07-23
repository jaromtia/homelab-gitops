# SSL Certificate Health Check and Monitoring Script (PowerShell)
# This script monitors SSL certificate expiration and handles renewal errors

param(
    [string]$Domain = $env:DOMAIN,
    [int]$AlertDays = 30,
    [int]$CriticalDays = 7,
    [string]$LogFile = ".\logs\ssl-health-check.log",
    [string]$TraefikContainer = "traefik",
    [string]$Command = "check"
)

# Ensure log directory exists
$logDir = Split-Path $LogFile -Parent
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Logging function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage
}

# Error handling
function Write-ErrorExit {
    param([string]$Message)
    Write-Log "ERROR: $Message"
    exit 1
}

# Check if required tools are available
function Test-Dependencies {
    Write-Log "Checking dependencies..."
    
    $deps = @("docker")
    foreach ($dep in $deps) {
        if (!(Get-Command $dep -ErrorAction SilentlyContinue)) {
            Write-ErrorExit "$dep is required but not installed"
        }
    }
    Write-Log "✓ All dependencies available"
}

# Check Traefik container status
function Test-TraefikStatus {
    Write-Log "Checking Traefik container status..."
    
    try {
        $containers = docker ps --filter "name=$TraefikContainer" --filter "status=running" --format "{{.Names}}"
        if ($containers -notcontains $TraefikContainer) {
            Write-ErrorExit "Traefik container is not running"
        }
        
        # Check Traefik health endpoint
        $response = Invoke-WebRequest -Uri "http://localhost:8080/ping" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ($response.StatusCode -ne 200) {
            Write-ErrorExit "Traefik health check failed"
        }
        
        Write-Log "✓ Traefik is running and healthy"
    }
    catch {
        Write-ErrorExit "Failed to check Traefik status: $($_.Exception.Message)"
    }
}

# Check SSL certificate expiration
function Test-CertificateExpiration {
    param([string]$DomainToCheck)
    
    Write-Log "Checking SSL certificate for $DomainToCheck..."
    
    try {
        # Use .NET to check certificate
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect($DomainToCheck, 443)
        
        $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream())
        $sslStream.AuthenticateAsClient($DomainToCheck)
        
        $cert = $sslStream.RemoteCertificate
        $cert2 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cert)
        
        $expirationDate = $cert2.NotAfter
        $daysUntilExp = ($expirationDate - (Get-Date)).Days
        
        $sslStream.Close()
        $tcpClient.Close()
        
        if ($daysUntilExp -lt $CriticalDays) {
            Write-Log "CRITICAL: Certificate for $DomainToCheck expires in $daysUntilExp days" -ForegroundColor Red
            return 2
        }
        elseif ($daysUntilExp -lt $AlertDays) {
            Write-Log "WARNING: Certificate for $DomainToCheck expires in $daysUntilExp days" -ForegroundColor Yellow
            return 1
        }
        else {
            Write-Log "✓ Certificate for $DomainToCheck is valid for $daysUntilExp days" -ForegroundColor Green
            return 0
        }
    }
    catch {
        Write-Log "WARNING: Could not retrieve certificate information for $DomainToCheck : $($_.Exception.Message)"
        return 1
    }
}

# Validate domain accessibility
function Test-DomainAccessibility {
    param([string]$DomainToTest)
    
    try {
        # Check DNS resolution
        $dnsResult = Resolve-DnsName -Name $DomainToTest -ErrorAction Stop
        if (-not $dnsResult) {
            Write-Log "WARNING: DNS resolution failed for $DomainToTest"
            return $false
        }
        
        # Check if port 80 is reachable (for ACME HTTP challenge)
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connectTask = $tcpClient.ConnectAsync($DomainToTest, 80)
        $timeout = [System.Threading.Tasks.Task]::Delay(10000)  # 10 second timeout
        
        $completedTask = [System.Threading.Tasks.Task]::WaitAny(@($connectTask, $timeout))
        
        if ($completedTask -eq 0 -and $tcpClient.Connected) {
            $tcpClient.Close()
            return $true
        } else {
            Write-Log "WARNING: Port 80 not reachable on $DomainToTest"
            $tcpClient.Close()
            return $false
        }
    }
    catch {
        Write-Log "WARNING: Domain accessibility check failed for $DomainToTest : $($_.Exception.Message)"
        return $false
    }
}

# Force certificate renewal with enhanced error handling
function Invoke-ForceRenewal {
    param([string]$DomainToRenew)
    
    Write-Log "Forcing certificate renewal for $DomainToRenew..."
    
    # Validate domain accessibility before renewal
    if (-not (Test-DomainAccessibility -DomainToTest $DomainToRenew)) {
        Write-Log "WARNING: Domain $DomainToRenew is not accessible, renewal may fail"
    }
    
    try {
        # Check Traefik container health before restart
        $containers = docker ps --filter "name=$TraefikContainer" --filter "status=running" --format "{{.Names}}"
        if ($containers -notcontains $TraefikContainer) {
            Write-Log "Traefik container is not running, starting it..."
            docker start $TraefikContainer | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-ErrorExit "Failed to start Traefik container"
            }
        }
        
        # Restart Traefik to trigger renewal
        Write-Log "Restarting Traefik container to trigger certificate renewal..."
        docker restart $TraefikContainer | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorExit "Failed to restart Traefik container"
        }
        
        # Wait for container to be healthy with exponential backoff
        $retries = 30
        $waitTime = 2
        $healthy = $false
        
        while ($retries -gt 0 -and -not $healthy) {
            try {
                $containers = docker ps --filter "name=$TraefikContainer" --filter "status=running" --format "{{.Names}}"
                if ($containers -contains $TraefikContainer) {
                    $response = Invoke-WebRequest -Uri "http://localhost:8080/ping" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                    if ($response.StatusCode -eq 200) {
                        $healthy = $true
                        Write-Log "✓ Traefik restarted successfully"
                        
                        # Additional validation: check if Traefik can access ACME storage
                        try {
                            docker exec $TraefikContainer ls /letsencrypt/acme.json | Out-Null
                            if ($LASTEXITCODE -eq 0) {
                                Write-Log "✓ ACME storage accessible from container"
                            } else {
                                Write-Log "WARNING: ACME storage not accessible from container"
                            }
                        }
                        catch {
                            Write-Log "WARNING: Could not verify ACME storage accessibility"
                        }
                        return
                    }
                }
            }
            catch {
                # Continue waiting
            }
            
            Write-Log "Waiting for Traefik to become healthy... (attempt $((31-$retries))/30)"
            Start-Sleep -Seconds $waitTime
            
            # Exponential backoff, max 10 seconds
            if ($waitTime -lt 10) {
                $waitTime = $waitTime * 2
            }
            
            $retries--
        }
        
        if (-not $healthy) {
            # If restart failed, try to diagnose the issue
            Write-Log "Traefik restart failed, attempting diagnosis..."
            try {
                $logs = docker logs $TraefikContainer --tail 50
                Write-Log "Recent Traefik logs: $logs"
            }
            catch {
                Write-Log "Could not retrieve Traefik logs for diagnosis"
            }
            
            Write-ErrorExit "Traefik failed to restart properly after certificate renewal attempt"
        }
    }
    catch {
        Write-ErrorExit "Failed to restart Traefik: $($_.Exception.Message)"
    }
}

# Monitor certificate renewal process
function Watch-Renewal {
    param([string]$DomainToMonitor)
    
    Write-Log "Monitoring certificate renewal for $DomainToMonitor..."
    
    $maxWait = 300  # 5 minutes
    $waitTime = 0
    
    while ($waitTime -lt $maxWait) {
        $certStatus = Test-CertificateExpiration -DomainToCheck $DomainToMonitor
        if ($certStatus -eq 0) {
            Write-Log "✓ Certificate renewal completed successfully"
            return $true
        }
        
        Start-Sleep -Seconds 10
        $waitTime += 10
        Write-Log "Waiting for renewal... ($waitTime/${maxWait}s)"
    }
    
    Write-Log "WARNING: Certificate renewal monitoring timed out"
    return $false
}

# Main health check function
function Invoke-MainHealthCheck {
    Write-Log "Starting SSL health check..."
    
    Test-Dependencies
    Test-TraefikStatus
    
    if ([string]::IsNullOrEmpty($Domain)) {
        Write-Log "WARNING: No domain specified, skipping certificate check"
        return
    }
    
    # Check main domain certificate
    $certStatus = Test-CertificateExpiration -DomainToCheck $Domain
    
    # If certificate is critical, attempt renewal
    if ($certStatus -eq 2) {
        Write-Log "Attempting automatic certificate renewal..."
        Invoke-ForceRenewal -DomainToRenew $Domain
        Watch-Renewal -DomainToMonitor $Domain | Out-Null
    }
    
    Write-Log "SSL health check completed"
}

# Main execution
switch ($Command.ToLower()) {
    "check" {
        Invoke-MainHealthCheck
    }
    "renew" {
        if ([string]::IsNullOrEmpty($Domain)) {
            Write-ErrorExit "Domain required for renewal command"
        }
        Invoke-ForceRenewal -DomainToRenew $Domain
        Watch-Renewal -DomainToMonitor $Domain | Out-Null
    }
    "monitor" {
        Write-Log "Starting continuous monitoring mode..."
        while ($true) {
            Invoke-MainHealthCheck
            Start-Sleep -Seconds 3600  # Check every hour
        }
    }
    default {
        Write-Host "Usage: .\ssl-health-check.ps1 [-Domain <domain>] [-Command <check|renew|monitor>]"
        Write-Host ""
        Write-Host "Commands:"
        Write-Host "  check          Run health check (default)"
        Write-Host "  renew          Force certificate renewal for domain"
        Write-Host "  monitor        Continuous monitoring mode"
        Write-Host ""
        Write-Host "Parameters:"
        Write-Host "  -Domain        Domain to check"
        Write-Host "  -AlertDays     Alert threshold in days (default: 30)"
        Write-Host "  -CriticalDays  Critical threshold in days (default: 7)"
        Write-Host "  -LogFile       Log file path"
        exit 1
    }
}