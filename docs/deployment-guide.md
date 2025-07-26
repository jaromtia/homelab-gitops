# Comprehensive Deployment Guide

This guide provides complete instructions for deploying the homelab infrastructure from scratch, including prerequisites, configuration, and verification steps.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Environment Configuration](#environment-configuration)
4. [Cloudflare Tunnel Setup](#cloudflare-tunnel-setup)
5. [Service Deployment](#service-deployment)
6. [Post-Deployment Configuration](#post-deployment-configuration)
7. [Verification and Testing](#verification-and-testing)
8. [GitHub Integration Setup](#github-integration-setup)

## Prerequisites

### System Requirements

- **Operating System**: Windows 10/11 or Windows Server 2019+
- **RAM**: Minimum 8GB, Recommended 16GB+
- **Storage**: Minimum 50GB free space, Recommended 100GB+
- **Network**: Stable internet connection with minimum 10Mbps upload

### Software Requirements

1. **Docker Desktop for Windows**
   ```powershell
   # Download from https://www.docker.com/products/docker-desktop
   # Or install via Chocolatey
   choco install docker-desktop
   ```

2. **Git for Windows**
   ```powershell
   # Download from https://git-scm.com/download/win
   # Or install via Chocolatey
   choco install git
   ```

3. **PowerShell 5.1 or later** (included with Windows)

### Account Requirements

1. **Cloudflare Account** (Free tier sufficient)
   - Domain registered and managed by Cloudflare
   - API token with Zone:Read and Zone:Edit permissions

2. **GitHub Account** (Free tier sufficient)
   - Personal access token with repo permissions

## Initial Setup

### 1. Clone Repository

```powershell
# Clone the repository
git clone https://github.com/your-username/homelab-infrastructure.git
cd homelab-infrastructure

# Verify directory structure
Get-ChildItem -Recurse -Directory | Select-Object Name
```

### 2. Create Directory Structure

```powershell
# Create required directories
New-Item -ItemType Directory -Force -Path @(
    "data/files",
    "data/backups",
    "data/logs",
    "config/cloudflared",
    "config/grafana/provisioning/dashboards",
    "config/grafana/provisioning/datasources",
    "config/prometheus",
    "config/loki",
    "config/promtail",
    "config/dashy"
)

# Verify directory creation
Get-ChildItem -Recurse -Directory | Where-Object {$_.Name -match "config|data"}
```

### 3. Set Permissions

```powershell
# Set appropriate permissions for data directories
icacls "data" /grant "Everyone:(OI)(CI)F" /T
icacls "config" /grant "Everyone:(OI)(CI)F" /T
```

## Environment Configuration

### 1. Create Environment File

```powershell
# Copy template to create .env file
Copy-Item .env.template .env

# Edit the .env file with your specific values
notepad .env
```

### 2. Required Environment Variables

Update the following variables in your `.env` file:

```bash
# Domain Configuration
DOMAIN=yourdomain.com
TUNNEL_ID=your-tunnel-id

# Service Passwords (Generate strong passwords)
GRAFANA_ADMIN_PASSWORD=your-secure-password
LINKDING_SUPERUSER_PASSWORD=your-secure-password
ACTUAL_PASSWORD=your-secure-password
DUPLICATI_PASSWORD=your-secure-password
FILEBROWSER_ADMIN_PASSWORD=your-secure-password

# GitHub Integration
GITHUB_USERNAME=your-github-username
GITHUB_TOKEN=your-github-token
GITHUB_REPO=your-username/homelab-infrastructure
GITHUB_REPO_URL=https://github.com/your-username/homelab-infrastructure.git

# Backup Configuration
BACKUP_ENCRYPTION_PASSWORD=your-backup-encryption-password
BACKUP_RETENTION_DAYS=30
```

### 3. Generate Secure Passwords

```powershell
# Generate secure passwords for services
function New-SecurePassword {
    param([int]$Length = 16)
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"
    $password = ""
    for ($i = 0; $i -lt $Length; $i++) {
        $password += $chars[(Get-Random -Maximum $chars.Length)]
    }
    return $password
}

# Generate passwords for each service
Write-Host "Generated Passwords:"
Write-Host "GRAFANA_ADMIN_PASSWORD=$(New-SecurePassword)"
Write-Host "LINKDING_SUPERUSER_PASSWORD=$(New-SecurePassword)"
Write-Host "ACTUAL_PASSWORD=$(New-SecurePassword)"
Write-Host "DUPLICATI_PASSWORD=$(New-SecurePassword)"
Write-Host "FILEBROWSER_ADMIN_PASSWORD=$(New-SecurePassword)"
Write-Host "BACKUP_ENCRYPTION_PASSWORD=$(New-SecurePassword 32)"
```

## Cloudflare Tunnel Setup

### 1. Install Cloudflared

```powershell
# Download cloudflared
Invoke-WebRequest -Uri "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -OutFile "cloudflared.exe"

# Move to system PATH
Move-Item cloudflared.exe "C:\Windows\System32\cloudflared.exe"

# Verify installation
cloudflared --version
```

### 2. Authenticate with Cloudflare

```powershell
# Login to Cloudflare
cloudflared tunnel login

# This will open a browser window for authentication
# Select your domain when prompted
```

### 3. Create Tunnel

```powershell
# Create a new tunnel
cloudflared tunnel create homelab

# Note the tunnel ID from the output
# Update TUNNEL_ID in your .env file
```

### 4. Configure Tunnel Credentials

```powershell
# Copy tunnel credentials to config directory
$tunnelId = "your-tunnel-id-here"
Copy-Item "$env:USERPROFILE\.cloudflared\$tunnelId.json" "config\cloudflared\credentials.json"
```

### 5. Create Tunnel Configuration

Create `config/cloudflared/config.yml`:

```yaml
tunnel: your-tunnel-id-here
credentials-file: /etc/cloudflared/credentials.json

ingress:
  # Dashboard
  - hostname: dashboard.yourdomain.com
    service: http://dashy:80
  
  # Monitoring
  - hostname: grafana.yourdomain.com
    service: http://grafana:3000
  - hostname: prometheus.yourdomain.com
    service: http://prometheus:9090
  
  # Management
  - hostname: portainer.yourdomain.com
    service: http://portainer:9000
  - hostname: files.yourdomain.com
    service: http://filebrowser:80
  - hostname: backup.yourdomain.com
    service: http://duplicati:8200
  
  # Applications
  - hostname: bookmarks.yourdomain.com
    service: http://linkding:9090
  - hostname: budget.yourdomain.com
    service: http://actual:5006
  
  # Catch-all rule
  - service: http_status:404
```

### 6. Configure DNS Records

```powershell
# Add CNAME records for each subdomain pointing to your-tunnel-id.cfargotunnel.com
# This can be done via Cloudflare dashboard or API
```

## Service Deployment

### 1. Validate Configuration

```powershell
# Validate Docker Compose configuration
docker-compose config

# Check for syntax errors
if ($LASTEXITCODE -eq 0) {
    Write-Host "Configuration is valid" -ForegroundColor Green
} else {
    Write-Host "Configuration has errors" -ForegroundColor Red
    exit 1
}
```

### 2. Deploy Core Infrastructure

```powershell
# Start core services first
docker-compose up -d cloudflared prometheus grafana loki promtail

# Wait for services to initialize
Start-Sleep -Seconds 30

# Check service status
docker-compose ps
```

### 3. Deploy Monitoring Stack

```powershell
# Start monitoring components
docker-compose up -d node-exporter cadvisor

# Verify monitoring stack
docker-compose logs prometheus | Select-String "Server is ready"
docker-compose logs grafana | Select-String "HTTP Server Listen"
```

### 4. Deploy Application Services

```powershell
# Start application services
docker-compose up -d dashy portainer filebrowser linkding actual duplicati

# Wait for services to start
Start-Sleep -Seconds 60

# Check all services
docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
```

### 5. Full Deployment (Alternative)

```powershell
# Deploy all services at once
docker-compose up -d

# Monitor startup logs
docker-compose logs -f --tail=50
```

## Post-Deployment Configuration

### 1. Configure Grafana

```powershell
# Wait for Grafana to be ready
do {
    $response = try { Invoke-WebRequest -Uri "http://localhost:3000/api/health" -UseBasicParsing } catch { $null }
    if ($response.StatusCode -eq 200) { break }
    Write-Host "Waiting for Grafana to start..."
    Start-Sleep -Seconds 5
} while ($true)

# Access Grafana at http://localhost:3000
# Login with admin and password from .env
Start-Process "http://localhost:3000"
```

### 2. Configure Portainer

```powershell
# Access Portainer within 5 minutes of startup
Start-Process "http://localhost:9000"

# Create admin user account
# Select "Docker" environment
# Connect to local Docker socket
```

### 3. Configure Duplicati

```powershell
# Access Duplicati
Start-Process "http://localhost:8200"

# Set up backup jobs for:
# - Configuration files
# - Service data volumes
# - Important user data
```

### 4. Configure FileBrowser

```powershell
# Get FileBrowser password
$password = docker-compose logs filebrowser | Select-String "randomly generated password" | ForEach-Object { ($_ -split ": ")[1] }
Write-Host "FileBrowser Password: $password"

# Access FileBrowser
Start-Process "http://localhost:8082"
```

## Verification and Testing

### 1. Service Health Checks

```powershell
# Run comprehensive health checks
.\scripts\run-health-tests.ps1

# Check individual services
.\scripts\test-service-health.ps1
```

### 2. Network Connectivity Tests

```powershell
# Test internal network connectivity
.\scripts\test-network-connectivity.ps1

# Test tunnel connectivity
.\scripts\test-tunnel-connectivity.ps1
```

### 3. Backup System Tests

```powershell
# Test backup integrity
.\scripts\test-backup-integrity.ps1

# Validate backup configuration
.\scripts\validate-configuration.ps1
```

### 4. Manual Verification

```powershell
# Test local access to all services
$services = @{
    "Dashy" = "http://localhost:80"
    "Grafana" = "http://localhost:3000"
    "Prometheus" = "http://localhost:9090"
    "Portainer" = "http://localhost:9000"
    "FileBrowser" = "http://localhost:8082"
    "Linkding" = "http://localhost:9091"
    "Actual" = "http://localhost:5006"
    "Duplicati" = "http://localhost:8200"
}

foreach ($service in $services.GetEnumerator()) {
    try {
        $response = Invoke-WebRequest -Uri $service.Value -UseBasicParsing -TimeoutSec 10
        Write-Host "$($service.Key): OK (Status: $($response.StatusCode))" -ForegroundColor Green
    } catch {
        Write-Host "$($service.Key): FAILED ($($_.Exception.Message))" -ForegroundColor Red
    }
}
```

## GitHub Integration Setup

### 1. Initialize Git Repository

```powershell
# Initialize repository if not already done
if (-not (Test-Path ".git")) {
    git init
    git remote add origin $env:GITHUB_REPO_URL
}

# Configure Git user
git config user.name "Your Name"
git config user.email "your.email@example.com"
```

### 2. Initial Commit

```powershell
# Add configuration files to Git
git add .
git commit -m "Initial homelab infrastructure deployment"
git push -u origin main
```

### 3. Set Up Automated Sync

```powershell
# Test GitHub integration
.\scripts\git-ops.ps1 status

# Save current configuration
.\scripts\git-ops.ps1 save "Post-deployment configuration"
```

## Troubleshooting Common Issues

### Docker Issues

```powershell
# Restart Docker Desktop
Restart-Service -Name "com.docker.service" -Force

# Check Docker daemon
docker version
docker system info
```

### Port Conflicts

```powershell
# Check for port conflicts
netstat -ano | findstr ":80 :3000 :9000 :9090"

# Stop conflicting services
Get-Process -Name "nginx","apache","iis*" -ErrorAction SilentlyContinue | Stop-Process -Force
```

### Permission Issues

```powershell
# Fix volume permissions
docker-compose down
Remove-Item -Recurse -Force data\*
docker-compose up -d
```

## Next Steps

After successful deployment:

1. **Customize Dashboards**: Configure Grafana dashboards for your needs
2. **Set Up Alerts**: Configure Prometheus alerting rules
3. **Schedule Backups**: Set up automated backup schedules in Duplicati
4. **Security Hardening**: Review and implement additional security measures
5. **Documentation**: Document any customizations or changes

## Support

For issues during deployment:

1. Check service logs: `docker-compose logs <service-name>`
2. Review configuration: `docker-compose config`
3. Run validation scripts in `scripts/` directory
4. Check GitHub repository for updates and issues
5. Review troubleshooting documentation

## Deployment Checklist

- [ ] Prerequisites installed and verified
- [ ] Repository cloned and directory structure created
- [ ] Environment variables configured
- [ ] Cloudflare tunnel created and configured
- [ ] DNS records configured
- [ ] Services deployed successfully
- [ ] Health checks passing
- [ ] External access working via tunnel
- [ ] Backup system configured
- [ ] GitHub integration set up
- [ ] Documentation reviewed and customized

Deployment is complete when all checklist items are verified and all services are accessible both locally and externally.