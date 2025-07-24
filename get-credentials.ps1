# Get Service Credentials Script
# This script helps you find the current credentials for your homelab services

Write-Host "=== Homelab Service Credentials ===" -ForegroundColor Green
Write-Host ""

# Check if Docker Compose is running
try {
    $services = docker-compose ps --format json | ConvertFrom-Json
    if ($services.Count -eq 0) {
        Write-Host "❌ No services are currently running. Start services with: docker-compose up -d" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ Docker Compose not available or no services running" -ForegroundColor Red
    exit 1
}

Write-Host "🔍 Finding service credentials..." -ForegroundColor Yellow
Write-Host ""

# FileBrowser Password
Write-Host "📁 FileBrowser (http://localhost:8082):" -ForegroundColor Cyan
try {
    $filebrowserLogs = docker-compose logs filebrowser 2>$null
    $passwordLine = $filebrowserLogs | Select-String "randomly generated password"
    if ($passwordLine) {
        $password = ($passwordLine -split "password: ")[1]
        Write-Host "   Username: admin" -ForegroundColor Green
        Write-Host "   Password: $password" -ForegroundColor Green
    } else {
        Write-Host "   ❌ No password found in logs. Service may not be running or needs reset." -ForegroundColor Red
        Write-Host "   Try: docker-compose restart filebrowser" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ❌ FileBrowser service not found" -ForegroundColor Red
}

Write-Host ""

# Portainer Status
Write-Host "🐳 Portainer (http://localhost:9000):" -ForegroundColor Cyan
try {
    $portainerLogs = docker-compose logs portainer --tail=10 2>$null
    if ($portainerLogs -match "timed out for security purposes") {
        Write-Host "   ⚠️  Setup window timed out. Restart with: docker-compose restart portainer" -ForegroundColor Yellow
        Write-Host "   Then access http://localhost:9000 within 5 minutes to create admin user" -ForegroundColor Yellow
    } else {
        Write-Host "   ✅ Ready for setup at http://localhost:9000" -ForegroundColor Green
        Write-Host "   Create admin user on first visit (within 5 minutes of startup)" -ForegroundColor Green
    }
} catch {
    Write-Host "   ❌ Portainer service not found" -ForegroundColor Red
}

Write-Host ""

# Grafana Credentials
Write-Host "📊 Grafana (http://localhost:3000):" -ForegroundColor Cyan
try {
    $grafanaUser = docker-compose exec grafana env 2>$null | Select-String "GF_SECURITY_ADMIN_USER"
    $grafanaPass = docker-compose exec grafana env 2>$null | Select-String "GF_SECURITY_ADMIN_PASSWORD"
    
    if ($grafanaUser -and $grafanaPass) {
        $user = ($grafanaUser -split "=")[1]
        $pass = ($grafanaPass -split "=")[1]
        Write-Host "   Username: $user" -ForegroundColor Green
        Write-Host "   Password: $pass" -ForegroundColor Green
    } else {
        Write-Host "   Username: admin" -ForegroundColor Green
        Write-Host "   Password: Check .env file for GRAFANA_ADMIN_PASSWORD" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ❌ Grafana service not found or not responding" -ForegroundColor Red
}

Write-Host ""

# Prometheus (no auth)
Write-Host "📈 Prometheus (http://localhost:9090):" -ForegroundColor Cyan
Write-Host "   ✅ No authentication required" -ForegroundColor Green

Write-Host ""

# Environment file check
Write-Host "📄 Environment File (.env):" -ForegroundColor Cyan
if (Test-Path ".env") {
    Write-Host "   ✅ .env file exists" -ForegroundColor Green
    Write-Host "   Check the following variables for service passwords:" -ForegroundColor Yellow
    Write-Host "   - GRAFANA_ADMIN_PASSWORD" -ForegroundColor Gray
    Write-Host "   - LINKDING_SUPERUSER_PASSWORD" -ForegroundColor Gray
    Write-Host "   - ACTUAL_PASSWORD" -ForegroundColor Gray
    Write-Host "   - DUPLICATI_PASSWORD" -ForegroundColor Gray
} else {
    Write-Host "   ❌ .env file not found. Copy from .env.template" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Quick Access Commands ===" -ForegroundColor Green
Write-Host "Start-Process 'http://localhost:9090'   # Prometheus" -ForegroundColor Gray
Write-Host "Start-Process 'http://localhost:3000'   # Grafana" -ForegroundColor Gray
Write-Host "Start-Process 'http://localhost:9000'   # Portainer" -ForegroundColor Gray
Write-Host "Start-Process 'http://localhost:8082'   # FileBrowser" -ForegroundColor Gray