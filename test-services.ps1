# Docker Container Testing Script
# This script tests all running homelab services

Write-Host "=== Homelab Docker Container Testing ===" -ForegroundColor Green
Write-Host ""

# Check Docker Compose status
Write-Host "1. Checking Docker Compose Services Status:" -ForegroundColor Yellow
docker-compose ps
Write-Host ""

# Test individual services
Write-Host "2. Testing Service Endpoints:" -ForegroundColor Yellow

# Test Prometheus
Write-Host "Testing Prometheus (http://localhost:9090)..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "http://localhost:9090" -Method GET -UseBasicParsing -TimeoutSec 5
    Write-Host "✅ Prometheus: $($response.StatusCode) $($response.StatusDescription)" -ForegroundColor Green
} catch {
    Write-Host "❌ Prometheus: Failed - $($_.Exception.Message)" -ForegroundColor Red
}

# Test Portainer
Write-Host "Testing Portainer (http://localhost:9000)..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "http://localhost:9000" -Method GET -UseBasicParsing -TimeoutSec 5
    Write-Host "✅ Portainer: $($response.StatusCode) $($response.StatusDescription)" -ForegroundColor Green
} catch {
    Write-Host "❌ Portainer: Failed - $($_.Exception.Message)" -ForegroundColor Red
}

# Test FileBrowser
Write-Host "Testing FileBrowser (http://localhost:8082)..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8082" -Method GET -UseBasicParsing -TimeoutSec 5
    Write-Host "✅ FileBrowser: $($response.StatusCode) $($response.StatusDescription)" -ForegroundColor Green
} catch {
    Write-Host "❌ FileBrowser: Failed - $($_.Exception.Message)" -ForegroundColor Red
}

# Test Dashy
Write-Host "Testing Dashy (http://localhost:80)..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "http://localhost:80" -Method GET -UseBasicParsing -TimeoutSec 5
    Write-Host "✅ Dashy: $($response.StatusCode) $($response.StatusDescription)" -ForegroundColor Green
} catch {
    Write-Host "❌ Dashy: Failed - $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Check container health
Write-Host "3. Container Health Status:" -ForegroundColor Yellow
$containers = docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
Write-Host $containers

Write-Host ""

# Show resource usage
Write-Host "4. Resource Usage:" -ForegroundColor Yellow
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

Write-Host ""
Write-Host "=== Testing Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "🌐 Access URLs:" -ForegroundColor Magenta
Write-Host "  • Prometheus: http://localhost:9090" -ForegroundColor White
Write-Host "  • Portainer:  http://localhost:9000" -ForegroundColor White  
Write-Host "  • FileBrowser: http://localhost:8082" -ForegroundColor White
Write-Host "  • Dashy:      http://localhost:80 (may have issues)" -ForegroundColor White
Write-Host ""
Write-Host "📊 To open services in browser:" -ForegroundColor Magenta
Write-Host "  Start-Process 'http://localhost:9090'  # Prometheus" -ForegroundColor Gray
Write-Host "  Start-Process 'http://localhost:9000'  # Portainer" -ForegroundColor Gray
Write-Host "  Start-Process 'http://localhost:8082'  # FileBrowser" -ForegroundColor Gray