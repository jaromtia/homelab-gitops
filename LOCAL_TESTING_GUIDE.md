# Local Docker Container Testing Guide

This guide shows you how to test your homelab infrastructure locally before deploying to production.

## Prerequisites

1. **Docker and Docker Compose installed**
2. **Environment file configured** (`.env` file exists)
3. **Configuration files in place** (config directory populated)

## Quick Start - Test All Services

### 1. Environment Setup Check

First, verify your environment is ready:

```powershell
# Check if Docker is running
docker --version
docker-compose --version

# Verify environment file exists
Get-Content .env | Select-String "DOMAIN"
```

### 2. Start Core Services (Without Cloudflare Tunnel)

For local testing, we'll start services without the Cloudflare tunnel to avoid external dependencies:

```powershell
# Start monitoring stack first
docker-compose up -d prometheus grafana loki promtail node-exporter cadvisor

# Wait a moment for services to initialize, then check status
docker-compose ps

# Check logs for any issues
docker-compose logs prometheus
docker-compose logs grafana
```

### 3. Start Dashboard and Management Services

```powershell
# Start dashboard and container management
docker-compose up -d dashy portainer

# Check status
docker-compose ps dashy portainer
```

### 4. Start Application Services

```powershell
# Start productivity and file management services
docker-compose up -d filebrowser linkding actual

# Check all services
docker-compose ps
```

## Individual Service Testing

### Monitoring Stack

#### Prometheus (Metrics Collection)
```powershell
# Start Prometheus
docker-compose up -d prometheus

# Test access
Start-Process "http://localhost:9090"

# Check targets are being scraped
# Navigate to Status > Targets in the web UI
```

#### Grafana (Dashboards)
```powershell
# Start Grafana (requires Prometheus)
docker-compose up -d prometheus grafana

# Access Grafana
Start-Process "http://localhost:3000"

# Default login: admin / your-secure-password (from .env)
```

#### Loki & Promtail (Log Aggregation)
```powershell
# Start log stack
docker-compose up -d loki promtail

# Check Loki is receiving logs
Invoke-WebRequest -Uri "http://localhost:3100/ready" -Method GET
```

### Dashboard Services

#### Dashy (Main Dashboard)
```powershell
# Start Dashy
docker-compose up -d dashy

# Access dashboard
Start-Process "http://localhost:80"
```

#### Portainer (Container Management)
```powershell
# Start Portainer
docker-compose up -d portainer

# Access Portainer
Start-Process "http://localhost:9000"

# First time setup will require creating admin user
```

### Application Services

#### FileBrowser (File Management)
```powershell
# Start FileBrowser
docker-compose up -d filebrowser

# Access FileBrowser
Start-Process "http://localhost:8082"

# Check file access to ./data/files directory
```

#### Linkding (Bookmark Manager)
```powershell
# Start Linkding
docker-compose up -d linkding

# Access Linkding
Start-Process "http://localhost:9090"

# Login with credentials from .env file
```

#### Actual Budget (Finance Manager)
```powershell
# Start Actual Budget
docker-compose up -d actual

# Access Actual Budget
Start-Process "http://localhost:5006"
```

## Health Check Testing

### Automated Health Checks
```powershell
# Check health status of all services
docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# View detailed health check results
docker inspect $(docker-compose ps -q) --format='{{.Name}}: {{.State.Health.Status}}'
```

### Manual Service Testing
```powershell
# Test Prometheus metrics endpoint
Invoke-WebRequest -Uri "http://localhost:9090/metrics" -Method GET

# Test Grafana health
Invoke-WebRequest -Uri "http://localhost:3000/api/health" -Method GET

# Test Loki readiness
Invoke-WebRequest -Uri "http://localhost:3100/ready" -Method GET

# Test Dashy
Invoke-WebRequest -Uri "http://localhost:80" -Method GET

# Test Portainer API
Invoke-WebRequest -Uri "http://localhost:9000/api/status" -Method GET
```

## Network Testing

### Check Network Connectivity
```powershell
# List Docker networks
docker network ls | Select-String "homelab"

# Inspect frontend network
docker network inspect homelab_frontend

# Test inter-service communication
docker-compose exec prometheus wget -qO- http://node-exporter:9100/metrics
docker-compose exec grafana wget -qO- http://prometheus:9090/api/v1/status/config
```

## Volume and Data Testing

### Check Volume Mounts
```powershell
# List Docker volumes
docker volume ls | Select-String "homelab"

# Inspect volume details
docker volume inspect homelab_prometheus_data
docker volume inspect homelab_grafana_data

# Check file permissions and data
docker-compose exec prometheus ls -la /prometheus
docker-compose exec grafana ls -la /var/lib/grafana
```

