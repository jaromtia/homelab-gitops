# Cloudflare Tunnel Validation Script (PowerShell)
param([switch]$Detailed)

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ConfigFile = Join-Path $ProjectRoot "config\cloudflared\config.yml"
$EnvFile = Join-Path $ProjectRoot ".env"

function Write-Log {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Test-ConfigFiles {
    Write-Log "Validating configuration files..."
    $success = $true
    
    if (Test-Path $ConfigFile) {
        Write-Success "Configuration file exists"
        $configContent = Get-Content $ConfigFile -Raw
        if ($configContent -match "YOUR_TUNNEL_ID") {
            Write-Warning "Configuration contains placeholder tunnel ID"
        } else {
            Write-Success "Tunnel ID configured"
        }
    } else {
        Write-Error "Configuration file not found: $ConfigFile"
        $success = $false
    }
    
    return $success
}

function Test-Docker {
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
        Write-Error "Docker is not accessible"
        return $false
    }
}

Write-Host "Cloudflare Tunnel Configuration Validation" -ForegroundColor White
Write-Host "==========================================" -ForegroundColor White
Write-Host ""

$overallSuccess = $true

if (-not (Test-Docker)) { $overallSuccess = $false }
if (-not (Test-ConfigFiles)) { $overallSuccess = $false }

if ($overallSuccess) {
    Write-Host ""
    Write-Success "Basic validation completed successfully!"
} else {
    Write-Host ""
    Write-Error "Validation completed with errors."
}