### Test File Browser Access
```powershell
# Check if data directory is accessible
docker-compose exec filebrowser ls -la /srv

# Test file operations (create test file)
New-Item -Path "./data/files/test.txt" -ItemType File -Value "Test file for FileBrowser"

# Verify in FileBrowser UI at http://localhost:8082
```

## Troubleshooting Commands

### View Logs
```powershell
# View logs for specific service
docker-compose logs -f prometheus
docker-compose logs -f grafana
docker-compose logs -f dashy

# View logs for all services
docker-compose logs --tail=50

# Follow logs in real-time
docker-compose logs -f
```

### Restart Services
```powershell
# Restart specific service
docker-compose restart prometheus

# Restart all services
docker-compose restart

# Force recreate containers
docker-compose up -d --force-recreate
```

### Clean Up
```powershell
# Stop all services
docker-compose down

# Stop and remove volumes (WARNING: This deletes data!)
docker-compose down -v

# Remove unused Docker resources
docker system prune -f
```

## Service Access URLs (Local Testing)

| Service | URL | Default Credentials |
|---------|-----|-------------------|
| Dashy | http://localhost:80 | None |
| Grafana | http://localhost:3000 | admin / (from .env) |
| Prometheus | http://localhost:9090 | None |
| Portainer | http://localhost:9000 | Setup on first visit |
| FileBrowser | http://localhost:8082 | admin / admin |
| Linkding | http://localhost:9090 | (from .env) |
| Actual Budget | http://localhost:5006 | (from .env) |
| Duplicati | http://localhost:8200 | Setup on first visit |
| Node Exporter | http://localhost:9100 | None |
| cAdvisor | http://localhost:8081 | None |

## Testing Scenarios

### Scenario 1: Basic Monitoring Stack
```powershell
# Start monitoring services
docker-compose up -d prometheus grafana node-exporter

# Wait 30 seconds for initialization
Start-Sleep -Seconds 30

# Test Prometheus targets
Start-Process "http://localhost:9090/targets"

# Test Grafana with Prometheus data source
Start-Process "http://localhost:3000"
```

### Scenario 2: Complete Dashboard Experience
```powershell
# Start all dashboard services
docker-compose up -d dashy prometheus grafana portainer

# Test main dashboard
Start-Process "http://localhost:80"

# Verify all service links work from Dashy
```

### Scenario 3: File and Data Management
```powershell
# Start file and backup services
docker-compose up -d filebrowser duplicati

# Create test files
New-Item -Path "./data/files/documents" -ItemType Directory -Force
New-Item -Path "./data/files/documents/test.txt" -ItemType File -Value "Test document"

# Test file access
Start-Process "http://localhost:8082"

# Test backup interface
Start-Process "http://localhost:8200"
```

## Performance Testing

### Resource Usage Monitoring
```powershell
# Monitor container resource usage
docker stats

# Check specific container resources
docker stats prometheus grafana dashy --no-stream

# Monitor disk usage
docker system df
```

### Load Testing
```powershell
# Generate some metrics load
for ($i=1; $i -le 100; $i++) {
    Invoke-WebRequest -Uri "http://localhost:9090/api/v1/query?query=up" -Method GET
    Start-Sleep -Milliseconds 100
}

# Check Grafana dashboard performance
for ($i=1; $i -le 50; $i++) {
    Invoke-WebRequest -Uri "http://localhost:3000/api/health" -Method GET
    Start-Sleep -Milliseconds 200
}
```

## Next Steps

After local testing is successful:

1. **Configure Cloudflare Tunnel** for external access
2. **Set up proper SSL certificates** 
3. **Configure backup schedules** in Duplicati
4. **Customize Grafana dashboards** for your needs
5. **Set up alerting rules** in Prometheus
6. **Deploy to production environment**

## Common Issues and Solutions

### Port Conflicts
If you get port binding errors:
```powershell
# Check what's using the port
netstat -ano | findstr :9090

# Stop conflicting services or change ports in docker-compose.yml
```

### Permission Issues
```powershell
# Fix volume permissions (if needed)
docker-compose exec prometheus chown -R nobody:nobody /prometheus
docker-compose exec grafana chown -R 472:472 /var/lib/grafana
```

### Service Dependencies
```powershell
# Start services in dependency order
docker-compose up -d prometheus
Start-Sleep -Seconds 10
docker-compose up -d grafana
Start-Sleep -Seconds 10
docker-compose up -d dashy
```